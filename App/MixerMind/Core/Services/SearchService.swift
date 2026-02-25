import Foundation
import SwiftData

enum SearchService {

    struct SearchResult {
        let id: UUID
        let similarity: Double
    }

    /// Perform local semantic search against all mixes in SwiftData.
    /// Returns mix IDs ranked by cosine similarity to the query.
    static func search(
        query: String,
        tagIds: Set<UUID> = [],
        mixTagMap: [UUID: Set<UUID>] = [:],
        modelContext: ModelContext,
        limit: Int = 20
    ) async throws -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // 1. Embed the query locally
        let queryEmbeddingData = try await EmbeddingService.generate(from: trimmed)
        let queryVector = EmbeddingService.decode(queryEmbeddingData)

        // 2. Fetch all local mixes that have embeddings
        let descriptor = FetchDescriptor<LocalMix>()
        let localMixes = try modelContext.fetch(descriptor)

        // 3. Score each mix by cosine similarity
        var scored: [SearchResult] = []
        for mix in localMixes {
            guard let embeddingData = mix.localEmbedding else { continue }

            // Tag filter: skip mixes that don't match all selected tags
            if !tagIds.isEmpty {
                let mixTags = mixTagMap[mix.mixId] ?? []
                guard tagIds.isSubset(of: mixTags) else { continue }
            }

            let mixVector = EmbeddingService.decode(embeddingData)
            let similarity = EmbeddingService.cosineSimilarity(queryVector, mixVector)

            if similarity > 0.25 {
                scored.append(SearchResult(id: mix.mixId, similarity: similarity))
            }
        }

        // 4. Sort by similarity descending, take top results
        return scored
            .sorted { $0.similarity > $1.similarity }
            .prefix(limit)
            .map { $0 }
    }
}
