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
    var audioRemoved: Bool = false
    var mediaIsVideo: Bool = false
    var fileName: String?
    var widgets: [MixWidget]?
    var sourceUrl: String?

    // Local file paths (relative to MixMedia/) for raw media saved in Phase 1
    var rawMediaPath: String?
    var rawMediaThumbnailPath: String?
    var rawAudioPath: String?
    var rawEmbedOgImagePath: String?
    var rawFilePath: String?

    // Screenshot (captured in Phase 1, already on disk)
    var screenshotBucket: String?
    var screenshotPath: String?
    var previewCropX: Double?
    var previewCropY: Double?
    var previewCropScale: Double?
    var gradientTop: String?
    var gradientBottom: String?
}
