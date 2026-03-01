import Foundation

// MARK: - Mix Type

enum MixType: String, Codable, Equatable {
    case note       // was "text" — plain text note
    case media      // photo or video capture / library pick
    case voice      // voice recording
    case canvas     // gradient background (+ optional widgets on top)
    case `import`   // Instagram/YouTube video or audio import
}

// MARK: - Widget

enum MixWidgetType: String, Codable, Hashable {
    case embed
    case file
}

struct MixWidget: Codable, Hashable, Identifiable {
    let id: UUID
    let type: MixWidgetType
    // Position (for future drag editor)
    var x: Double = 0.5
    var y: Double = 0.5
    // Content
    var embedUrl: String?
    var embedOg: OGMetadata?
    var fileName: String?
    var fileLocalPath: String?
}

// MARK: - Mix

struct Mix: Identifiable, Hashable {
    let id: UUID
    let type: MixType
    let createdAt: Date
    var title: String?
    var tags: [Tag] = []

    // Text
    let textContent: String?

    // Audio (unified — TTS, voice recording, AI summary, silence)
    var audioUrl: String?

    // Media (photo or video)
    let mediaUrl: String?
    let mediaThumbnailUrl: String?
    let mediaIsVideo: Bool

    // Widgets (embed, file — layered on canvas)
    var widgets: [MixWidget]

    // Search content (AI-generated description / transcript)
    let content: String?

    // Screenshot preview
    let screenshotUrl: String?
    let previewCropX: Double?      // 0.0 = left, 0.5 = center, 1.0 = right
    let previewCropY: Double?      // 0.0 = top, 0.5 = center, 1.0 = bottom
    let previewCropScale: Double?  // Zoom factor (1.0 = no crop, 2.0 = show half)

    // Gradient background
    let gradientTop: String?
    let gradientBottom: String?

    // Import source
    let sourceUrl: String?

    // Text width bucket for note screenshots
    let screenshotBucket: String?

    var textBucket: ScreenshotService.TextBucket? { .init(stored: screenshotBucket) }

    init(
        id: UUID,
        type: MixType,
        createdAt: Date,
        title: String? = nil,
        tags: [Tag] = [],
        textContent: String? = nil,
        audioUrl: String? = nil,
        mediaUrl: String? = nil,
        mediaThumbnailUrl: String? = nil,
        mediaIsVideo: Bool = false,
        widgets: [MixWidget] = [],
        content: String? = nil,
        screenshotUrl: String? = nil,
        previewCropX: Double? = nil,
        previewCropY: Double? = nil,
        previewCropScale: Double? = nil,
        gradientTop: String? = nil,
        gradientBottom: String? = nil,
        sourceUrl: String? = nil,
        screenshotBucket: String? = nil
    ) {
        self.id = id
        self.type = type
        self.createdAt = createdAt
        self.title = title
        self.tags = tags
        self.textContent = textContent
        self.audioUrl = audioUrl
        self.mediaUrl = mediaUrl
        self.mediaThumbnailUrl = mediaThumbnailUrl
        self.mediaIsVideo = mediaIsVideo
        self.widgets = widgets
        self.content = content
        self.screenshotUrl = screenshotUrl
        self.previewCropX = previewCropX
        self.previewCropY = previewCropY
        self.previewCropScale = previewCropScale
        self.gradientTop = gradientTop
        self.gradientBottom = gradientBottom
        self.sourceUrl = sourceUrl
        self.screenshotBucket = screenshotBucket
    }

    // Convenience accessors for first widget of type
    var embedWidget: MixWidget? { widgets.first { $0.type == .embed } }
    var fileWidget: MixWidget? { widgets.first { $0.type == .file } }
    var embedUrl: String? { embedWidget?.embedUrl }
    var embedOg: OGMetadata? { embedWidget?.embedOg }
    var fileName: String? { fileWidget?.fileName }
}

struct OGMetadata: Codable, Hashable {
    let title: String?
    let description: String?
    let imageUrl: String?
    let host: String

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case imageUrl = "image_url"
        case host
    }
}

// MARK: - Tags

struct Tag: Identifiable, Hashable {
    let id: UUID
    let name: String
    let createdAt: Date
}

struct TagWithFrequency: Identifiable, Hashable {
    let tag: Tag
    var frequency: Int
    var id: UUID { tag.id }
    var name: String { tag.name }
}

// MARK: - Saved Views

struct SavedView: Identifiable, Hashable {
    let id: UUID
    let name: String
    let tagIds: [UUID]
    let createdAt: Date
}
