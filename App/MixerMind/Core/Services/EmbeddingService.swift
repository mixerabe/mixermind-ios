import Foundation
import NaturalLanguage

enum EmbeddingService {

    /// Generate a local embedding from text using Apple's NLContextualEmbedding.
    /// Returns a [Float] vector (512 dimensions) encoded as Data for storage.
    static func generate(from text: String) async throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EmbeddingError.emptyInput }

        // NLContextualEmbedding is synchronous and CPU-bound — run off main
        return try await Task.detached {
            guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
                throw EmbeddingError.modelUnavailable
            }

            guard let vector = embedding.vector(for: trimmed) else {
                throw EmbeddingError.embeddingFailed
            }

            // Encode [Double] -> Data for compact storage
            return vector.withUnsafeBufferPointer { buffer in
                Data(buffer: buffer)
            }
        }.value
    }

    /// Decode stored embedding Data back to [Double].
    static func decode(_ data: Data) -> [Double] {
        data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Double.self))
        }
    }

    /// Cosine similarity between two vectors.
    static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for i in a.indices {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 0 else { return 0 }
        return dot / denom
    }

    enum EmbeddingError: LocalizedError {
        case emptyInput
        case modelUnavailable
        case embeddingFailed

        var errorDescription: String? {
            switch self {
            case .emptyInput: return "No text to embed"
            case .modelUnavailable: return "Sentence embedding model not available"
            case .embeddingFailed: return "Failed to generate embedding"
            }
        }
    }
}
