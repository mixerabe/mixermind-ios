import Foundation

enum ContentService {

    // MARK: - Transcribe audio to text

    static func fromAudio(data audioData: Data, fileName: String, contentType: String = "audio/m4a") async throws -> String {
        guard !audioData.isEmpty else { throw ContentError.emptyInput }

        guard let endpoint = URL(string: "\(Constants.backendURL)/api/content/from-audio") else {
            throw ContentError.invalidResponse
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ContentError.invalidResponse
        }

        let result = try JSONDecoder().decode(ContentResponse.self, from: data)
        return result.content
    }

    // MARK: - Describe image via vision LLM

    static func fromImage(imageData: Data) async throws -> String {
        guard !imageData.isEmpty else { throw ContentError.emptyInput }

        guard let endpoint = URL(string: "\(Constants.backendURL)/api/content/from-image") else {
            throw ContentError.invalidResponse
        }

        let base64 = imageData.base64EncodedString()

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let body = ["image_base64": base64]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ContentError.invalidResponse
        }

        let result = try JSONDecoder().decode(ContentResponse.self, from: data)
        return result.content
    }

    // MARK: - Build content from text (direct copy)

    static func fromText(_ text: String) -> String {
        text
    }

    // MARK: - Build content from embed metadata

    static func fromEmbed(og: OGMetadata?, url: String) -> String {
        var parts: [String] = []
        if let title = og?.title, !title.isEmpty { parts.append(title) }
        if let desc = og?.description, !desc.isEmpty { parts.append(desc) }
        if let host = og?.host, !host.isEmpty { parts.append(host) }
        if parts.isEmpty { parts.append(url) }
        return parts.joined(separator: " — ")
    }

    // MARK: - Models

    private struct ContentResponse: Decodable {
        let content: String
    }

    enum ContentError: LocalizedError {
        case emptyInput
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .emptyInput: return "No content to analyze"
            case .invalidResponse: return "Failed to generate content"
            }
        }
    }
}
