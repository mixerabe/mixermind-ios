import Foundation

// MARK: - Mix Type

enum MixType: String, Codable, Equatable {
    case text
    case photo
    case video
    case `import`
    case embed
    case audio
}

// MARK: - Mix

struct Mix: Codable, Identifiable, Hashable {
    let id: UUID
    let type: MixType
    let createdAt: Date
    let title: String?
    var tags: [Tag] = []

    // Text
    let textContent: String?
    let ttsAudioUrl: String?

    // Photo
    let photoUrl: String?
    let photoThumbnailUrl: String?

    // Video
    let videoUrl: String?
    let videoThumbnailUrl: String?

    // Import
    let importSourceUrl: String?
    let importMediaUrl: String?
    let importThumbnailUrl: String?
    let importAudioUrl: String?

    // Embed
    let embedUrl: String?
    let embedOg: OGMetadata?

    // Audio
    let audioUrl: String?

    // Screenshot preview
    let screenshotUrl: String?
    let previewScaleX: Double?
    let previewScaleY: Double?

    init(
        id: UUID,
        type: MixType,
        createdAt: Date,
        title: String? = nil,
        tags: [Tag] = [],
        textContent: String? = nil,
        ttsAudioUrl: String? = nil,
        photoUrl: String? = nil,
        photoThumbnailUrl: String? = nil,
        videoUrl: String? = nil,
        videoThumbnailUrl: String? = nil,
        importSourceUrl: String? = nil,
        importMediaUrl: String? = nil,
        importThumbnailUrl: String? = nil,
        importAudioUrl: String? = nil,
        embedUrl: String? = nil,
        embedOg: OGMetadata? = nil,
        audioUrl: String? = nil,
        screenshotUrl: String? = nil,
        previewScaleX: Double? = nil,
        previewScaleY: Double? = nil
    ) {
        self.id = id
        self.type = type
        self.createdAt = createdAt
        self.title = title
        self.tags = tags
        self.textContent = textContent
        self.ttsAudioUrl = ttsAudioUrl
        self.photoUrl = photoUrl
        self.photoThumbnailUrl = photoThumbnailUrl
        self.videoUrl = videoUrl
        self.videoThumbnailUrl = videoThumbnailUrl
        self.importSourceUrl = importSourceUrl
        self.importMediaUrl = importMediaUrl
        self.importThumbnailUrl = importThumbnailUrl
        self.importAudioUrl = importAudioUrl
        self.embedUrl = embedUrl
        self.embedOg = embedOg
        self.audioUrl = audioUrl
        self.screenshotUrl = screenshotUrl
        self.previewScaleX = previewScaleX
        self.previewScaleY = previewScaleY
    }

    enum CodingKeys: String, CodingKey {
        case id, type, title // tags excluded — populated locally
        case createdAt = "created_at"
        case textContent = "text_content"
        case ttsAudioUrl = "tts_audio_url"
        case photoUrl = "photo_url"
        case photoThumbnailUrl = "photo_thumbnail_url"
        case videoUrl = "video_url"
        case videoThumbnailUrl = "video_thumbnail_url"
        case importSourceUrl = "import_source_url"
        case importMediaUrl = "import_media_url"
        case importThumbnailUrl = "import_thumbnail_url"
        case importAudioUrl = "import_audio_url"
        case embedUrl = "embed_url"
        case embedOg = "embed_og"
        case audioUrl = "audio_url"
        case screenshotUrl = "screenshot_url"
        case previewScaleX = "preview_scale_x"
        case previewScaleY = "preview_scale_y"
    }
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

// MARK: - Create Mix Payload

/// pgvector expects a string like "[0.1,0.2,...]" via PostgREST
struct PgVector: Encodable {
    let values: [Double]

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let str = "[" + values.map { String($0) }.joined(separator: ",") + "]"
        try container.encode(str)
    }
}

