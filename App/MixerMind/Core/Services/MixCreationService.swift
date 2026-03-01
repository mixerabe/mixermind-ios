import Foundation
import CoreData
import AVFoundation
import UIKit

/// In-memory media blob passed alongside the creation request.
struct MixCreationMedia {
    var mediaData: Data?
    var mediaIsVideo: Bool = false
    var mediaThumbnailData: Data?
    var audioData: Data?
    var embedOgImageData: Data?
    var fileData: Data?
    var fileName: String?
}

@Observable @MainActor
final class MixCreationService {
    private let fileManager = LocalFileManager.shared

    static let didFinishCreation = Notification.Name("MixCreationService.didFinishCreation")

    // MARK: - Create (background, fire-and-forget)

    /// Persists raw media synchronously then kicks off heavy processing in the background.
    /// Posts `didFinishCreation` when the mix is saved to Core Data.
    func create(request: MixCreationRequest, media: MixCreationMedia, context: NSManagedObjectContext) {
        var updatedRequest = request
        persistRawMedia(request: &updatedRequest, media: media)
        Task {
            await process(request: updatedRequest, context: context)
            NotificationCenter.default.post(name: Self.didFinishCreation, object: nil)
        }
    }

    // MARK: - Persist Raw Media

    private func persistRawMedia(request: inout MixCreationRequest, media: MixCreationMedia) {
        let mixDir = request.mixId.uuidString
        let dirURL = fileManager.fileURL(for: mixDir)
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        func writeIfNeeded(_ data: Data?, name: String, existingPath: String?) -> String? {
            if existingPath != nil { return existingPath }
            guard let data else { return nil }
            let path = "\(mixDir)/\(name)"
            let url = fileManager.fileURL(for: path)
            do { try data.write(to: url); return path } catch { return nil }
        }

        let mediaExt = media.mediaIsVideo ? "mp4" : "jpg"
        request.rawMediaPath = writeIfNeeded(media.mediaData, name: "raw_media.\(mediaExt)", existingPath: request.rawMediaPath)
        request.rawMediaThumbnailPath = writeIfNeeded(media.mediaThumbnailData, name: "media_thumb.jpg", existingPath: request.rawMediaThumbnailPath)
        request.rawAudioPath = writeIfNeeded(media.audioData, name: "raw_audio.m4a", existingPath: request.rawAudioPath)
        request.rawEmbedOgImagePath = writeIfNeeded(media.embedOgImageData, name: "embed_og.jpg", existingPath: request.rawEmbedOgImagePath)

        if let fileData = media.fileData, let fileName = media.fileName ?? request.fileName {
            let ext = (fileName as NSString).pathExtension
            let name = ext.isEmpty ? "raw_file" : "raw_file.\(ext)"
            request.rawFilePath = writeIfNeeded(fileData, name: name, existingPath: request.rawFilePath)
            request.fileName = fileName
        }
    }

    // MARK: - Process

