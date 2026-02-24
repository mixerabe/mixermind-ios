import Foundation

enum TTSVoice: String, CaseIterable {
    case alloy, ash, ballad, coral, echo, fable, nova, onyx, sage, shimmer
}

enum TextToSpeechService {
    static func synthesize(
        text: String,
        voice: TTSVoice = .onyx
    ) async throws -> Data {
        guard !text.isEmpty else {
            throw TTSError.emptyText
        }

        guard let endpoint = URL(string: "\(Constants.backendURL)/api/tts") else {
            throw TTSError.invalidResponse
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let body: [String: String] = ["text": text, "voice": voice.rawValue]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw TTSError.invalidResponse
        }

        guard http.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TTSError.apiError(statusCode: http.statusCode, message: message)
        }

        return data
    }

    enum TTSError: LocalizedError {
        case emptyText
        case invalidResponse
        case apiError(statusCode: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .emptyText:
                return "No text to convert"
            case .invalidResponse:
                return "Invalid response from TTS service"
            case .apiError(let code, let message):
                return "TTS failed (\(code)): \(message)"
            }
        }
    }
}
