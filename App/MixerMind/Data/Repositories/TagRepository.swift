import Foundation
import Supabase

final class TagRepository {
    private var client: SupabaseClient {
        guard let client = SupabaseManager.shared.client else {
            fatalError("SupabaseManager not configured. Call configure() first.")
        }
        return client
    }

    // MARK: - Tags CRUD

    func listTags() async throws -> [Tag] {
        try await client.from("tags")
            .select()
            .order("name")
            .execute()
            .value
    }

    func createTag(name: String) async throws -> Tag {
        try await client.from("tags")
            .insert(["name": name])
            .select()
            .single()
            .execute()
            .value
    }

    func updateTag(id: UUID, name: String) async throws -> Tag {
        try await client.from("tags")
            .update(["name": name])
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    func deleteTag(id: UUID) async throws {
        try await client.from("tags")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Mix-Tag Relations

    func getTagIdsForMix(mixId: UUID) async throws -> [UUID] {
        let rows: [MixTagRow] = try await client.from("mix_tags")
            .select()
            .eq("mix_id", value: mixId)
            .execute()
            .value
        return rows.map(\.tagId)
    }

    func setTagsForMix(mixId: UUID, tagIds: Set<UUID>) async throws {
        // Delete existing
        try await client.from("mix_tags")
            .delete()
            .eq("mix_id", value: mixId)
            .execute()

        // Insert new
        if !tagIds.isEmpty {
            let rows = tagIds.map { ["mix_id": mixId.uuidString, "tag_id": $0.uuidString] }
            try await client.from("mix_tags")
                .insert(rows)
                .execute()
        }
    }

    func allMixTagRows() async throws -> [MixTagRow] {
        try await client.from("mix_tags")
            .select()
            .execute()
            .value
    }
}
