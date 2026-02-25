import Foundation
import Supabase

final class MixRepository {
    private var client: SupabaseClient {
        guard let client = SupabaseManager.shared.client else {
            fatalError("SupabaseManager not configured. Call configure() first.")
        }
        return client
    }

    /// All columns except `content_tsv` and `content_embedding` (pgvector search-only).
    private static let mixColumns = """
        id, type, created_at, title, \
        text_content, tts_audio_url, \
        photo_url, photo_thumbnail_url, \
        video_url, video_thumbnail_url, \
        import_source_url, import_media_url, import_thumbnail_url, import_audio_url, \
        embed_url, embed_og, \
        audio_url, content, \
        screenshot_url, preview_scale_y, \
        gradient_top, gradient_bottom
        """

    // MARK: - CRUD

    func listMixes() async throws -> [Mix] {
        try await client.from("mixes")
            .select(Self.mixColumns)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func getMix(id: UUID) async throws -> Mix {
        try await client.from("mixes")
            .select(Self.mixColumns)
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    func createMix(_ payload: CreateMixPayload) async throws -> Mix {
        try await client.from("mixes")
            .insert(payload)
            .select(Self.mixColumns)
            .single()
            .execute()
            .value
    }

    func updateMix(id: UUID, _ payload: UpdateMixPayload) async throws -> Mix {
        try await client.from("mixes")
            .update(payload)
            .eq("id", value: id)
            .select(Self.mixColumns)
            .single()
            .execute()
            .value
    }

    private struct TitleUpdate: Encodable {
        let title: String?

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(title, forKey: .title)
        }

        enum CodingKeys: String, CodingKey { case title }
    }

    func updateTitle(id: UUID, title: String?) async throws -> Mix {
        try await client.from("mixes")
            .update(TitleUpdate(title: title))
            .eq("id", value: id)
            .select(Self.mixColumns)
            .single()
            .execute()
            .value
    }

    func deleteMix(id: UUID) async throws {
        try await client.from("mixes")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Storage

    func uploadMedia(data: Data, fileName: String, contentType: String) async throws -> String {
        let path = "\(UUID().uuidString)/\(fileName)"

        try await client.storage
            .from("mix-media")
            .upload(path, data: data, options: .init(contentType: contentType))

        let publicURL = try client.storage
            .from("mix-media")
            .getPublicURL(path: path)

        return publicURL.absoluteString
    }
}
