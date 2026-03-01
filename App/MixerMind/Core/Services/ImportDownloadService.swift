import Foundation
import AVFoundation
import UIKit

enum ImportMode {
    case video
    case audioOnly
}

struct ImportResult {
    let videoData: Data
    let title: String?
    let thumbnailUrl: String?
    let sourceUrl: String
    let mode: ImportMode
}

enum ImportDownloadService {

    enum ImportError: LocalizedError {
        case unsupportedPlatform
        case invalidURL
        case downloadFailed(String)
        case noData

        var errorDescription: String? {
            switch self {
            case .unsupportedPlatform: return "Only Instagram and YouTube links are supported"
            case .invalidURL: return "Invalid URL"
            case .downloadFailed(let msg): return msg
            case .noData: return "No data received"
            }
        }
    }

    static func detectPlatform(_ url: String) -> String? {
        let lower = url.lowercased()
        if lower.contains("instagram.com") || lower.contains("instagr.am") {
            return "instagram"
        }
        if lower.contains("youtube.com") || lower.contains("youtu.be") {
            return "youtube"
        }
        return nil
    }

    static func download(url: String, mode: ImportMode) async throws -> ImportResult {
        guard detectPlatform(url) != nil else {
            throw ImportError.unsupportedPlatform
        }

        let endpoint = "\(Constants.backendURL)/api/media/download"
        guard let requestURL = URL(string: endpoint) else {
            throw ImportError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "url": url,
            "audio_only": mode == .audioOnly
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ImportError.noData
        }

        if httpResponse.statusCode != 200 {
            let message = String(data: data, encoding: .utf8) ?? "Download failed"
            throw ImportError.downloadFailed(message)
        }

        guard !data.isEmpty else {
            throw ImportError.noData
        }

        let title = httpResponse.value(forHTTPHeaderField: "X-Video-Title")
        let thumbnailUrl = httpResponse.value(forHTTPHeaderField: "X-Video-Thumbnail")

        return ImportResult(
            videoData: data,
            title: title,
            thumbnailUrl: thumbnailUrl,
            sourceUrl: url,
            mode: mode
        )
    }

    static func generateThumbnail(from videoData: Data) async -> UIImage? {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")
        do {
            try videoData.write(to: tempURL)
        } catch {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let asset = AVURLAsset(url: tempURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)

        guard let cgImage = try? await generator.image(at: .zero).image else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
