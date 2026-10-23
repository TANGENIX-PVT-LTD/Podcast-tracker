import UIKit

/// Widgets can't fetch from the network while rendering, so the app caches the next episode's
/// thumbnail (downscaled) into the shared app group whenever the up-next episode changes.
@MainActor
enum WidgetThumbnailCache {
    private static let ownerKey = "podtrackio.widget.thumbnail.owner"
    private static var inFlight: UUID?

    static func hasThumbnail(for podcast: Podcast?) -> Bool {
        guard let podcast, let file = PodTrackioWidgetSnapshotStore.thumbnailURL,
              UserDefaults(suiteName: PodTrackioWidgetSnapshotStore.appGroupID)?.string(forKey: ownerKey) == podcast.id.uuidString else { return false }
        return FileManager.default.fileExists(atPath: file.path)
    }

    static func refresh(for podcast: Podcast?, completion: @escaping @MainActor () -> Void) {
        guard let podcast, !hasThumbnail(for: podcast), inFlight != podcast.id,
              let source = podcast.thumbnailURL.flatMap(URL.init(string:)),
              let destination = PodTrackioWidgetSnapshotStore.thumbnailURL else { return }
        inFlight = podcast.id
        Task {
            defer { inFlight = nil }
            guard let (data, _) = try? await URLSession.shared.data(from: source), let image = UIImage(data: data) else { return }
            let width: CGFloat = 640
            let size = CGSize(width: width, height: width * image.size.height / max(1, image.size.width))
            let scaled = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
                .image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            guard let jpeg = scaled.jpegData(compressionQuality: 0.8), (try? jpeg.write(to: destination, options: .atomic)) != nil else { return }
            UserDefaults(suiteName: PodTrackioWidgetSnapshotStore.appGroupID)?.set(podcast.id.uuidString, forKey: ownerKey)
            completion()
        }
    }
}

extension StreakDay {
    var widgetState: String {
        switch state {
        case .done: "done"
        case .frozen: "frozen"
        case .missed: "missed"
        case .today: "today"
        case .todayDone: "todayDone"
        case .future: "future"
        }
    }
}
