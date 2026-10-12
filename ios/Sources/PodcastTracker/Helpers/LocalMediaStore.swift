import AVFoundation
import Foundation
import OSLog

@MainActor
final class LocalMediaStore: ObservableObject {
    static let shared = LocalMediaStore()

    enum MediaError: LocalizedError, Equatable {
        case invalidVideoID
        case ytDLPUnavailable
        case ffmpegUnavailable
        case storageLimitReached
        case downloadFailed(String)
        case missingDownloadedFile

        var errorDescription: String? {
            switch self {
            case .invalidVideoID: "The YouTube video ID is invalid."
            case .ytDLPUnavailable: "Offline media is unavailable on this device."
            case .ffmpegUnavailable: "ffmpeg is required for this download quality."
            case .storageLimitReached: "The 8 GB download limit has been reached. Delete a download before trying again."
            case .downloadFailed(let detail): detail
            case .missingDownloadedFile: "The download finished without creating a playable media file."
            }
        }
    }

    private struct Invocation: Sendable {
        let executableURL: URL
        let argumentPrefix: [String]
    }

    private struct PendingDownload: Sendable {
        let videoID: String
        let quality: DownloadQuality
        let retention: DownloadRetention
    }

    private struct PreparedMedia: Sendable {
        let url: URL
        let byteCount: Int64
        let resolutionHeight: Int?
    }

    private struct HTTPStatusError: Error {
        let statusCode: Int
    }

    @Published private(set) var records: [String: DownloadRecord]
    @Published private(set) var transientStates: [String: EpisodeDownloadState] = [:]
    @Published private(set) var activeDownloadedBytes: [String: Int64] = [:]
    @Published private(set) var activeDownloadProgress: [String: Double] = [:]
    @Published var settings: DownloadSettings {
        didSet { if persistsMetadata { dataManager.saveDownloadSettings(settings) } }
    }

    private let fileManager = FileManager.default
    private let rootURL: URL
    private let dataManager: DataManager
    private let persistsMetadata: Bool
    private let logger = Logger(subsystem: "com.tangenix.podtrackio", category: "LocalMedia")
    private var queue: [PendingDownload] = []
    private var waiters: [String: [CheckedContinuation<URL, Error>]] = [:]
    private var activeVideoID: String?
    private var activeTask: Task<Void, Never>?

    init(rootURL: URL? = nil, dataManager: DataManager = .shared) {
        self.dataManager = dataManager
        self.persistsMetadata = rootURL == nil
        self.rootURL = rootURL ?? dataManager.mediaCacheURL
        let loadedSettings = rootURL == nil ? dataManager.loadDownloadSettings() : DownloadSettings()
        self.settings = DownloadSettings(
            quality: loadedSettings.quality,
            maximumStorageBytes: DownloadSettings.storageLimitBytes
        )
        self.records = rootURL == nil
            ? Dictionary(uniqueKeysWithValues: dataManager.loadDownloadRecords().map { ($0.videoID, $0) })
            : [:]
        repairRecordsFromDisk()
    }

    var storageUsedBytes: Int64 { records.values.reduce(0) { $0 + $1.byteCount } }
    var remainingStorageBytes: Int64 { max(0, settings.maximumStorageBytes - storageUsedBytes) }

    func state(for videoID: String) -> EpisodeDownloadState {
        if let transient = transientStates[videoID] { return transient }
        if let record = records[videoID] { return .downloaded(record) }
        return .notDownloaded
    }

    func cachedPlayableURL(videoId: String) -> URL? {
        guard let record = records[videoId] else { return nil }
        let url = rootURL.appending(path: record.fileName)
        guard Self.isCompleteMediaFile(url, fileManager: fileManager) else {
            records[videoId] = nil
            persistRecords()
            return nil
        }
        return url
    }

