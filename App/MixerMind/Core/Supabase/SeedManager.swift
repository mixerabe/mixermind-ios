import Foundation
import UIKit

struct SeedMix: Decodable {
    let type: String
    let textContent: String?
    let mediaFile: String?
    let audioFile: String?

    enum CodingKeys: String, CodingKey {
        case type
        case textContent = "text_content"
        case mediaFile = "media_file"
        case audioFile = "audio_file"
    }
}

enum SeedManager {
    static func seedMixes() async throws {
        guard let url = Bundle.main.url(forResource: "seed_mixes", withExtension: "json") else {
            throw SeedError.fileNotFound
        }

        let data = try Data(contentsOf: url)
        let seeds = try JSONDecoder().decode([SeedMix].self, from: data)

        let repo = MixRepository()

        for seed in seeds {
            guard let mixType = MixType(rawValue: seed.type) else { continue }

            var payload = CreateMixPayload(type: mixType)
            payload.textContent = seed.textContent

            // Upload media file if referenced
            if let mediaFile = seed.mediaFile {
                let mediaData = try loadBundleFile(named: mediaFile)

                switch mixType {
                case .photo:
                    let contentType = imageContentType(for: mediaFile)
                    let url = try await repo.uploadMedia(data: mediaData, fileName: mediaFile, contentType: contentType)
                    payload.photoUrl = url
                    // Generate thumbnail
                    if let thumb = await generateThumbnail(imageData: mediaData, repo: repo) {
                        payload.photoThumbnailUrl = thumb
                    }

                case .video:
                    let url = try await repo.uploadMedia(data: mediaData, fileName: mediaFile, contentType: "video/mp4")
                    payload.videoUrl = url

                default:
                    break
                }
            }

            // Upload audio file if referenced
            if let audioFile = seed.audioFile {
                let audioData = try loadBundleFile(named: audioFile)
                let contentType = audioContentType(for: audioFile)
                let url = try await repo.uploadMedia(data: audioData, fileName: audioFile, contentType: contentType)
                payload.audioUrl = url
            }

            _ = try await repo.createMix(payload)
        }
    }

    private static func loadBundleFile(named name: String) throws -> Data {
        let nameWithoutExt = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension

        guard let url = Bundle.main.url(forResource: nameWithoutExt, withExtension: ext) else {
            throw SeedError.mediaNotFound(name)
        }
        return try Data(contentsOf: url)
    }

    private static func imageContentType(for fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        default: return "image/jpeg"
        }
    }

    private static func audioContentType(for fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "mp3": return "audio/mpeg"
        case "m4a", "aac": return "audio/aac"
        case "wav": return "audio/wav"
        default: return "audio/mpeg"
        }
    }

    @MainActor
    private static func generateThumbnail(imageData: Data, repo: MixRepository) async -> String? {
        guard let uiImage = UIImage(data: imageData) else { return nil }

        let targetWidth: CGFloat = 300
        let scale = targetWidth / uiImage.size.width
        let targetSize = CGSize(width: targetWidth, height: uiImage.size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let resized = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            uiImage.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let jpegData = resized.jpegData(compressionQuality: 0.5) else { return nil }

        return try? await repo.uploadMedia(
            data: jpegData,
            fileName: "thumb.jpg",
            contentType: "image/jpeg"
        )
    }
}

enum SeedError: LocalizedError {
    case fileNotFound
    case mediaNotFound(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "seed_mixes.json not found in app bundle"
        case .mediaNotFound(let name):
            return "Seed media file '\(name)' not found in app bundle"
        }
    }
}
