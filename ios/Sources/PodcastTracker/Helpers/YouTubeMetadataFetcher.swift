import Foundation

/// Fetches YouTube video metadata (title, etc.) without requiring an API key
enum YouTubeMetadataFetcher {
    enum FetchError: LocalizedError {
        case invalidResponse
        case videoNotFound
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: "Received an invalid response from YouTube."
            case .videoNotFound: "Video not found or unavailable."
            case .networkError(let error): "Network error: \(error.localizedDescription)"
            }
        }
    }

    /// Fetches the video title from YouTube's oEmbed endpoint
    /// This doesn't require an API key and works for public videos
    static func fetchTitle(videoID: String) async throws -> String {
        let urlString = "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=\(videoID)&format=json"
        guard let url = URL(string: urlString) else {
            throw FetchError.invalidResponse
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FetchError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            throw FetchError.videoNotFound
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw FetchError.invalidResponse
        }

        struct OEmbedResponse: Decodable {
            let title: String
        }

        let oembed = try JSONDecoder().decode(OEmbedResponse.self, from: data)
        return oembed.title
    }
}