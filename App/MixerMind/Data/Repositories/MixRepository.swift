import Foundation
import Supabase

final class MixRepository {
    private var client: SupabaseClient {
        guard let client = SupabaseManager.shared.client else {
            fatalError("SupabaseManager not configured. Call configure() first.")
        }
        return client
    }

    // MARK: - CRUD

    func listMixes() async throws -> [Mix] {
        try await client.from("mixes")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func getMix(id: UUID) async throws -> Mix {
        try await client.from("mixes")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    func createMix(_ payload: CreateMixPayload) async throws -> Mix {
        try await client.from("mixes")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
    }

    func updateMix(id: UUID, _ payload: UpdateMixPayload) async throws -> Mix {
        try await client.from("mixes")
            .update(payload)
            .eq("id", value: id)
            .select()
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
            .select()
            .single()
            .execute()
            .value
    }

    private struct CaptionUpdate: Encodable {
        let caption: String?

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(caption, forKey: .caption)
        }

        enum CodingKeys: String, CodingKey { case caption }
    }

    func updateCaption(id: UUID, caption: String?) async throws -> Mix {
        try await client.from("mixes")
            .update(CaptionUpdate(caption: caption))
            .eq("id", value: id)
            .select()
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
