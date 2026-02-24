import Foundation
import Supabase

final class SavedViewRepository {
    private var client: SupabaseClient {
        guard let client = SupabaseManager.shared.client else {
            fatalError("SupabaseManager not configured. Call configure() first.")
        }
        return client
    }

    func listSavedViews() async throws -> [SavedView] {
        try await client.from("playlists")
            .select()
            .order("name")
            .execute()
            .value
    }

    func createSavedView(name: String, tagIds: [UUID]) async throws -> SavedView {
        let payload = SavedViewPayload(name: name, tagIds: tagIds)
        return try await client.from("playlists")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
    }

    func updateTagIds(id: UUID, tagIds: [UUID]) async throws -> SavedView {
        let payload = TagIdsPayload(tagIds: tagIds)
        return try await client.from("playlists")
            .update(payload)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    func updateName(id: UUID, name: String) async throws -> SavedView {
        let payload = NamePayload(name: name)
        return try await client.from("playlists")
            .update(payload)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    func deleteSavedView(id: UUID) async throws {
        try await client.from("playlists")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}

private struct SavedViewPayload: Encodable {
    let name: String
    let tagIds: [UUID]

    enum CodingKeys: String, CodingKey {
        case name
        case tagIds = "tag_ids"
    }
}

private struct TagIdsPayload: Encodable {
    let tagIds: [UUID]

    enum CodingKeys: String, CodingKey {
        case tagIds = "tag_ids"
    }
}

private struct NamePayload: Encodable {
    let name: String
}
