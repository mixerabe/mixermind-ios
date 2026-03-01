import Foundation
import Speech

enum ContentService {

    static func fromAudio(fileURL: URL?) async -> String {
        guard let fileURL else { return "Voice recording" }
        do {
            return try await transcribe(fileURL: fileURL)
        } catch {
            return "Voice recording"
        }
    }

    static func fromImage() -> String {
        "this is an image"
    }

    static func fromVideo() -> String {
        "this is a video"
    }

    // MARK: - Build content from text (direct copy)

    static func fromText(_ text: String) -> String {
        text
    }

    static func fromFile(name: String) -> String {
        name
    }

    static func fromImport(sourceUrl: String, title: String?) -> String {
        var parts: [String] = []
        if let title, !title.isEmpty { parts.append(title) }
        parts.append(sourceUrl)
        return parts.joined(separator: " — ")
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

    // MARK: - Transcription

    private static func transcribe(fileURL: URL) async throws -> String {
        let recognizer = SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            throw TranscriptionError.unavailable
        }

        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined {
            let granted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
            guard granted else { throw TranscriptionError.denied }
        } else if status != .authorized {
            throw TranscriptionError.denied
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    let text = result.bestTranscription.formattedString
                    continuation.resume(returning: text.isEmpty ? "Voice recording" : text)
                } else if let error {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private enum TranscriptionError: Error {
        case unavailable
        case denied
    }
}
