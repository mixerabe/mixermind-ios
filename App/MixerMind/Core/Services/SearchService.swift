import Foundation
import Supabase

enum SearchService {

    struct SearchResult: Decodable {
        let id: UUID
        let type: MixType
        let createdAt: Date
        let title: String?
        let photoThumbnailUrl: String?
        let videoThumbnailUrl: String?
        let importThumbnailUrl: String?
        let appleMusicArtworkUrl: String?
        let embedOg: OGMetadata?

        enum CodingKeys: String, CodingKey {
            case id, type, title
            case createdAt = "created_at"
            case photoThumbnailUrl = "photo_thumbnail_url"
            case videoThumbnailUrl = "video_thumbnail_url"
            case importThumbnailUrl = "import_thumbnail_url"
            case appleMusicArtworkUrl = "apple_music_artwork_url"
            case embedOg = "embed_og"
        }
    }

    private struct SearchRequest: Encodable {
        let query: String
        let limit: Int
    }

    private struct EdgeFunctionResponse: Decodable {
        let results: [SearchResult]
    }

    static func search(query: String) async throws -> [SearchResult] {
        guard let client = SupabaseManager.shared.client else {
            throw SearchError.notConfigured
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // The SDK generic invoke decodes directly
        let response: EdgeFunctionResponse = try await client.functions.invoke(
            "search",
            options: .init(body: SearchRequest(query: trimmed, limit: 20))
        )
        return response.results
    }

    enum SearchError: LocalizedError {
        case notConfigured

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Supabase not configured"
            }
        }
    }
}