struct CreateMixPayload: Encodable {
    let type: MixType
    var title: String? = nil
    var textContent: String? = nil
    var ttsAudioUrl: String? = nil
    var photoUrl: String? = nil
    var photoThumbnailUrl: String? = nil
    var videoUrl: String? = nil
    var videoThumbnailUrl: String? = nil
    var importSourceUrl: String? = nil
    var importMediaUrl: String? = nil
    var importThumbnailUrl: String? = nil
    var importAudioUrl: String? = nil
    var embedUrl: String? = nil
    var embedOg: OGMetadata? = nil
    var audioUrl: String? = nil
    var screenshotUrl: String? = nil
    var previewScaleX: Double? = nil
    var previewScaleY: Double? = nil
    var content: String? = nil
    var contentEmbedding: PgVector? = nil

    enum CodingKeys: String, CodingKey {
        case type, title, content
        case textContent = "text_content"
        case ttsAudioUrl = "tts_audio_url"
        case photoUrl = "photo_url"
        case photoThumbnailUrl = "photo_thumbnail_url"
        case videoUrl = "video_url"
        case videoThumbnailUrl = "video_thumbnail_url"
        case importSourceUrl = "import_source_url"
        case importMediaUrl = "import_media_url"
        case importThumbnailUrl = "import_thumbnail_url"
        case importAudioUrl = "import_audio_url"
        case embedUrl = "embed_url"
        case embedOg = "embed_og"
        case audioUrl = "audio_url"
        case screenshotUrl = "screenshot_url"
        case previewScaleX = "preview_scale_x"
        case previewScaleY = "preview_scale_y"
        case contentEmbedding = "content_embedding"
    }
}

struct UpdateMixPayload: Encodable {
    var title: String? = nil
    var textContent: String? = nil
    var ttsAudioUrl: String? = nil
    var photoUrl: String? = nil
    var photoThumbnailUrl: String? = nil
    var videoUrl: String? = nil
    var videoThumbnailUrl: String? = nil
    var importSourceUrl: String? = nil
    var importMediaUrl: String? = nil
    var importThumbnailUrl: String? = nil
    var importAudioUrl: String? = nil
    var embedUrl: String? = nil
    var embedOg: OGMetadata? = nil
    var audioUrl: String? = nil
    var screenshotUrl: String? = nil
    var previewScaleX: Double? = nil
    var previewScaleY: Double? = nil
    var content: String? = nil
    var contentEmbedding: PgVector? = nil

    enum CodingKeys: String, CodingKey {
        case title, content
        case textContent = "text_content"
        case ttsAudioUrl = "tts_audio_url"
        case photoUrl = "photo_url"
        case photoThumbnailUrl = "photo_thumbnail_url"
        case videoUrl = "video_url"
        case videoThumbnailUrl = "video_thumbnail_url"
        case importSourceUrl = "import_source_url"
        case importMediaUrl = "import_media_url"
        case importThumbnailUrl = "import_thumbnail_url"
        case importAudioUrl = "import_audio_url"
        case embedUrl = "embed_url"
        case embedOg = "embed_og"
        case audioUrl = "audio_url"
        case screenshotUrl = "screenshot_url"
        case previewScaleX = "preview_scale_x"
        case previewScaleY = "preview_scale_y"
        case contentEmbedding = "content_embedding"
    }
}

// MARK: - Tags

struct Tag: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdAt = "created_at"
    }
}

struct TagWithFrequency: Identifiable, Hashable {
    let tag: Tag
    var frequency: Int
    var id: UUID { tag.id }
    var name: String { tag.name }
}

struct MixTagRow: Codable {
    let mixId: UUID
    let tagId: UUID

    enum CodingKeys: String, CodingKey {
        case mixId = "mix_id"
        case tagId = "tag_id"
    }
}

// MARK: - Saved Views

struct SavedView: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let tagIds: [UUID]
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name
        case tagIds = "tag_ids"
        case createdAt = "created_at"
    }
}