    private func process(request: MixCreationRequest, context: NSManagedObjectContext) async {
        let mixId = request.mixId
        let mixDir = mixId.uuidString

        func saveLocal(_ data: Data, name: String) -> String {
            let path = "\(mixDir)/\(name)"
            let url = fileManager.fileURL(for: path)
            try? data.write(to: url)
            return path
        }

        var localPaths: [String: String] = [:]

        do {
            // 1. Compress media & save locally
            switch request.mixType {
            case .note:
                // Audio is added manually in the editor (via "Add audio" chip).
                // If the user generated TTS before saving, it arrives via rawAudioPath.
                if let path = request.rawAudioPath, let data = readFile(path) {
                    localPaths["audio"] = saveLocal(data, name: "tts.mp3")
                }

            case .media:
                if request.mediaIsVideo {
                    if let path = request.rawMediaPath, let data = readFile(path) {
                        let compressed = try await compressVideo(data: data)
                        localPaths["media"] = saveLocal(compressed, name: "media.mp4")
                        let audioTrackData: Data
                        if request.audioRemoved {
                            let duration = try await videoDuration(from: data)
                            audioTrackData = try generateSilence(duration: duration)
                        } else {
                            audioTrackData = try await extractOrGenerateSilence(from: data)
                        }
                        let compressedAudio = try await compressAudio(data: audioTrackData, fileName: "video_audio.m4a")
                        localPaths["audio"] = saveLocal(compressedAudio, name: "video_audio.m4a")
                    }
                    if let path = request.rawMediaThumbnailPath {
                        localPaths["mediaThumb"] = path
                    }
                } else {
                    if let path = request.rawMediaPath {
                        localPaths["media"] = path
                    }
                    if let path = request.rawMediaThumbnailPath {
                        localPaths["mediaThumb"] = path
                    }
                    // AI Summary audio
                    if let path = request.rawAudioPath, let data = readFile(path) {
                        let compressed = try await compressAudio(data: data, fileName: "ai_summary.m4a")
                        localPaths["audio"] = saveLocal(compressed, name: "ai_summary.m4a")
                    }
                }

            case .voice:
                if let path = request.rawAudioPath, let data = readFile(path) {
                    let compressed = try await compressAudio(data: data, fileName: "voice.m4a")
                    localPaths["audio"] = saveLocal(compressed, name: "voice.m4a")
                }

            case .canvas:
                // Embed widget OG image
                if let path = request.rawEmbedOgImagePath {
                    localPaths["embedOgImage"] = path
                }
                // File widget — store the file itself
                if let path = request.rawFilePath {
                    localPaths["file"] = path
                }
                // File widget — check if audio/video file
                let fileExt = ((request.fileName ?? "") as NSString).pathExtension.lowercased()
                let audioExts = Set(["mp3", "m4a", "wav", "aac", "flac", "ogg"])
                let videoExts = Set(["mp4", "mov", "m4v"])

                if audioExts.contains(fileExt), let path = request.rawFilePath, let data = readFile(path) {
                    let compressed = try await compressAudio(data: data, fileName: request.fileName ?? "audio.m4a")
                    localPaths["audio"] = saveLocal(compressed, name: "file_audio.m4a")
                } else if videoExts.contains(fileExt), let path = request.rawFilePath, let data = readFile(path) {
                    let audioData = try await extractOrGenerateSilence(from: data)
                    let compressed = try await compressAudio(data: audioData, fileName: "file_audio.m4a")
                    localPaths["audio"] = saveLocal(compressed, name: "file_audio.m4a")
                } else if let path = request.rawAudioPath, let data = readFile(path) {
                    // AI summary audio added in editor
                    let compressed = try await compressAudio(data: data, fileName: "ai_summary.m4a")
                    localPaths["audio"] = saveLocal(compressed, name: "ai_summary.m4a")
                }

            case .`import`:
                if request.mediaIsVideo {
                    // Video import — same pipeline as .media video
                    if let path = request.rawMediaPath, let data = readFile(path) {
                        let compressed = try await compressVideo(data: data)
                        localPaths["media"] = saveLocal(compressed, name: "media.mp4")
                        let audioTrackData = try await extractOrGenerateSilence(from: data)
                        let compressedAudio = try await compressAudio(data: audioTrackData, fileName: "video_audio.m4a")
                        localPaths["audio"] = saveLocal(compressedAudio, name: "video_audio.m4a")
                    }
                    if let path = request.rawMediaThumbnailPath {
                        localPaths["mediaThumb"] = path
                    }
                } else {
                    // Audio-only import — extract audio from MP4 container
                    if let path = request.rawMediaPath, let data = readFile(path) {
                        let audioData = try await extractOrGenerateSilence(from: data)
                        let compressed = try await compressAudio(data: audioData, fileName: "import_audio.m4a")
                        localPaths["audio"] = saveLocal(compressed, name: "import_audio.m4a")
                    }
                }
            }

            // 2. Generate searchable content (non-fatal)
            var searchContent: String?
            switch request.mixType {
            case .note:
                if let text = request.textContent, !text.isEmpty {
                    searchContent = ContentService.fromText(text)
                }
            case .media:
                if request.mediaIsVideo {
                    searchContent = ContentService.fromVideo()
                } else {
                    searchContent = ContentService.fromImage()
                }
            case .voice:
                if let audioPath = localPaths["audio"] {
                    let audioURL = fileManager.fileURL(for: audioPath)
                    searchContent = await ContentService.fromAudio(fileURL: audioURL)
                }
            case .canvas:
                // Check widgets for searchable content
                let widgets = request.widgets ?? []
                if let ew = widgets.first(where: { $0.type == .embed }) {
                    searchContent = ContentService.fromEmbed(og: ew.embedOg, url: ew.embedUrl ?? "")
                } else if let fw = widgets.first(where: { $0.type == .file }), let name = fw.fileName {
                    searchContent = ContentService.fromFile(name: name)
                }

            case .`import`:
                searchContent = ContentService.fromImport(sourceUrl: request.sourceUrl ?? "", title: request.title)
            }

            // 3. Create LocalMix with all processed local paths (on context queue)
            let paths = localPaths
            let widgetsData: Data? = {
                guard let widgets = request.widgets, !widgets.isEmpty else { return nil }
                return try? JSONEncoder().encode(widgets)
            }()

            try await context.perform {
                let local = LocalMix(mixId: mixId, type: request.mixType.rawValue, createdAt: request.createdAt, context: context)

                let trimmedTitle = (request.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedTitle.isEmpty {
                    local.title = trimmedTitle
                }

                local.textContent = request.textContent
                local.embedUrl = request.embedUrl
                local.searchContent = searchContent
                local.previewCropXDouble = request.previewCropX
                local.previewCropYDouble = request.previewCropY
                local.previewCropScaleDouble = request.previewCropScale
                local.gradientTop = request.gradientTop
                local.gradientBottom = request.gradientBottom
                local.mediaIsVideo = request.mediaIsVideo
                local.localScreenshotPath = request.screenshotPath
                local.screenshotBucket = request.screenshotBucket

                if let ogData = request.embedOgJson {
                    local.embedOgJson = ogData
                }

                local.localMediaPath = paths["media"] ?? paths["file"] ?? request.rawMediaPath
                local.localMediaThumbnailPath = paths["mediaThumb"] ?? request.rawMediaThumbnailPath
                local.localEmbedOgImagePath = paths["embedOgImage"] ?? request.rawEmbedOgImagePath
                local.localAudioPath = paths["audio"]
                local.fileName = request.fileName
                local.widgetsJson = widgetsData
                local.sourceUrl = request.sourceUrl

                // 4. Save LocalMixTag rows
                for tagId in request.selectedTagIds {
                    _ = LocalMixTag(mixId: request.mixId, tagId: tagId, context: context)
                }

                try context.save()
            }

        } catch {
            // Creation failed — clean up mix directory
            let dirURL = fileManager.fileURL(for: mixDir)
            try? FileManager.default.removeItem(at: dirURL)
        }
    }

    // MARK: - Helpers

    private func readFile(_ relativePath: String) -> Data? {
        let url = fileManager.fileURL(for: relativePath)
        return try? Data(contentsOf: url)
    }

    // MARK: - Media Compression

    private func compressVideo(data: Data) async throws -> Data {
        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_compressed.mp4")
        try data.write(to: inputURL)

        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        let asset = AVURLAsset(url: inputURL)
        let duration = try await asset.load(.duration).seconds

        let preset: String
        if duration <= 60 {
            preset = AVAssetExportPresetMediumQuality
        } else {
            preset = AVAssetExportPresetLowQuality
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw CompressionError.exportFailed
        }

        session.outputURL = outputURL
        session.outputFileType = .mp4

        await session.export()

        guard session.status == .completed else {
            throw session.error ?? CompressionError.exportFailed
        }

        return try Data(contentsOf: outputURL)
    }

    private func compressAudio(data: Data, fileName: String) async throws -> Data {
        let ext = (fileName as NSString).pathExtension
        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_audio_in." + (ext.isEmpty ? "mp3" : ext))
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_audio_out.m4a")
        try data.write(to: inputURL)

        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        let asset = AVURLAsset(url: inputURL)
        let duration = try await asset.load(.duration).seconds

        let bitrate: Int
        if duration <= 300 {
            bitrate = 128_000
        } else {
            bitrate = 64_000
        }

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)

        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw CompressionError.noAudioTrack
        }

