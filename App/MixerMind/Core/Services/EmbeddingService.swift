import Foundation

enum EmbeddingService {

    static func generate(from text: String) async throws -> [Double] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EmbeddingError.emptyInput }

        guard let endpoint = URL(string: "\(Constants.backendURL)/api/embeddings") else {
            throw EmbeddingError.invalidResponse
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body = ["text": trimmed]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw EmbeddingError.invalidResponse
        }

        let result = try JSONDecoder().decode(EmbeddingResponse.self, from: data)
        return result.embedding
    }

    private struct EmbeddingResponse: Decodable {
        let embedding: [Double]
    }

    enum EmbeddingError: LocalizedError {
        case emptyInput
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .emptyInput: return "No text to embed"
            case .invalidResponse: return "Failed to generate embedding"
            }
        }
    }
}
