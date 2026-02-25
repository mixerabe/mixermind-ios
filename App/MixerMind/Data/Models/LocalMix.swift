import Foundation
import SwiftData

@Model
final class LocalMix {
    @Attribute(.unique) var mixId: UUID
    var type: String
    var createdAt: Date
    var title: String?

    // Text
    var textContent: String?

    // Remote URLs (from Supabase)
    var remoteTtsAudioUrl: String?
    var remotePhotoUrl: String?
    var remotePhotoThumbnailUrl: String?
    var remoteVideoUrl: String?
    var remoteVideoThumbnailUrl: String?
    var remoteImportSourceUrl: String?
    var remoteImportMediaUrl: String?
    var remoteImportThumbnailUrl: String?
    var remoteImportAudioUrl: String?
    var remoteEmbedUrl: String?
    var remoteEmbedOgJson: Data?
    var remoteAudioUrl: String?

    // Import source URL (metadata, not a file to download)
    var importSourceUrl: String?

    // Local relative paths (relative to Documents/MixMedia/)
    var localTtsAudioPath: String?
    var localPhotoPath: String?
    var localPhotoThumbnailPath: String?
    var localVideoPath: String?
    var localVideoThumbnailPath: String?
    var localImportMediaPath: String?
    var localImportThumbnailPath: String?
    var localImportAudioPath: String?
    var localEmbedOgImagePath: String?
    var localAudioPath: String?
    var localScreenshotPath: String?

    // Screenshot preview
    var remoteScreenshotUrl: String?
    var previewScaleY: Double?
    var gradientTop: String?
    var gradientBottom: String?

    var isSynced: Bool = false

    init(mixId: UUID, type: String, createdAt: Date) {
        self.mixId = mixId
        self.type = type
        self.createdAt = createdAt
    }

    // MARK: - Update from Remote

    func updateFromRemote(_ mix: Mix) {
        type = mix.type.rawValue
        createdAt = mix.createdAt
        title = mix.title
        textContent = mix.textContent

        remoteTtsAudioUrl = mix.ttsAudioUrl
        remotePhotoUrl = mix.photoUrl
        remotePhotoThumbnailUrl = mix.photoThumbnailUrl
        remoteVideoUrl = mix.videoUrl
        remoteVideoThumbnailUrl = mix.videoThumbnailUrl
        remoteImportSourceUrl = mix.importSourceUrl
        remoteImportMediaUrl = mix.importMediaUrl
        remoteImportThumbnailUrl = mix.importThumbnailUrl
        remoteImportAudioUrl = mix.importAudioUrl
        remoteEmbedUrl = mix.embedUrl
        remoteAudioUrl = mix.audioUrl
        importSourceUrl = mix.importSourceUrl
        remoteScreenshotUrl = mix.screenshotUrl
        previewScaleY = mix.previewScaleY
        gradientTop = mix.gradientTop
        gradientBottom = mix.gradientBottom

        if let og = mix.embedOg {
            remoteEmbedOgJson = try? JSONEncoder().encode(og)
        } else {
            remoteEmbedOgJson = nil
        }
    }

    // MARK: - Convert to Mix

    func toMix(tags: [Tag] = []) -> Mix {
        let fileManager = LocalFileManager.shared

        let embedOg: OGMetadata? = {
            guard let data = remoteEmbedOgJson else { return nil }
            guard var og = try? JSONDecoder().decode(OGMetadata.self, from: data) else { return nil }
            // Rewrite OG image URL to local file:// path when available
            if let localPath = localEmbedOgImagePath, fileManager.fileExists(at: localPath) {
                og = OGMetadata(
                    title: og.title,
                    description: og.description,
                    imageUrl: fileManager.fileURL(for: localPath).absoluteString,
                    host: og.host
                )
            }
            return og
        }()

        return Mix(
            id: mixId,
            type: MixType(rawValue: type) ?? .text,
            createdAt: createdAt,
            title: title,
            tags: tags,
            textContent: textContent,
            ttsAudioUrl: localURL(localTtsAudioPath, remote: remoteTtsAudioUrl, fileManager: fileManager),
            photoUrl: localURL(localPhotoPath, remote: remotePhotoUrl, fileManager: fileManager),
            photoThumbnailUrl: localURL(localPhotoThumbnailPath, remote: remotePhotoThumbnailUrl, fileManager: fileManager),
            videoUrl: localURL(localVideoPath, remote: remoteVideoUrl, fileManager: fileManager),
            videoThumbnailUrl: localURL(localVideoThumbnailPath, remote: remoteVideoThumbnailUrl, fileManager: fileManager),
            importSourceUrl: importSourceUrl,
            importMediaUrl: localURL(localImportMediaPath, remote: remoteImportMediaUrl, fileManager: fileManager),
            importThumbnailUrl: localURL(localImportThumbnailPath, remote: remoteImportThumbnailUrl, fileManager: fileManager),
            importAudioUrl: localURL(localImportAudioPath, remote: remoteImportAudioUrl, fileManager: fileManager),
            embedUrl: remoteEmbedUrl,
            embedOg: embedOg,
            audioUrl: localURL(localAudioPath, remote: remoteAudioUrl, fileManager: fileManager),
            screenshotUrl: localURL(localScreenshotPath, remote: remoteScreenshotUrl, fileManager: fileManager),
            previewScaleY: previewScaleY,
            gradientTop: gradientTop,
            gradientBottom: gradientBottom
        )
    }

    private func localURL(_ localPath: String?, remote: String?, fileManager: LocalFileManager) -> String? {
        if let localPath, fileManager.fileExists(at: localPath) {
            return fileManager.fileURL(for: localPath).absoluteString
        }
        return remote
    }
}
