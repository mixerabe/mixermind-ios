import Foundation

struct MixCreationRequest: Codable {
    let mixId: UUID
    let mixType: MixType
    let createdAt: Date
    var textContent: String?
    var title: String?
    var selectedTagIds: [UUID] = []
    var embedUrl: String?
    var embedOgJson: Data?           // Encoded OGMetadata
    var importSourceUrl: String?
    var isAudioFromTTS: Bool = false
    var audioRemoved: Bool = false
    var audioFileName: String?

    // Local file paths (relative to MixMedia/) for raw media saved in Phase 1
    var rawPhotoPath: String?
    var rawVideoPath: String?
    var rawAudioPath: String?
    var rawImportMediaPath: String?
    var rawImportAudioPath: String?
    var rawPhotoThumbnailPath: String?
    var rawVideoThumbnailPath: String?
    var rawImportThumbnailPath: String?
    var rawEmbedOgImagePath: String?

    // Screenshot (captured in Phase 1, already on disk)
    var screenshotPath: String?
    var previewScaleY: Double?
    var gradientTop: String?
    var gradientBottom: String?
}
