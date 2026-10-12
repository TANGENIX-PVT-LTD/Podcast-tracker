import AVFoundation
import Foundation
import YouTubeKit

enum NativePlaybackSource: Hashable {
    case local
    case stream
}

enum YouTubeStreamResolver {
    struct DownloadCandidate: Sendable {
        let videoURL: URL
        let audioURL: URL?
        let height: Int?
        let expectedBytes: Int64?
        let requestHeaders: [String: String]
        let isHLS: Bool
    }
    enum ResolverError: LocalizedError {
        case noPlayableStream
        case assetNotReady
        case invalidVideoID
        case ytDLPUnavailable
        case ytDLPFailed(String)

        var errorDescription: String? {
            switch self {
            case .noPlayableStream: "YouTube did not expose a playable stream for this video."
            case .assetNotReady: "The stream could not be prepared for playback."
            case .invalidVideoID: "The YouTube video ID is invalid."
            case .ytDLPUnavailable: "yt-dlp is not available on this Mac."
            case .ytDLPFailed(let detail): detail
            }
        }
    }

    private struct YTDLPInvocation: Sendable {
        let executableURL: URL
        let argumentPrefix: [String]
    }

    static func playableItem(
        videoId: String,
        source: NativePlaybackSource,
        listenOnly: Bool = false
    ) async throws -> AVPlayerItem {
        if source == .local {
            guard let url = await LocalMediaStore.shared.cachedPlayableURL(videoId: videoId) else {
                throw ResolverError.assetNotReady
            }
            return AVPlayerItem(url: url)
        }
        #if os(macOS) && !APP_STORE
        if let url = try? await ytDLPStreamURL(videoId: videoId) {
            return AVPlayerItem(url: url)
        }
        #endif

        if listenOnly {
            let response = try await resolvedStreamingInfo(videoId: videoId)
            if let originalHLS = try await originalHLSVariantURL(
                from: response,
                maximumHeight: 144,
                preferLowest: true
            ) {
                return AVPlayerItem(url: originalHLS)
            }
            guard let audio = preferredOriginalAudioFormats(from: response.downloadFormats).first,
                  let audioURL = audio.url else {
                throw ResolverError.noPlayableStream
            }
            let asset = AVURLAsset(
                url: audioURL,
                options: ["AVURLAssetHTTPHeaderFieldsKey": requestHeaders(for: response)]
            )
            return AVPlayerItem(asset: asset)
        }

        // Keep regular video playback on the progressive path that proved reliable
        // before offline download support was added. Download resolution is isolated
        // below so it can never change or break streaming again.
        let response = try await legacyStreamingInfo(videoId: videoId)

        let muxed = response.defaultFormats
            .filter { $0.url != nil && $0.mimeType?.hasPrefix("video/mp4") == true }
            .sorted { ($0.height ?? 0) > ($1.height ?? 0) }
        if let url = muxed.first?.url {
            return AVPlayerItem(url: url)
        }

        if let hls = response.videoInfos.streamingURL {
            return AVPlayerItem(url: hls)
        }

        // Progressive/HLS playback is the stable legacy path. Only perform the
        // heavier deciphering pass when neither one is available.
        let resolved = try await resolvedStreamingInfo(videoId: videoId)
        if let originalHLS = try await originalHLSVariantURL(
            from: resolved,
            maximumHeight: 1_080,
            preferLowest: false
        ) {
            return AVPlayerItem(url: originalHLS)
        }
        if let item = try? await adaptiveCompositionItem(
            from: resolved.downloadFormats,
            requestHeaders: requestHeaders(for: resolved)
        ) { return item }

        throw ResolverError.noPlayableStream
    }