    func download(videoID: String, completedAt: Date?) async throws -> URL {
        guard Self.isValid(videoID: videoID) else { throw MediaError.invalidVideoID }
        if let existing = cachedPlayableURL(videoId: videoID) { return existing }
        guard remainingStorageBytes > 1_000_000 else { throw MediaError.storageLimitReached }

        return try await withCheckedThrowingContinuation { continuation in
            waiters[videoID, default: []].append(continuation)
            guard activeVideoID != videoID, !queue.contains(where: { $0.videoID == videoID }) else { return }
            let retention = Self.retentionForNewDownload(completedAt: completedAt)
            queue.append(.init(videoID: videoID, quality: settings.quality, retention: retention))
            transientStates[videoID] = .queued
            startNextIfNeeded()
        }
    }

    func cancel(videoID: String) {
        if activeVideoID == videoID {
            activeTask?.cancel()
            return
        }
        queue.removeAll { $0.videoID == videoID }
        transientStates[videoID] = nil
        finishWaiters(for: videoID, result: .failure(CancellationError()))
    }

    func deleteDownload(videoID: String) {
        cancel(videoID: videoID)
        if let record = records.removeValue(forKey: videoID) {
            try? fileManager.removeItem(at: rootURL.appending(path: record.fileName))
        }
        removeIncompleteFiles(videoID: videoID)
        transientStates[videoID] = nil
        persistRecords()
    }

    func markCompleted(videoID: String, completedAt: Date) {
        guard var record = records[videoID], record.retention == .untilCompleted else { return }
        record.retention = .automatic(expiresAt: completedAt.addingTimeInterval(7 * 24 * 60 * 60))
        records[videoID] = record
        persistRecords()
    }

    func reconcile(with podcasts: [Podcast], migrationDate: Date = Date()) {
        repairRecordsFromDisk()
        let byVideoID = Dictionary(grouping: podcasts, by: \.youtubeVideoId)
        for (videoID, var record) in records {
            let matching = byVideoID[videoID] ?? []
            guard matching.contains(where: \.isCompleted), record.retention == .untilCompleted else { continue }
            let completedAt = matching.compactMap(\.completedAt).min() ?? migrationDate
            record.retention = .automatic(expiresAt: completedAt.addingTimeInterval(7 * 24 * 60 * 60))
            records[videoID] = record
        }
        cleanupExpired(now: migrationDate)
        persistRecords()
    }

    func cleanupExpired(now: Date = Date()) {
        let expired = records.values.compactMap { record -> String? in
            guard let date = record.retention.expirationDate, date <= now else { return nil }
            return record.videoID
        }
        for videoID in expired { deleteDownload(videoID: videoID) }
    }

    func deleteCompletedDownloads(podcasts: [Podcast]) {
        let completedIDs = Set(podcasts.filter(\.isCompleted).map(\.youtubeVideoId))
        for videoID in completedIDs where records[videoID] != nil { deleteDownload(videoID: videoID) }
    }

