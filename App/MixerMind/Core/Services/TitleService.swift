import Foundation

enum TitleService {

    // MARK: - Generate title from text

    static func fromText(_ text: String) async throws -> String {
        guard !text.isEmpty else { throw TitleError.emptyInput }

        guard let endpoint = URL(string: "\(Constants.backendURL)/api/title/from-text") else {
            throw TitleError.invalidResponse
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body = ["text": text]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TitleError.invalidResponse
        }

        let result = try JSONDecoder().decode(TextTitleResponse.self, from: data)
        return result.title
    }

    // MARK: - Generate title from audio

    static func fromAudio(data audioData: Data, fileName: String, contentType: String = "audio/m4a") async throws -> String {
        guard !audioData.isEmpty else { throw TitleError.emptyInput }

        guard let endpoint = URL(string: "\(Constants.backendURL)/api/title/from-audio") else {
            throw TitleError.invalidResponse
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TitleError.invalidResponse
        }

        let result = try JSONDecoder().decode(AudioTitleResponse.self, from: data)
        return result.title
    }

    // MARK: - Response Models

    private struct TextTitleResponse: Decodable {
        let title: String
    }

    private struct AudioTitleResponse: Decodable {
        let title: String
        let transcript: String?
    }

    // MARK: - Errors

    enum TitleError: LocalizedError {
        case emptyInput
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .emptyInput: return "No content to generate title from"
            case .invalidResponse: return "Failed to generate title"
            }
        }
    }
}
