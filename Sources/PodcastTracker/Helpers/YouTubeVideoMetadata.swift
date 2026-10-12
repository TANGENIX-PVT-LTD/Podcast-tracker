import Foundation
#if os(iOS)
import YouTubeKit
#endif

/// Lightweight metadata for a single YouTube video (title, thumbnail, duration)
struct YouTubeVideoMetadata: Sendable {
    let videoID: String
    let title: String
    let thumbnailURL: String?
    let duration: TimeInterval?
}

enum YouTubeVideoMetadataFetcher {
    enum FetchError: LocalizedError {
        case invalidVideoID
        case ytDLPUnavailable
        case extractionFailed(String)
        case videoUnavailable

        var errorDescription: String? {
            switch self {
            case .invalidVideoID: "Invalid YouTube video ID."
            case .ytDLPUnavailable: "yt-dlp is unavailable on this Mac."
            case .extractionFailed(let detail): detail
            case .videoUnavailable: "This video is unavailable or private."
            }
        }
    }

    /// Fetch metadata for a single YouTube video by its video ID.
    /// Returns nil if the video ID is invalid or fetch fails.
    static func fetch(videoID: String) async -> YouTubeVideoMetadata? {
        guard videoID.count == 11 else { return nil }

        #if os(iOS)
        return await fetchWithYouTubeKit(videoID: videoID)
        #elseif APP_STORE
        // In App Store, try oEmbed first as it's very fast
        return await fetchWithOEmbed(videoID: videoID)
        #else
        // Try oEmbed first (very fast, no yt-dlp needed), fall back to yt-dlp
        if let metadata = await fetchWithOEmbed(videoID: videoID) {
            return metadata
        }
        return await fetchWithYTDLP(videoID: videoID)
        #endif
    }

    #if os(iOS)
    private static func fetchWithYouTubeKit(videoID: String) async -> YouTubeVideoMetadata? {
        do {
            let model = YouTubeModel()
            let video = try await YTVideo(videoId: videoID)
                .fetchVideoThrowing(youtubeModel: model, useCookies: false)
            let thumbnail = video.thumbnails.max { lhs, rhs in
                (lhs.width ?? 0) * (lhs.height ?? 0) < (rhs.width ?? 0) * (rhs.height ?? 0)
            }?.url.absoluteString
            let duration = video.durationSeconds
            return YouTubeVideoMetadata(
                videoID: videoID,
                title: video.title ?? "Untitled",
                thumbnailURL: thumbnail ?? "https://img.youtube.com/vi/\(videoID)/mqdefault.jpg",
                duration: duration
            )
        } catch {
            return nil
        }
    }
    #endif

    /// Fast fallback using YouTube's oEmbed API - works everywhere, no auth needed
    private static func fetchWithOEmbed(videoID: String) async -> YouTubeVideoMetadata? {
        let urlString = "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=\(videoID)&format=json"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            struct OEmbedResponse: Decodable {
                let title: String
                let thumbnail_url: String?
            }

            let oembed = try JSONDecoder().decode(OEmbedResponse.self, from: data)
            let title = oembed.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }

            return YouTubeVideoMetadata(
                videoID: videoID,
                title: title,
                thumbnailURL: oembed.thumbnail_url ?? "https://img.youtube.com/vi/\(videoID)/mqdefault.jpg",
                duration: nil
            )
        } catch {
            return nil
        }
    }

    #if !os(iOS) && !APP_STORE
    private static func fetchWithYTDLP(videoID: String) async -> YouTubeVideoMetadata? {
        guard let executable = ytDLPURL() else { return nil }

        return await withTaskCancellationHandler {
            let task = Task.detached(priority: .userInitiated) {
                let process = Process()
                let output = Pipe()
                let error = Pipe()
                process.executableURL = executable
                // Use --print to get only title (much faster than full JSON)
                // Timeout after 8 seconds
                process.arguments = [
                    "--no-warnings", "--no-download",
                    "--extractor-args", "youtube:player_client=web_safari",
                    "--print", "%(title)s",
                    "https://www.youtube.com/watch?v=\(videoID)"
                ]
                process.standardOutput = output
                process.standardError = error
                try process.run()

                // 8 second timeout
                let deadline = Date().addingTimeInterval(8)
                async let capturedOutput = output.fileHandleForReading.readToEnd()
                async let capturedError = error.fileHandleForReading.readToEnd()

                while process.isRunning, !Task.isCancelled, Date() < deadline {
                    try? await Task.sleep(for: .milliseconds(100))
                }

                if process.isRunning {
                    process.terminate()
                    process.waitUntilExit()
                }

                if Task.isCancelled { throw CancellationError() }

                let data = try await capturedOutput ?? Data()
                let errorData = try await capturedError ?? Data()
                let detail = String(decoding: errorData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard process.terminationStatus == 0 else {
                    if detail.localizedCaseInsensitiveContains("private") ||
                       detail.localizedCaseInsensitiveContains("unavailable") ||
                       detail.localizedCaseInsensitiveContains("deleted") ||
                       detail.localizedCaseInsensitiveContains("copyright") {
                        throw FetchError.videoUnavailable
                    }
                    throw FetchError.extractionFailed(detail.isEmpty ? "Could not fetch video metadata." : detail)
                }

                let title = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { throw FetchError.extractionFailed("Empty title received") }

                return YouTubeVideoMetadata(
                    videoID: videoID,
                    title: title,
                    thumbnailURL: "https://img.youtube.com/vi/\(videoID)/mqdefault.jpg",
                    duration: nil
                )
            }
            do {
                return try await withTaskCancellationHandler {
                    try await task.value
                } onCancel: {
                    task.cancel()
                }
            } catch is CancellationError {
                return nil
            } catch {
                return nil
            }
        } onCancel: { }
    }

    private static func ytDLPURL() -> URL? {
        let manager = FileManager.default
        return ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", "/opt/local/bin/yt-dlp"]
            .first(where: manager.isExecutableFile(atPath:))
            .map(URL.init(fileURLWithPath:))
    }
    #endif
}