    private func startNextIfNeeded() {
        guard activeVideoID == nil, !queue.isEmpty else { return }
        let request = queue.removeFirst()
        activeVideoID = request.videoID
        transientStates[request.videoID] = .downloading
        activeDownloadProgress[request.videoID] = 0
        let destination = rootURL.appending(path: "\(request.videoID).mp4")
        let maximumBytes = remainingStorageBytes

        activeTask = Task { [weak self] in
            guard let self else { return }
            let progressTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    self.activeDownloadedBytes[request.videoID] = self.measuredPartialBytes(videoID: request.videoID)
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
            defer {
                progressTask.cancel()
                self.activeDownloadedBytes[request.videoID] = nil
                self.activeDownloadProgress[request.videoID] = nil
            }
            do {
                try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
                #if os(iOS)
                let prepared = try await Self.prepareMobileDownload(
                    videoID: request.videoID,
                    destination: destination,
                    quality: request.quality,
                    maximumBytes: maximumBytes,
                    progress: { [weak self] fraction in
                        Task { @MainActor in
                            self?.activeDownloadProgress[request.videoID] = min(max(fraction, 0), 1)
                        }
                    }
                )
                #else
                guard let invocation = Self.ytDLPInvocation(fileManager: fileManager) else {
                    throw MediaError.ytDLPUnavailable
                }
                if request.quality != .saver480,
                   !fileManager.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg"),
                   !fileManager.isExecutableFile(atPath: "/usr/local/bin/ffmpeg") {
                    throw MediaError.ffmpegUnavailable
                }
                let prepared = try await Self.prepareDownload(
                    videoID: request.videoID,
                    destination: destination,
                    quality: request.quality,
                    maximumBytes: maximumBytes,
                    invocation: invocation
                )
                #endif
                guard prepared.byteCount <= remainingStorageBytes else {
                    try? fileManager.removeItem(at: prepared.url)
                    throw MediaError.storageLimitReached
                }
                let record = DownloadRecord(
                    videoID: request.videoID,
                    fileName: prepared.url.lastPathComponent,
                    byteCount: prepared.byteCount,
                    resolutionHeight: prepared.resolutionHeight,
                    downloadedAt: Date(),
                    retention: request.retention
                )
                records[request.videoID] = record
                transientStates[request.videoID] = nil
                persistRecords()
                logger.info("Download completed for video \(request.videoID, privacy: .private)")
                finishWaiters(for: request.videoID, result: .success(prepared.url))
            } catch {
                removeIncompleteFiles(videoID: request.videoID)
                if error is CancellationError {
                    transientStates[request.videoID] = nil
                } else {
                    transientStates[request.videoID] = .failed(error.localizedDescription)
                    logger.error("Download failed: \(error.localizedDescription, privacy: .public)")
                }
                finishWaiters(for: request.videoID, result: .failure(error))
            }
            activeVideoID = nil
            activeTask = nil
            startNextIfNeeded()
        }
    }

    private func finishWaiters(for videoID: String, result: Result<URL, Error>) {
        let continuations = waiters.removeValue(forKey: videoID) ?? []
        for continuation in continuations { continuation.resume(with: result) }
    }

