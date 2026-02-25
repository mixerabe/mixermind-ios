import Foundation

/// Resolves social media URLs to direct media stream URLs via the Python backend.
enum MediaURLService {
    struct Result {
        let platform: Platform
        let originalURL: String
        let videoURL: URL?
        let audioURL: URL?
        let thumbnailURL: URL?
        let title: String?
        let duration: Double?
    }

    enum Platform: String, Decodable {
        case instagram, youtube, tiktok, spotify
    }

    enum MediaError: LocalizedError {
        case unsupportedURL
        case noMediaFound
        case serverError(String)
        case networkError

        var errorDescription: String? {
            switch self {
            case .unsupportedURL: return "Unsupported URL. Paste an Instagram, YouTube, TikTok, or Spotify link."
            case .noMediaFound: return "No video found at this URL"
            case .serverError(let msg): return msg
            case .networkError: return "Network error"
            }
        }
    }

    // MARK: - Public API

    /// Resolve metadata + stream URLs (no download)
    static func resolve(_ urlString: String) async throws -> Result {
        let platform = detectPlatform(urlString)
        switch platform {
        case .youtube, .instagram, .tiktok:
            return try await resolveViaBackend(urlString)
        case .spotify:
            // Spotify uses a separate download path — this shouldn't be called directly.
            // Return a stub result; actual download goes through downloadSpotify().
            return Result(platform: .spotify, originalURL: urlString,
                          videoURL: nil, audioURL: nil, thumbnailURL: nil,
                          title: nil, duration: nil)
        case nil:
            throw MediaError.unsupportedURL
        }
    }

    /// Download + merge video server-side (Instagram/TikTok only)
    static func downloadMerged(_ urlString: String) async throws -> Data {
        guard let endpoint = URL(string: "\(Constants.backendURL)/api/media/download") else {
            throw MediaError.serverError("Backend not configured")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["url": urlString])
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw MediaError.networkError
        }

        guard http.statusCode == 200 else {
            if let body = try? JSONDecoder().decode([String: String].self, from: data),
               let msg = body["detail"] {
                throw MediaError.serverError(msg)
            }
            throw MediaError.serverError("Server returned \(http.statusCode)")
        }

        guard !data.isEmpty else {
            throw MediaError.noMediaFound
        }

        return data
    }

    // MARK: - Platform Detection

    private static func detectPlatform(_ url: String) -> Platform? {
        if url.contains("instagram.com/p/") || url.contains("instagram.com/reel/") || url.contains("instagram.com/reels/") {
            return .instagram
        }
        if url.contains("youtube.com/watch") || url.contains("youtu.be/") || url.contains("youtube.com/shorts/") {
            return .youtube
        }
        if url.contains("tiktok.com/") {
            return .tiktok
        }
        if url.contains("open.spotify.com/") || url.contains("spotify.com/") {
            return .spotify
        }
        return nil
    }

    static func isSpotifyQuery(_ input: String) -> Bool {
        detectPlatform(input) == .spotify
    }

    // MARK: - Backend (Instagram / YouTube / TikTok)

    private static func resolveViaBackend(_ urlString: String) async throws -> Result {
        guard let endpoint = URL(string: "\(Constants.backendURL)/api/media/resolve") else {
            throw MediaError.serverError("Backend not configured")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["url": urlString])
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw MediaError.networkError
        }

        guard http.statusCode == 200 else {
            if let body = try? JSONDecoder().decode([String: String].self, from: data),
               let msg = body["detail"] {
                throw MediaError.serverError(msg)
            }
            throw MediaError.serverError("Server returned \(http.statusCode)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        let platformStr = json["platform"] as? String ?? ""
        let platform = Platform(rawValue: platformStr) ?? .instagram

        let videoURL = (json["video_url"] as? String).flatMap(URL.init(string:))
        let audioURL = (json["audio_url"] as? String).flatMap(URL.init(string:))
        let thumbnailURL = (json["thumbnail_url"] as? String).flatMap(URL.init(string:))

        guard videoURL != nil || audioURL != nil else {
            throw MediaError.noMediaFound
        }

        return Result(
            platform: platform,
            originalURL: urlString,
            videoURL: videoURL,
            audioURL: audioURL,
            thumbnailURL: thumbnailURL,
            title: json["title"] as? String,
            duration: json["duration"] as? Double
        )
    }

    // MARK: - Spotify (via Backend spotDL)

    struct SpotifyResult {
        let audioData: Data
        let title: String
        let artist: String
        let duration: Double?
    }

    /// Download a Spotify track by URL or search query. Returns MP3 data + metadata.
    static func downloadSpotify(_ query: String) async throws -> SpotifyResult {
        guard let endpoint = URL(string: "\(Constants.backendURL)/api/media/spotify") else {
            throw MediaError.serverError("Backend not configured")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["query": query])
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw MediaError.networkError
        }

        guard http.statusCode == 200 else {
            if let body = try? JSONDecoder().decode([String: String].self, from: data),
               let msg = body["detail"] {
                throw MediaError.serverError(msg)
            }
            throw MediaError.serverError("Server returned \(http.statusCode)")
        }

        guard !data.isEmpty else {
            throw MediaError.noMediaFound
        }

        let title = http.value(forHTTPHeaderField: "X-Track-Title") ?? "Spotify Track"
        let artist = http.value(forHTTPHeaderField: "X-Track-Artist") ?? ""
        let duration = http.value(forHTTPHeaderField: "X-Track-Duration").flatMap(Double.init)

        return SpotifyResult(audioData: data, title: title, artist: artist, duration: duration)
    }

}
