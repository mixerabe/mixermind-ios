import Foundation

/// Resolves social media URLs to direct media stream URLs.
/// YouTube: on-device via InnerTube (needs residential IP = your phone).
/// Instagram/TikTok: via the Python backend (uses session cookies).
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
        case .youtube:
            return try await resolveYouTubeOnDevice(urlString)
        case .instagram, .tiktok:
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

    // MARK: - Backend (Instagram / TikTok)

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

    // MARK: - YouTube (On-Device InnerTube)

    private static func extractYouTubeVideoId(_ url: String) -> String? {
        if let range = url.range(of: #"youtu\.be/([A-Za-z0-9_-]{11})"#, options: .regularExpression) {
            return String(url[range].suffix(11))
        }
        if let range = url.range(of: #"youtube\.com/shorts/([A-Za-z0-9_-]{11})"#, options: .regularExpression) {
            return String(url[range].suffix(11))
        }
        if let range = url.range(of: #"[?&]v=([A-Za-z0-9_-]{11})"#, options: .regularExpression) {
            return String(url[range].suffix(11))
        }
        return nil
    }

    private static func resolveYouTubeOnDevice(_ urlString: String) async throws -> Result {
        guard let videoId = extractYouTubeVideoId(urlString) else {
            throw MediaError.serverError("Could not extract YouTube video ID")
        }

        let playerURL = URL(string: "https://www.youtube.com/youtubei/v1/player")!

        let body: [String: Any] = [
            "videoId": videoId,
            "context": [
                "client": [
                    "clientName": "ANDROID_VR",
                    "clientVersion": "1.71.26",
                    "deviceMake": "Oculus",
                    "deviceModel": "Quest 3",
                    "osName": "Android",
                    "osVersion": "12L",
                    "androidSdkVersion": 32,
                    "hl": "en",
                    "gl": "US",
                ] as [String: Any]
            ] as [String: Any],
            "params": "CgIQBg==",
        ]

        var request = URLRequest(url: playerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("com.google.android.apps.youtube.vr.oculus/1.71.26 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip", forHTTPHeaderField: "User-Agent")
        request.setValue("2", forHTTPHeaderField: "X-Goog-Api-Format-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let bodyPreview = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw MediaError.serverError("YouTube HTTP \(statusCode): \(bodyPreview)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        // Check playability
        if let playability = json["playabilityStatus"] as? [String: Any],
           let status = playability["status"] as? String,
           status != "OK" {
            let reason = playability["reason"] as? String
                ?? (playability["messages"] as? [String])?.first
                ?? status
            throw MediaError.serverError("YouTube: \(reason)")
        }

        guard let streamingData = json["streamingData"] as? [String: Any] else {
            throw MediaError.noMediaFound
        }

        let formats = streamingData["formats"] as? [[String: Any]] ?? []
        let adaptiveFormats = streamingData["adaptiveFormats"] as? [[String: Any]] ?? []

        // Pick best audio (prefer AAC/m4a for iOS)
        let audioFormats = adaptiveFormats.filter { f in
            f["url"] != nil &&
            f["width"] == nil &&
            (f["mimeType"] as? String)?.hasPrefix("audio/") == true
        }
        let bestAudio = audioFormats
            .filter { ($0["mimeType"] as? String)?.contains("mp4") == true }
            .sorted { ($0["bitrate"] as? Int ?? 0) > ($1["bitrate"] as? Int ?? 0) }
            .first ?? audioFormats.sorted { ($0["bitrate"] as? Int ?? 0) > ($1["bitrate"] as? Int ?? 0) }.first

        // Pick best muxed video (has both audio+video)
        let muxedFormats = formats.filter { f in
            f["url"] != nil && (f["width"] != nil || f["height"] != nil)
        }.sorted { ($0["height"] as? Int ?? 0) > ($1["height"] as? Int ?? 0) }

        // Pick best adaptive video (H.264, ≤720p)
        let videoAdaptive = adaptiveFormats.filter { f in
            f["url"] != nil &&
            (f["width"] != nil || f["height"] != nil) &&
            (f["mimeType"] as? String)?.hasPrefix("audio/") != true &&
            (f["height"] as? Int ?? 9999) <= 720
        }
        let bestAdaptiveVideo = videoAdaptive
            .filter { ($0["mimeType"] as? String)?.contains("avc") == true }
            .sorted { ($0["height"] as? Int ?? 0) > ($1["height"] as? Int ?? 0) }
            .first ?? videoAdaptive.sorted { ($0["height"] as? Int ?? 0) > ($1["height"] as? Int ?? 0) }.first

        let bestVideo = bestAdaptiveVideo ?? muxedFormats.first

        guard bestVideo != nil || bestAudio != nil else {
            throw MediaError.noMediaFound
        }

        let videoDetails = json["videoDetails"] as? [String: Any]
        let title = videoDetails?["title"] as? String
        let durationStr = videoDetails?["lengthSeconds"] as? String

        return Result(
            platform: .youtube,
            originalURL: urlString,
            videoURL: (bestVideo?["url"] as? String).flatMap(URL.init(string:)),
            audioURL: (bestAudio?["url"] as? String).flatMap(URL.init(string:)),
            thumbnailURL: URL(string: "https://img.youtube.com/vi/\(videoId)/hqdefault.jpg"),
            title: title,
            duration: durationStr.flatMap(Double.init)
        )
    }
}