    static func downloadableVideo(videoId: String, maximumHeight: Int) async throws -> DownloadCandidate {
        // Resolve downloads independently from playback. Prefer a single muxed
        // progressive file; iOS can persist it without merging two expiring URLs.
        let response = try await legacyStreamingInfo(videoId: videoId)
        let formats = response.defaultFormats
            .filter {
                $0 is VideoDownloadFormat
                    && $0.url != nil
                    && $0.mimeType?.hasPrefix("video/mp4") == true
                    && ($0.height ?? 0) <= maximumHeight
            }
            .sorted {
                let leftHeight = $0.height ?? 0
                let rightHeight = $1.height ?? 0
                return leftHeight == rightHeight
                    ? ($0.averageBitrate ?? 0) > ($1.averageBitrate ?? 0)
                    : leftHeight > rightHeight
            }
        if let format = formats.first, let url = format.url {
            return DownloadCandidate(
                videoURL: url,
                audioURL: nil,
                height: format.height,
                expectedBytes: format.contentLength.map(Int64.init),
                requestHeaders: requestHeaders(for: response),
                isHLS: false
            )
        }

        let resolved = try await resolvedStreamingInfo(videoId: videoId)
        if let originalHLS = try await originalHLSVariantURL(
            from: resolved,
            maximumHeight: maximumHeight,
            preferLowest: false
        ) {
            return DownloadCandidate(
                videoURL: originalHLS,
                audioURL: nil,
                height: maximumHeight,
                expectedBytes: nil,
                requestHeaders: requestHeaders(for: resolved),
                isHLS: true
            )
        }
        let videos = resolved.downloadFormats
            .filter {
                $0 is VideoDownloadFormat
                    && $0.url != nil
                    && $0.mimeType?.hasPrefix("video/mp4") == true
                    && ($0.codec?.hasPrefix("avc1") ?? false)
                    && ($0.height ?? 0) <= maximumHeight
            }
            .sorted { ($0.height ?? 0) > ($1.height ?? 0) }
        let audios = preferredOriginalAudioFormats(from: resolved.downloadFormats)
        guard let video = videos.first, let videoURL = video.url,
              let audio = audios.first, let audioURL = audio.url else {
            throw ResolverError.noPlayableStream
        }
        let expectedBytes: Int64? = {
            guard let videoBytes = video.contentLength, let audioBytes = audio.contentLength else { return nil }
            return Int64(videoBytes) + Int64(audioBytes)
        }()
        return DownloadCandidate(
            videoURL: videoURL,
            audioURL: audioURL,
            height: video.height,
            expectedBytes: expectedBytes,
            requestHeaders: requestHeaders(for: resolved),
            isHLS: false
        )
    }

    private struct HLSVariant {
        let url: URL
        let height: Int
        let audioContentID: String?
        let isOriginal: Bool
    }