    private func repairRecordsFromDisk() {
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        records = records.filter { _, record in
            Self.isCompleteMediaFile(rootURL.appending(path: record.fileName), fileManager: fileManager)
        }
        let files = (try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        for url in files where ["mp4", "movpkg"].contains(url.pathExtension)
            && Self.isCompleteMediaFile(url, fileManager: fileManager) {
            let videoID = url.deletingPathExtension().lastPathComponent
            guard Self.isValid(videoID: videoID), records[videoID] == nil else { continue }
            let size = Self.mediaSize(at: url, fileManager: fileManager)
            records[videoID] = DownloadRecord(
                videoID: videoID,
                fileName: url.lastPathComponent,
                byteCount: size,
                resolutionHeight: nil,
                downloadedAt: (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date(),
                retention: .untilCompleted
            )
        }
        persistRecords()
    }

    private func removeIncompleteFiles(videoID: String) {
        let files = (try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.lastPathComponent.hasPrefix(videoID)
            && !Self.isCompleteMediaFile(url, fileManager: fileManager) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func measuredPartialBytes(videoID: String) -> Int64 {
        let files = (try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix(videoID) }.reduce(0) { total, url in
            total + Self.mediaSize(at: url, fileManager: fileManager)
        }
    }

    private func persistRecords() {
        guard persistsMetadata else { return }
        dataManager.saveDownloadRecords(records.values.sorted { $0.downloadedAt > $1.downloadedAt })
    }

    private nonisolated static func prepareDownload(
        videoID: String,
        destination: URL,
        quality: DownloadQuality,
        maximumBytes: Int64,
        invocation: Invocation
    ) async throws -> PreparedMedia {
        #if os(macOS) && !APP_STORE
        let processTask = Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let clientArguments = [
                ["--extractor-args", "youtube:player_client=web_embedded"],
                []
            ]
            var successfulOutput: String?
            var lastError = "The episode could not be downloaded."

            for clientArgument in clientArguments {
                let process = Process()
                let standardOutput = Pipe()
                let standardError = Pipe()
                process.executableURL = invocation.executableURL
                var arguments = invocation.argumentPrefix + [
                    "--no-playlist", "--no-warnings", "--no-progress", "--no-mtime", "--force-overwrites",
                    "--no-continue",
                    "--format", quality.formatSelector,
                    "--max-filesize", "\(maximumBytes)",
                    "--merge-output-format", "mp4",
                    "--output", destination.path,
                    "--print", "after_move:filepath"
                ]
                arguments.insert(contentsOf: clientArgument, at: invocation.argumentPrefix.count)
                if let runtimeArguments = javaScriptRuntimeArguments(fileManager: fileManager) {
                    arguments.insert(contentsOf: runtimeArguments, at: invocation.argumentPrefix.count)
                }
                for ffmpeg in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/opt/local/bin/ffmpeg"]
                where fileManager.isExecutableFile(atPath: ffmpeg) {
                    arguments += ["--ffmpeg-location", ffmpeg]
                    break
                }
                arguments.append("https://www.youtube.com/watch?v=\(videoID)")
                process.arguments = arguments
                process.standardOutput = standardOutput
                process.standardError = standardError
                try process.run()

                let deadline = Date().addingTimeInterval(4 * 60 * 60)
                while process.isRunning, Date() < deadline, !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                if process.isRunning { process.terminate(); process.waitUntilExit() }
                if Task.isCancelled { throw CancellationError() }

                let output = String(decoding: standardOutput.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let errorOutput = String(decoding: standardError.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if process.terminationStatus == 0 {
                    successfulOutput = output
                    break
                }
                if errorOutput.localizedCaseInsensitiveContains("larger than max-filesize") {
                    throw MediaError.storageLimitReached
                }
                if !errorOutput.isEmpty { lastError = errorOutput }
                removeAttemptFiles(destination: destination, fileManager: fileManager)
            }

            guard let output = successfulOutput else { throw MediaError.downloadFailed(lastError) }
            let printedPath = output.split(whereSeparator: \.isNewline).last.map(String.init)
            let finalURL = printedPath.map { URL(fileURLWithPath: $0) } ?? destination
            guard isCompleteMediaFile(finalURL, fileManager: fileManager),
                  let attributes = try? fileManager.attributesOfItem(atPath: finalURL.path),
                  let size = attributes[.size] as? NSNumber else { throw MediaError.missingDownloadedFile }

            let asset = AVURLAsset(url: finalURL)
            let height: Int?
            if let track = try? await asset.loadTracks(withMediaType: .video).first,
               let naturalSize = try? await track.load(.naturalSize) {
                height = Int(abs(naturalSize.height.rounded()))
            } else {
                height = nil
            }
            return PreparedMedia(url: finalURL, byteCount: size.int64Value, resolutionHeight: height)
        }
        return try await withTaskCancellationHandler {
            try await processTask.value
        } onCancel: {
            processTask.cancel()
        }
        #else
        throw MediaError.ytDLPUnavailable
        #endif
    }

    #if os(iOS)
    private nonisolated static func prepareMobileDownload(
        videoID: String,
        destination: URL,
        quality: DownloadQuality,
        maximumBytes: Int64,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> PreparedMedia {
        var lastRejectedStatus: Int?
        for attempt in 0..<3 {
            try Task.checkCancellation()
            let candidate = try await YouTubeStreamResolver.downloadableVideo(
                videoId: videoID,
                maximumHeight: quality.rawValue
            )
            if let expectedBytes = candidate.expectedBytes, expectedBytes > maximumBytes {
                throw MediaError.storageLimitReached
            }

            do {
                return try await prepareResolvedMobileDownload(
                    candidate: candidate,
                    destination: destination,
                    maximumBytes: maximumBytes,
                    progress: progress
                )
            } catch let error as HTTPStatusError where error.statusCode == 403 || error.statusCode == 410 {
                lastRejectedStatus = error.statusCode
                if attempt < 2 {
                    // CDN URLs are short-lived and client-bound. Resolve a fresh pair
                    // instead of retrying the already rejected URL.
                    try await Task.sleep(for: .milliseconds(250 * (attempt + 1)))
                }
            }
        }
        throw MediaError.downloadFailed(
            "YouTube rejected the fresh media URL (HTTP \(lastRejectedStatus ?? 403)). Please try again."
        )
    }

    private nonisolated static func prepareResolvedMobileDownload(
        candidate: YouTubeStreamResolver.DownloadCandidate,
        destination: URL,
        maximumBytes: Int64,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> PreparedMedia {
        if candidate.isHLS {
            return try await prepareHLSMobileDownload(
                candidate: candidate,
                destination: destination.deletingPathExtension().appendingPathExtension("movpkg"),
                maximumBytes: maximumBytes,
                progress: progress
            )
        }

        let fileManager = FileManager.default
        var temporaryFiles: [URL] = []
        defer { temporaryFiles.forEach { try? fileManager.removeItem(at: $0) } }

        // A muxed progressive asset is also the path used by the working native
        // player. Let AVFoundation persist that asset first; unlike a bare
        // URLSession request it uses the same media loading stack as AVPlayer.
        if candidate.audioURL == nil {
            do {
                return try await exportProgressiveMobileDownload(
                    candidate: candidate,
                    destination: destination,
                    maximumBytes: maximumBytes
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Some progressive assets cannot be exported even though their
                // bytes are directly downloadable. Retain that transport as a
                // compatibility fallback, using the same freshly resolved URL.
            }
        }

        let (videoURL, videoResponse) = try await downloadYouTubeMedia(
            from: candidate.videoURL,
            headers: candidate.requestHeaders
        )
        temporaryFiles.append(videoURL)
        let videoExpected = max(0, videoResponse.expectedContentLength)
        let audioDownload: (URL, URLResponse)?
        if let audioURL = candidate.audioURL {
            let downloaded = try await downloadYouTubeMedia(from: audioURL, headers: candidate.requestHeaders)
            temporaryFiles.append(downloaded.0)
            audioDownload = downloaded
        } else {
            audioDownload = nil
        }
        try Task.checkCancellation()
        let audioExpected = max(0, audioDownload?.1.expectedContentLength ?? 0)
        if videoExpected + audioExpected > maximumBytes || (candidate.expectedBytes ?? 0) > maximumBytes {
            throw MediaError.storageLimitReached
        }
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        if let (audioURL, _) = audioDownload {
            try await mergeMobileVideo(videoURL: videoURL, audioURL: audioURL, destination: destination)
        } else {
            try fileManager.moveItem(at: videoURL, to: destination)
        }
        guard isCompleteMediaFile(destination, fileManager: fileManager),
              let attributes = try? fileManager.attributesOfItem(atPath: destination.path),
              let size = attributes[.size] as? NSNumber else {
            try? fileManager.removeItem(at: destination)
            throw MediaError.missingDownloadedFile
        }
        guard size.int64Value <= maximumBytes else {
            try? fileManager.removeItem(at: destination)
            throw MediaError.storageLimitReached
        }
        return PreparedMedia(url: destination, byteCount: size.int64Value, resolutionHeight: candidate.height)
    }

    private nonisolated static func exportProgressiveMobileDownload(
        candidate: YouTubeStreamResolver.DownloadCandidate,
        destination: URL,
        maximumBytes: Int64
    ) async throws -> PreparedMedia {
        if let expectedBytes = candidate.expectedBytes, expectedBytes > maximumBytes {
            throw MediaError.storageLimitReached
        }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        let asset = AVURLAsset(
            url: candidate.videoURL,
            options: ["AVURLAssetHTTPHeaderFieldsKey": candidate.requestHeaders]
        )
        guard try await asset.load(.isPlayable),
              let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw MediaError.missingDownloadedFile
        }
        try await exporter.export(to: destination, as: .mp4)
        try Task.checkCancellation()
        guard isCompleteMediaFile(destination, fileManager: fileManager),
              let attributes = try? fileManager.attributesOfItem(atPath: destination.path),
              let size = attributes[.size] as? NSNumber else {
            throw MediaError.missingDownloadedFile
        }
        guard size.int64Value <= maximumBytes else {
            try? fileManager.removeItem(at: destination)
            throw MediaError.storageLimitReached
        }
        return PreparedMedia(
            url: destination,
            byteCount: size.int64Value,
            resolutionHeight: candidate.height
        )
    }

    private nonisolated static func prepareHLSMobileDownload(
        candidate: YouTubeStreamResolver.DownloadCandidate,
        destination: URL,
        maximumBytes: Int64,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> PreparedMedia {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        let asset = AVURLAsset(
            url: candidate.videoURL,
            options: ["AVURLAssetHTTPHeaderFieldsKey": candidate.requestHeaders]
        )
        guard try await asset.load(.isPlayable) else {
            throw MediaError.missingDownloadedFile
        }

        let operation = HLSAssetDownloadOperation(progress: progress)
        let downloadedURL = try await operation.download(asset: asset, destination: destination)
        try Task.checkCancellation()
        let size = mediaSize(at: downloadedURL, fileManager: fileManager)
        guard size > 1_000_000 else {
            try? fileManager.removeItem(at: downloadedURL)
            throw MediaError.missingDownloadedFile
        }
        guard size <= maximumBytes else {
            try? fileManager.removeItem(at: downloadedURL)
            throw MediaError.storageLimitReached
        }
        return PreparedMedia(
            url: downloadedURL,
            byteCount: size,
            resolutionHeight: candidate.height
        )
    }

    private nonisolated static func downloadYouTubeMedia(
        from url: URL,
        headers: [String: String]
    ) async throws -> (URL, URLResponse) {
        let userAgents = [
            headers["User-Agent"],
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.3.1 Safari/605.1.15"
        ].compactMap { $0 }
        var lastStatus = 403
        var attemptedUserAgents = Set<String>()
        for userAgent in userAgents where attemptedUserAgents.insert(userAgent).inserted {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
            request.setValue(headers["Referer"] ?? "https://www.youtube.com/", forHTTPHeaderField: "Referer")
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            let result = try await URLSession.shared.download(for: request)
            if let response = result.1 as? HTTPURLResponse,
               !(200...299).contains(response.statusCode) {
                lastStatus = response.statusCode
                try? FileManager.default.removeItem(at: result.0)
                if response.statusCode == 403 { continue }
                throw HTTPStatusError(statusCode: response.statusCode)
            }
            return result
        }
        throw HTTPStatusError(statusCode: lastStatus)
    }

    private nonisolated static func mergeMobileVideo(videoURL: URL, audioURL: URL, destination: URL) async throws {
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)
        let composition = AVMutableComposition()
        guard let sourceVideo = try await videoAsset.loadTracks(withMediaType: .video).first,
              let sourceAudio = try await audioAsset.loadTracks(withMediaType: .audio).first,
              let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ),
              let audioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw MediaError.missingDownloadedFile
        }
        let duration = CMTimeMinimum(try await videoAsset.load(.duration), try await audioAsset.load(.duration))
        guard duration.isValid, duration.seconds > 0 else { throw MediaError.missingDownloadedFile }
        let range = CMTimeRange(start: .zero, duration: duration)
        try videoTrack.insertTimeRange(range, of: sourceVideo, at: .zero)
        try audioTrack.insertTimeRange(range, of: sourceAudio, at: .zero)
        videoTrack.preferredTransform = try await sourceVideo.load(.preferredTransform)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw MediaError.missingDownloadedFile
        }
        try await exporter.export(to: destination, as: .mp4)
    }
    #endif

    private nonisolated static func removeAttemptFiles(destination: URL, fileManager: FileManager) {
        let directory = destination.deletingLastPathComponent()
        let prefix = destination.deletingPathExtension().lastPathComponent
        let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            try? fileManager.removeItem(at: file)
        }
    }

    private nonisolated static func isCompleteMediaFile(_ url: URL, fileManager: FileManager) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        return mediaSize(at: url, fileManager: fileManager) > 1_000_000
    }

    private nonisolated static func mediaSize(at url: URL, fileManager: FileManager) -> Int64 {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue {
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        }
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let child as URL in enumerator {
            guard let values = try? child.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private nonisolated static func isValid(videoID: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return videoID.count == 11 && videoID.unicodeScalars.allSatisfy(allowed.contains)
    }

    nonisolated static func retentionForNewDownload(completedAt: Date?) -> DownloadRetention {
        completedAt == nil ? .untilCompleted : .manual
    }

    private nonisolated static func ytDLPInvocation(fileManager: FileManager) -> Invocation? {
        #if !os(macOS) || APP_STORE
        nil
        #else
        for path in ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", "/opt/local/bin/yt-dlp"]
        where fileManager.isExecutableFile(atPath: path) {
            return Invocation(executableURL: URL(fileURLWithPath: path), argumentPrefix: [])
        }
        let local = fileManager.homeDirectoryForCurrentUser.appending(path: ".local/bin/yt-dlp")
        guard fileManager.isReadableFile(atPath: local.path) else { return nil }
        for python in ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/opt/local/bin/python3"]
        where fileManager.isExecutableFile(atPath: python) {
            return Invocation(executableURL: URL(fileURLWithPath: python), argumentPrefix: [local.path])
        }
        return nil
        #endif
    }

    private nonisolated static func javaScriptRuntimeArguments(fileManager: FileManager) -> [String]? {
        #if !os(macOS) || APP_STORE
        nil
        #else
        for path in ["/opt/homebrew/bin/deno", "/usr/local/bin/deno", "/opt/local/bin/deno"]
        where fileManager.isExecutableFile(atPath: path) {
            return ["--js-runtimes", "deno:\(path)"]
        }
        for path in ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/opt/local/bin/node"]
        where fileManager.isExecutableFile(atPath: path) {
            return ["--js-runtimes", "node:\(path)"]
        }
        return nil
        #endif
    }
}

#if os(iOS)
private final class HLSAssetDownloadOperation: NSObject, AVAssetDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var downloadLocation: URL?
    private var task: AVAssetDownloadTask?
    private var session: AVAssetDownloadURLSession?

    init(progress: @escaping @Sendable (Double) -> Void) {
        self.progress = progress
    }

    func download(asset: AVURLAsset, destination: URL) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let configuration = URLSessionConfiguration.background(
                    withIdentifier: "com.tangenix.podtrackio.hls.\(UUID().uuidString)"
                )
                configuration.isDiscretionary = false
                configuration.sessionSendsLaunchEvents = false
                let session = AVAssetDownloadURLSession(
                    configuration: configuration,
                    assetDownloadDelegate: self,
                    delegateQueue: OperationQueue()
                )
                self.session = session
                guard let task = session.makeAssetDownloadTask(
                    asset: asset,
                    destinationURL: destination,
                    options: nil
                ) else {
                    finish(.failure(LocalMediaStore.MediaError.missingDownloadedFile))
                    return
                }
                self.task = task
                task.resume()
            }
        } onCancel: {
            self.task?.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        willDownloadTo location: URL
    ) {
        downloadLocation = location
    }

    func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didLoad timeRange: CMTimeRange,
        totalTimeRangesLoaded loadedTimeRanges: [NSValue],
        timeRangeExpectedToLoad: CMTimeRange
    ) {
        let expectedSeconds = timeRangeExpectedToLoad.duration.seconds
        guard expectedSeconds.isFinite, expectedSeconds > 0 else { return }
        let loadedSeconds = loadedTimeRanges.reduce(0.0) { total, value in
            let seconds = value.timeRangeValue.duration.seconds
            return total + (seconds.isFinite ? max(0, seconds) : 0)
        }
        progress(min(max(loadedSeconds / expectedSeconds, 0), 1))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        } else if let downloadLocation {
            finish(.success(downloadLocation))
        } else {
            finish(.failure(LocalMediaStore.MediaError.missingDownloadedFile))
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        self.task = nil
        session?.finishTasksAndInvalidate()
        session = nil
        continuation.resume(with: result)
    }
}
#endif
