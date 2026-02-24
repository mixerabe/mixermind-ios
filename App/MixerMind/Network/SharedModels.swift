import Foundation

// MARK: - Mix Type

enum MixType: String, Codable, Equatable {
    case text
    case photo
    case video
    case `import`
    case embed
    case audio
    case appleMusic = "apple_music"
}

// MARK: - Mix

struct Mix: Codable, Identifiable, Hashable {
    let id: UUID
    let type: MixType
    let createdAt: Date
    let title: String?
    let caption: String?
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

    // Apple Music
    let appleMusicId: String?
    let appleMusicTitle: String?
    let appleMusicArtist: String?
    let appleMusicArtworkUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, type, title, caption // tags excluded — populated locally
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
        case appleMusicId = "apple_music_id"
        case appleMusicTitle = "apple_music_title"
        case appleMusicArtist = "apple_music_artist"
        case appleMusicArtworkUrl = "apple_music_artwork_url"
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

struct CreateMixPayload: Encodable {
    let type: MixType
    var title: String? = nil
    var caption: String? = nil
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
    var appleMusicId: String? = nil
    var appleMusicTitle: String? = nil
    var appleMusicArtist: String? = nil
    var appleMusicArtworkUrl: String? = nil

    enum CodingKeys: String, CodingKey {
        case type, title, caption
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
        case appleMusicId = "apple_music_id"
        case appleMusicTitle = "apple_music_title"
        case appleMusicArtist = "apple_music_artist"
        case appleMusicArtworkUrl = "apple_music_artwork_url"
    }
}

struct UpdateMixPayload: Encodable {
    var title: String? = nil
    var caption: String? = nil
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
    var appleMusicId: String? = nil
    var appleMusicTitle: String? = nil
    var appleMusicArtist: String? = nil
    var appleMusicArtworkUrl: String? = nil

    enum CodingKeys: String, CodingKey {
        case title, caption
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
        case appleMusicId = "apple_music_id"
        case appleMusicTitle = "apple_music_title"
        case appleMusicArtist = "apple_music_artist"
        case appleMusicArtworkUrl = "apple_music_artwork_url"
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