    /// YouTube sometimes emits one complete HLS video rendition per language,
    /// ordered with auto-dubs before the source audio. AVPlayer then picks the
    /// first dubbed rendition. Resolve a single source-audio rendition here so
    /// playback and offline persistence never rely on that ordering.
    private static func originalHLSVariantURL(
        from response: VideoInfosWithDownloadFormatsResponse,
        maximumHeight: Int,
        preferLowest: Bool
    ) async throws -> URL? {
        guard let masterURL = response.videoInfos.streamingURL else { return nil }
        var request = URLRequest(url: masterURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        for (name, value) in requestHeaders(for: response) { request.setValue(value, forHTTPHeaderField: name) }
        let (data, rawResponse) = try await URLSession.shared.data(for: request)
        guard let http = rawResponse as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }
        let lines = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: { $0.isNewline })
            .map(String.init)
        let originalAudioID = preferredOriginalAudioFormats(from: response.downloadFormats)
            .first?.formatLocaleInfos?.localeId
        var variants: [HLSVariant] = []
        for index in lines.indices where lines[index].hasPrefix("#EXT-X-STREAM-INF:") {
            guard index + 1 < lines.count,
                  let url = URL(string: lines[index + 1], relativeTo: masterURL)?.absoluteURL else { continue }
            let info = lines[index]
            let height = info
                .components(separatedBy: "RESOLUTION=").dropFirst().first?
                .components(separatedBy: ",").first?
                .components(separatedBy: "x").last
                .flatMap(Int.init) ?? 0
            let audioID = info
                .components(separatedBy: "YT-EXT-AUDIO-CONTENT-ID=\"").dropFirst().first?
                .components(separatedBy: "\"").first
            variants.append(.init(
                url: url,
                height: height,
                audioContentID: audioID,
                isOriginal: info.contains("b3JpZ2luYWw")
            ))
        }
        let matching = variants.filter {
            ($0.audioContentID == originalAudioID || $0.isOriginal) && $0.height <= maximumHeight
        }
        let fallback = variants.filter { $0.height <= maximumHeight }
        let candidates = matching.isEmpty ? fallback : matching
        return (preferLowest
            ? candidates.min(by: { $0.height < $1.height })
            : candidates.max(by: { $0.height < $1.height }))?.url
    }

    private static func legacyStreamingInfo(videoId: String) async throws -> VideoInfosWithDownloadFormatsResponse {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard videoId.count == 11, videoId.unicodeScalars.allSatisfy(allowedCharacters.contains) else {
            throw ResolverError.invalidVideoID
        }
        let model = YouTubeModel()
        model.selectedLocale = "en-US"
        return try await YTVideo(videoId: videoId)
            .fetchStreamingInfosWithDownloadFormatsThrowing(youtubeModel: model, useCookies: false)
    }

    private static func preferredOriginalAudioFormats(
        from formats: [any AdaptiveDownloadFormat]
    ) -> [AudioOnlyFormat] {
        formats
            .compactMap { $0 as? AudioOnlyFormat }
            .filter { $0.url != nil && $0.mimeType?.hasPrefix("audio/mp4") == true }
            .sorted { left, right in
                let leftOriginal = left.formatLocaleInfos == nil
                let rightOriginal = right.formatLocaleInfos == nil
                if leftOriginal != rightOriginal { return leftOriginal }

                let leftNotDubbed = left.formatLocaleInfos?.isAutoDubbed != true
                let rightNotDubbed = right.formatLocaleInfos?.isAutoDubbed != true
                if leftNotDubbed != rightNotDubbed { return leftNotDubbed }

                let leftStandard = !left.isDrc
                let rightStandard = !right.isDrc
                if leftStandard != rightStandard { return leftStandard }
                return (left.averageBitrate ?? 0) > (right.averageBitrate ?? 0)
            }
    }

    private static func requestHeaders(
        for response: VideoInfosWithDownloadFormatsResponse
    ) -> [String: String] {
        [
            "Referer": "https://www.youtube.com/",
            "User-Agent": response.videoInfos.client?.userAgent
                ?? "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.3.1 Safari/605.1.15"
        ]
    }

    /// YouTube's download-format response contains ciphered URLs. YouTubeKit requires the
    /// watch-page player to be fetched first and then used to decipher both the signature and
    /// throttling parameter. Without this step every progressive format can have a nil URL,
    /// which made both native playback and downloads report `noPlayableStream`.
    private static func resolvedStreamingInfo(videoId: String) async throws -> VideoInfosWithDownloadFormatsResponse {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard videoId.count == 11, videoId.unicodeScalars.allSatisfy(allowedCharacters.contains) else {
            throw ResolverError.invalidVideoID
        }

        let model = YouTubeModel()
        model.selectedLocale = "en-US"
        let video = YTVideo(videoId: videoId)
        let watchPage = try await video.fetchStreamingInfosThrowing(youtubeModel: model, useCookies: false)
        var response = try await video.fetchStreamingInfosWithDownloadFormatsThrowing(
            youtubeModel: model,
            useCookies: false
        )
        guard let player = watchPage.player else {
            throw ResolverError.noPlayableStream
        }
        try response.deciphersURLs(player: player)
        response.videoInfos.streamingURL = watchPage.streamingURL
        return response
    }

    #if os(macOS) && !APP_STORE
    private static func ytDLPStreamURL(videoId: String) async throws -> URL {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard videoId.count == 11, videoId.unicodeScalars.allSatisfy(allowedCharacters.contains) else {
            throw ResolverError.invalidVideoID
        }
        guard let invocation = ytDLPInvocation() else {
            throw ResolverError.ytDLPUnavailable
        }

        let resolutionTask = Task.detached(priority: .userInitiated) {
            let process = Process()
            let standardOutput = Pipe()
            let standardError = Pipe()
            process.executableURL = invocation.executableURL
            var arguments = invocation.argumentPrefix + [
                "--no-warnings",
                "--no-playlist",
                "--extractor-args", "youtube:player_client=web_embedded",
                "--format", "18/best[height<=480][ext=mp4]",
                "--get-url",
                "https://www.youtube.com/watch?v=\(videoId)"
            ]
            if let runtimeArguments = javaScriptRuntimeArguments() {
                arguments.insert(contentsOf: runtimeArguments, at: invocation.argumentPrefix.count)
            }
            process.arguments = arguments
            process.standardOutput = standardOutput
            process.standardError = standardError

            try process.run()
            let deadline = Date().addingTimeInterval(25)
            while process.isRunning, Date() < deadline, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
            }
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }

            let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
            let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
            guard process.terminationStatus == 0 else {
                let detail = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw ResolverError.ytDLPFailed(
                    detail?.isEmpty == false ? detail! : "yt-dlp could not resolve this video."
                )
            }

            let output = String(decoding: outputData, as: UTF8.self)
            guard let firstLine = output.split(whereSeparator: \.isNewline).first,
                  let url = URL(string: String(firstLine)) else {
                throw ResolverError.ytDLPFailed("yt-dlp returned an invalid stream URL.")
            }
            return url
        }
        return try await withTaskCancellationHandler {
            try await resolutionTask.value
        } onCancel: {
            resolutionTask.cancel()
        }
    }

    private static func ytDLPInvocation() -> YTDLPInvocation? {
        let fileManager = FileManager.default
        let directCandidates = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/opt/local/bin/yt-dlp"
        ]
        if let path = directCandidates.first(where: fileManager.isExecutableFile(atPath:)) {
            return YTDLPInvocation(executableURL: URL(fileURLWithPath: path), argumentPrefix: [])
        }

        let localYTDLP = fileManager.homeDirectoryForCurrentUser
            .appending(path: ".local/bin/yt-dlp")
        let modernPythonCandidates = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/opt/local/bin/python3"
        ]
        guard fileManager.isReadableFile(atPath: localYTDLP.path),
              let pythonPath = modernPythonCandidates.first(where: fileManager.isExecutableFile(atPath:)) else {
            return nil
        }
        return YTDLPInvocation(
            executableURL: URL(fileURLWithPath: pythonPath),
            argumentPrefix: [localYTDLP.path]
        )
    }

    private static func javaScriptRuntimeArguments() -> [String]? {
        let fileManager = FileManager.default
        for path in ["/opt/homebrew/bin/deno", "/usr/local/bin/deno", "/opt/local/bin/deno"]
        where fileManager.isExecutableFile(atPath: path) {
            return ["--js-runtimes", "deno:\(path)"]
        }
        for path in ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/opt/local/bin/node"]
        where fileManager.isExecutableFile(atPath: path) {
            return ["--js-runtimes", "node:\(path)"]
        }
        return nil
    }
    #endif

    private static func adaptiveCompositionItem(
        from formats: [any AdaptiveDownloadFormat],
        requestHeaders: [String: String]
    ) async throws -> AVPlayerItem {
        let videos = formats.filter {
            $0 is VideoDownloadFormat
                && $0.url != nil
                && $0.mimeType?.hasPrefix("video/mp4") == true
                && ($0.codec?.hasPrefix("avc1") ?? false)
        }
        let audios = preferredOriginalAudioFormats(from: formats)
        guard
            let video = videos.sorted(by: { ($0.height ?? 0) > ($1.height ?? 0) }).first, let videoURL = video.url,
            let audio = audios.first, let audioURL = audio.url
        else { throw ResolverError.noPlayableStream }

        let options = ["AVURLAssetHTTPHeaderFieldsKey": requestHeaders]
        let videoAsset = AVURLAsset(url: videoURL, options: options)
        let audioAsset = AVURLAsset(url: audioURL, options: options)

        let composition = AVMutableComposition()
        guard
            let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ResolverError.assetNotReady }

        guard
            let sourceVideoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
            let sourceAudioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first
        else { throw ResolverError.assetNotReady }

        let duration = CMTimeMinimum(try await videoAsset.load(.duration), try await audioAsset.load(.duration))
        guard duration.isValid, duration.seconds > 0 else { throw ResolverError.assetNotReady }

        let range = CMTimeRange(start: .zero, duration: duration)
        try compositionVideoTrack.insertTimeRange(range, of: sourceVideoTrack, at: .zero)
        try compositionAudioTrack.insertTimeRange(range, of: sourceAudioTrack, at: .zero)
        compositionVideoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

        return await MainActor.run { AVPlayerItem(asset: composition) }
    }
}