        let readerOutput = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        )
        reader.add(readerOutput)

        let writerInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVEncoderBitRateKey: bitrate,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44100,
            ]
        )
        writer.add(writerInput)

        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "audio.compress")) {
                while writerInput.isReadyForMoreMediaData {
                    if let buffer = readerOutput.copyNextSampleBuffer() {
                        writerInput.append(buffer)
                    } else {
                        writerInput.markAsFinished()
                        continuation.resume()
                        return
                    }
                }
            }
        }

        await writer.finishWriting()

        guard writer.status == .completed else {
            throw writer.error ?? CompressionError.exportFailed
        }

        return try Data(contentsOf: outputURL)
    }

    private func extractAudioFromVideo(data: Data) async throws -> Data {
        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_audio.m4a")
        try data.write(to: inputURL)

        let asset = AVURLAsset(url: inputURL)

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            try? FileManager.default.removeItem(at: inputURL)
            throw CompressionError.noAudioTrack
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            try? FileManager.default.removeItem(at: inputURL)
            throw CompressionError.exportFailed
        }
        session.outputURL = outputURL
        session.outputFileType = .m4a

        await session.export()

        try? FileManager.default.removeItem(at: inputURL)

        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: outputURL)
            throw session.error ?? CompressionError.exportFailed
        }

        let audioData = try Data(contentsOf: outputURL)
        try? FileManager.default.removeItem(at: outputURL)
        return audioData
    }

    private func extractOrGenerateSilence(from videoData: Data) async throws -> Data {
        do {
            return try await extractAudioFromVideo(data: videoData)
        } catch {
            let duration = try await videoDuration(from: videoData)
            return try generateSilence(duration: duration)
        }
    }

    private func videoDuration(from data: Data) async throws -> Double {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let asset = AVURLAsset(url: tempURL)
        let duration = try await asset.load(.duration)
        return duration.seconds
    }

    private func generateSilence(duration: TimeInterval) throws -> Data {
        let sampleRate: Double = 44100
        let channels: AVAudioChannelCount = 1
        let totalFrames = AVAudioFrameCount(sampleRate * max(duration, 0.1))

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels) else {
            throw CompressionError.exportFailed
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            throw CompressionError.exportFailed
        }
        buffer.frameLength = totalFrames

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_silence.m4a")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let file = try AVAudioFile(
            forWriting: outputURL,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: 32_000,
            ]
        )
        try file.write(from: buffer)

        return try Data(contentsOf: outputURL)
    }

    private enum CompressionError: LocalizedError {
        case exportFailed
        case noAudioTrack

        var errorDescription: String? {
            switch self {
            case .exportFailed: return "Failed to compress media"
            case .noAudioTrack: return "No audio track found"
            }
        }
    }
}
