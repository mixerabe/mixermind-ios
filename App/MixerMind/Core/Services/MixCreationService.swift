import Foundation
import SwiftData
import AVFoundation
import UIKit

extension Notification.Name {
    static let mixCreationStatusChanged = Notification.Name("mixCreationStatusChanged")
}

/// In-memory media blob passed from Phase 1 → Phase 2.
/// Avoids writing large video data to disk synchronously during create.
/// Only used for initial enqueue; retry reads from disk.
struct MixCreationMedia {
    var photoData: Data?
    var videoData: Data?
    var audioData: Data?
    var importMediaData: Data?
    var importAudioData: Data?
    var embedOgImageData: Data?
    var photoThumbnailData: Data?
    var videoThumbnailData: Data?
    var importThumbnailData: Data?
}

@Observable @MainActor
final class MixCreationService {
    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    private let fileManager = LocalFileManager.shared

    // MARK: - Enqueue (Phase 1 result → Phase 2 background)

    func enqueue(request: MixCreationRequest, media: MixCreationMedia, modelContext: ModelContext) {
        // 1. Create LocalMix with creation status
        let local = LocalMix(mixId: request.mixId, type: request.mixType.rawValue, createdAt: request.createdAt)
        local.creationStatus = "creating"
        local.title = request.title
        local.textContent = request.textContent
        local.importSourceUrl = request.importSourceUrl
        local.remoteEmbedUrl = request.embedUrl
        local.localScreenshotPath = request.screenshotPath
        local.previewScaleY = request.previewScaleY
        local.gradientTop = request.gradientTop
        local.gradientBottom = request.gradientBottom

        if let ogData = request.embedOgJson {
            local.remoteEmbedOgJson = ogData
        }

        // Set local media paths from Phase 1 raw files (for screenshot display)
        local.localPhotoPath = request.rawPhotoPath
        local.localPhotoThumbnailPath = request.rawPhotoThumbnailPath
        local.localVideoThumbnailPath = request.rawVideoThumbnailPath
        local.localImportThumbnailPath = request.rawImportThumbnailPath
        local.localEmbedOgImagePath = request.rawEmbedOgImagePath

        // 2. Persist request JSON to disk (lightweight — only paths & metadata)
        let requestPath = "\(request.mixId.uuidString)/request.json"
        let requestURL = fileManager.fileURL(for: requestPath)
        if let data = try? JSONEncoder().encode(request) {
            try? data.write(to: requestURL)
        }
        local.creationRequestPath = requestPath

        // 3. Save LocalMix
        modelContext.insert(local)

        // 4. Save LocalMixTag rows
        for tagId in request.selectedTagIds {
            modelContext.insert(LocalMixTag(mixId: request.mixId, tagId: tagId))
        }

        try? modelContext.save()

        // 5. Kick off background processing with in-memory media
        spawnBackgroundTask(for: request, media: media, modelContext: modelContext)
    }

    // MARK: - Retry

    func retry(mixId: UUID, modelContext: ModelContext) {
        // Read persisted request from disk
        guard let local = fetchLocalMix(mixId: mixId, modelContext: modelContext),
              let requestPath = local.creationRequestPath else { return }

        let requestURL = fileManager.fileURL(for: requestPath)
        guard let data = try? Data(contentsOf: requestURL),
              let request = try? JSONDecoder().decode(MixCreationRequest.self, from: data) else { return }

        local.creationStatus = "creating"
        try? modelContext.save()
        NotificationCenter.default.post(name: .mixCreationStatusChanged, object: nil)

        spawnBackgroundTask(for: request, media: nil, modelContext: modelContext)
    }

    // MARK: - Discard

    func discard(mixId: UUID, modelContext: ModelContext) {
        // Cancel active task
        activeTasks[mixId]?.cancel()
        activeTasks[mixId] = nil

        // Delete LocalMix
        if let local = fetchLocalMix(mixId: mixId, modelContext: modelContext) {
            modelContext.delete(local)
        }

        // Delete LocalMixTag rows
        if let rows = try? modelContext.fetch(FetchDescriptor<LocalMixTag>()) {
            for row in rows where row.mixId == mixId {
                modelContext.delete(row)
            }
        }

        try? modelContext.save()

        // Delete local files for this mix
        let dirURL = fileManager.fileURL(for: mixId.uuidString)
        try? FileManager.default.removeItem(at: dirURL)

        // Fire-and-forget: try deleting from Supabase if a row was partially created
        let repo: MixRepository = resolve()
        Task { try? await repo.deleteMix(id: mixId) }

        NotificationCenter.default.post(name: .mixCreationStatusChanged, object: nil)
    }

    // MARK: - Resume Incomplete (app launch)

    func resumeIncomplete(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<LocalMix>()
        guard let locals = try? modelContext.fetch(descriptor) else { return }

        for local in locals where local.creationStatus == "creating" {
            guard let requestPath = local.creationRequestPath else {
                local.creationStatus = "failed"
                continue
            }

            let requestURL = fileManager.fileURL(for: requestPath)
            guard let data = try? Data(contentsOf: requestURL),
                  let request = try? JSONDecoder().decode(MixCreationRequest.self, from: data) else {
                local.creationStatus = "failed"
                continue
            }

            spawnBackgroundTask(for: request, media: nil, modelContext: modelContext)
        }

        try? modelContext.save()
    }

    // MARK: - Background Processing (Phase 2)

    private func spawnBackgroundTask(for request: MixCreationRequest, media: MixCreationMedia?, modelContext: ModelContext) {
        let task = Task {
            // Write raw media to disk in the background (for app-kill recovery)
            var updatedRequest = request
            if let media {
                self.persistRawMedia(request: &updatedRequest, media: media)
            }
            await self.process(request: updatedRequest, modelContext: modelContext)
        }
        activeTasks[request.mixId] = task
    }

    /// Write raw media blobs to disk in the background so app-kill recovery works.
    /// Updates request paths in-place.
    private func persistRawMedia(request: inout MixCreationRequest, media: MixCreationMedia) {
        let mixDir = request.mixId.uuidString
        let dirURL = fileManager.fileURL(for: mixDir)
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        func writeIfNeeded(_ data: Data?, name: String, existingPath: String?) -> String? {
            if existingPath != nil { return existingPath } // already on disk
            guard let data else { return nil }
            let path = "\(mixDir)/\(name)"
            let url = fileManager.fileURL(for: path)
            do { try data.write(to: url); return path } catch { return nil }
        }

        request.rawPhotoPath = writeIfNeeded(media.photoData, name: "raw_photo.jpg", existingPath: request.rawPhotoPath)
        request.rawVideoPath = writeIfNeeded(media.videoData, name: "raw_video.mp4", existingPath: request.rawVideoPath)
        request.rawAudioPath = writeIfNeeded(media.audioData, name: "raw_audio.\(request.isAudioFromTTS ? "mp3" : "m4a")", existingPath: request.rawAudioPath)
        request.rawImportMediaPath = writeIfNeeded(media.importMediaData, name: "raw_import_media.mp4", existingPath: request.rawImportMediaPath)
        request.rawImportAudioPath = writeIfNeeded(media.importAudioData, name: "raw_import_audio.m4a", existingPath: request.rawImportAudioPath)
        request.rawEmbedOgImagePath = writeIfNeeded(media.embedOgImageData, name: "embed_og.jpg", existingPath: request.rawEmbedOgImagePath)
        request.rawPhotoThumbnailPath = writeIfNeeded(media.photoThumbnailData, name: "photo_thumb.jpg", existingPath: request.rawPhotoThumbnailPath)
        request.rawVideoThumbnailPath = writeIfNeeded(media.videoThumbnailData, name: "video_thumb.jpg", existingPath: request.rawVideoThumbnailPath)
        request.rawImportThumbnailPath = writeIfNeeded(media.importThumbnailData, name: "import_thumb.jpg", existingPath: request.rawImportThumbnailPath)

        // Re-persist updated request.json with new paths
        let requestPath = "\(mixDir)/request.json"
        let requestURL = fileManager.fileURL(for: requestPath)
        if let data = try? JSONEncoder().encode(request) {
            try? data.write(to: requestURL)
        }
    }

    private func process(request: MixCreationRequest, modelContext: ModelContext) async {
        let repo: MixRepository = resolve()
        let tagRepo: TagRepository = resolve()
        let mixId = request.mixId
        let mixDir = mixId.uuidString

        // Helper: save compressed data to local MixMedia path for immediate playback
        func saveLocal(_ data: Data, name: String) -> String {
            let path = "\(mixDir)/\(name)"
            let url = fileManager.fileURL(for: path)
            try? data.write(to: url)
            return path
        }

        // Track local paths of processed files for step 7
        var localPaths: [String: String] = [:]

        do {
            var payload = CreateMixPayload(type: request.mixType)

            // 1. Compress & upload media (save compressed files locally too)
            switch request.mixType {
            case .text:
                payload.textContent = request.textContent
                if let text = request.textContent, !text.isEmpty {
                    let ttsData = try await TextToSpeechService.synthesize(text: text)
                    let ttsUrl = try await repo.uploadMedia(data: ttsData, fileName: "tts.mp3", contentType: "audio/mpeg")
                    payload.ttsAudioUrl = ttsUrl
                    localPaths["ttsAudio"] = saveLocal(ttsData, name: "tts.mp3")
                }

            case .photo:
                if let path = request.rawPhotoPath, let data = readFile(path) {
                    let url = try await repo.uploadMedia(data: data, fileName: "image.jpg", contentType: "image/jpeg")
                    payload.photoUrl = url
                    localPaths["photo"] = path // raw is fine for photos
                }
                if let path = request.rawPhotoThumbnailPath, let data = readFile(path) {
                    let url = try await repo.uploadMedia(data: data, fileName: "photo_thumb.jpg", contentType: "image/jpeg")
                    payload.photoThumbnailUrl = url
                    localPaths["photoThumb"] = path
                }

            case .video:
                if let path = request.rawVideoPath, let data = readFile(path) {
                    let compressed = try await compressVideo(data: data)
                    let url = try await repo.uploadMedia(data: compressed, fileName: "video.mp4", contentType: "video/mp4")
                    payload.videoUrl = url
                    localPaths["video"] = saveLocal(compressed, name: "video.mp4")
                    // Extract audio track (or generate silence for muted videos)
                    let audioTrackData = try await extractOrGenerateSilence(from: data)
                    let compressedAudio = try await compressAudio(data: audioTrackData, fileName: "video_audio.m4a")
                    let audioUrl = try await repo.uploadMedia(data: compressedAudio, fileName: "video_audio.m4a", contentType: "audio/aac")
                    payload.audioUrl = audioUrl
                    localPaths["audio"] = saveLocal(compressedAudio, name: "video_audio.m4a")
                }
                if let path = request.rawVideoThumbnailPath, let data = readFile(path) {
                    let url = try await repo.uploadMedia(data: data, fileName: "video_thumb.jpg", contentType: "image/jpeg")
                    payload.videoThumbnailUrl = url
                    localPaths["videoThumb"] = path
                }

            case .import:
                payload.importSourceUrl = request.importSourceUrl
                var importAudioData: Data?

                if let path = request.rawImportMediaPath, let data = readFile(path) {
                    let compressed = try await compressVideo(data: data)
                    let url = try await repo.uploadMedia(data: compressed, fileName: "import_video.mp4", contentType: "video/mp4")
                    payload.importMediaUrl = url
                    localPaths["importMedia"] = saveLocal(compressed, name: "import_video.mp4")
                    // If no separate audio was provided, extract from the video
                    if request.rawImportAudioPath == nil {
                        importAudioData = try await extractOrGenerateSilence(from: data)
                    }
                }
                if let path = request.rawImportThumbnailPath, let data = readFile(path) {
                    let url = try await repo.uploadMedia(data: data, fileName: "import_thumb.jpg", contentType: "image/jpeg")
                    payload.importThumbnailUrl = url
                    localPaths["importThumb"] = path
                }
                if let path = request.rawImportAudioPath, let data = readFile(path) {
                    importAudioData = data
                }
                if var audioData = importAudioData {
                    audioData = try await compressAudio(data: audioData, fileName: "import_audio.m4a")
                    let url = try await repo.uploadMedia(data: audioData, fileName: "import_audio.m4a", contentType: "audio/aac")
                    payload.importAudioUrl = url
                    localPaths["importAudio"] = saveLocal(audioData, name: "import_audio.m4a")
                }

            case .embed:
                payload.embedUrl = request.embedUrl
                let ogMeta: OGMetadata? = {
                    guard let data = request.embedOgJson else { return nil }
                    return try? JSONDecoder().decode(OGMetadata.self, from: data)
                }()
                if let path = request.rawEmbedOgImagePath, let imageData = readFile(path) {
                    let imageUrl = try await repo.uploadMedia(data: imageData, fileName: "embed_og.jpg", contentType: "image/jpeg")
                    payload.embedOg = OGMetadata(
                        title: ogMeta?.title,
                        description: ogMeta?.description,
                        imageUrl: imageUrl,
                        host: ogMeta?.host ?? ""
                    )
                    localPaths["embedOgImage"] = path
                } else {
                    payload.embedOg = OGMetadata(
                        title: ogMeta?.title,
                        description: ogMeta?.description,
                        imageUrl: nil,
                        host: ogMeta?.host ?? ""
                    )
                }

            case .audio:
                if let path = request.rawAudioPath, var data = readFile(path) {
                    if request.isAudioFromTTS {
                        let url = try await repo.uploadMedia(data: data, fileName: "audio.mp3", contentType: "audio/mpeg")
                        payload.audioUrl = url
                        localPaths["audio"] = path
                    } else {
                        data = try await compressAudio(data: data, fileName: request.audioFileName ?? "audio.m4a")
                        let url = try await repo.uploadMedia(data: data, fileName: "audio.m4a", contentType: "audio/aac")
                        payload.audioUrl = url
                        localPaths["audio"] = saveLocal(data, name: "audio.m4a")
                    }
                }
            }

            try Task.checkCancellation()

            // 2. Generate searchable content (non-fatal)
            do {
                switch request.mixType {
                case .text:
                    if let text = request.textContent, !text.isEmpty {
                        payload.content = ContentService.fromText(text)
                    }
                case .photo:
                    if let path = request.rawPhotoPath, let data = readFile(path) {
                        payload.content = try await ContentService.fromImage(imageData: data)
                    }
                case .video:
                    if let path = request.rawVideoPath, let data = readFile(path) {
                        let audioTrack = try await extractAudioFromVideo(data: data)
                        payload.content = try await ContentService.fromAudio(data: audioTrack, fileName: "video_audio.m4a")
                    }
                case .import:
                    if let path = request.rawImportAudioPath, let data = readFile(path) {
                        payload.content = try await ContentService.fromAudio(data: data, fileName: "import_audio.m4a")
                    } else if let path = request.rawImportMediaPath, let data = readFile(path) {
                        let audioTrack = try await extractAudioFromVideo(data: data)
                        payload.content = try await ContentService.fromAudio(data: audioTrack, fileName: "import_audio.m4a")
                    }
                case .audio:
                    if let path = request.rawAudioPath, let data = readFile(path), !request.isAudioFromTTS {
                        let name = request.audioFileName ?? "audio.m4a"
                        let ct = name.hasSuffix(".mp3") ? "audio/mpeg" : "audio/m4a"
                        payload.content = try await ContentService.fromAudio(data: data, fileName: name, contentType: ct)
                    }
                case .embed:
                    let ogMeta: OGMetadata? = {
                        guard let data = request.embedOgJson else { return nil }
                        return try? JSONDecoder().decode(OGMetadata.self, from: data)
                    }()
                    payload.content = ContentService.fromEmbed(og: ogMeta, url: request.embedUrl ?? "")
                }
            } catch {}

            try Task.checkCancellation()

            // 3. Auto-generate title (non-fatal)
            let trimmedTitle = (request.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTitle.isEmpty {
                payload.title = trimmedTitle
            } else if request.autoCreateTitle {
                do {
                    let generated: String
                    switch request.mixType {
                    case .text:
                        if let text = request.textContent, !text.isEmpty {
                            generated = try await TitleService.fromText(text)
                        } else { generated = "" }
                    case .audio:
                        if let path = request.rawAudioPath, let data = readFile(path) {
                            let name = request.audioFileName ?? "audio.m4a"
                            let ct = name.hasSuffix(".mp3") ? "audio/mpeg" : "audio/m4a"
                            generated = try await TitleService.fromAudio(data: data, fileName: name, contentType: ct)
                        } else { generated = "" }
                    default:
                        generated = ""
                    }
                    if !generated.isEmpty { payload.title = generated }
                } catch {}
            }

            try Task.checkCancellation()

            // 4. Upload screenshot
            if let path = request.screenshotPath, let screenshotData = readFile(path) {
                let screenshotUrl = try await repo.uploadMedia(data: screenshotData, fileName: "screenshot.jpg", contentType: "image/jpeg")
                payload.screenshotUrl = screenshotUrl
            }
            payload.previewScaleY = request.previewScaleY
            payload.gradientTop = request.gradientTop
            payload.gradientBottom = request.gradientBottom

            // 5. Insert into Supabase
            let createdMix = try await repo.createMix(payload)

            // 6. Set tags
            let tagIds = Set(request.selectedTagIds)
            if !tagIds.isEmpty {
                try? await tagRepo.setTagsForMix(mixId: createdMix.id, tagIds: tagIds)
            }

            try Task.checkCancellation()

            // 7. Update LocalMix — set remote URLs AND set local paths to compressed files
            //    so the mix is immediately playable without waiting for SyncEngine.
            if let local = fetchLocalMix(mixId: mixId, modelContext: modelContext) {
                local.updateFromRemote(createdMix)

                // Set local paths to compressed/processed files saved during step 1
                switch request.mixType {
                case .text:
                    local.localTtsAudioPath = localPaths["ttsAudio"]
                case .photo:
                    local.localPhotoPath = localPaths["photo"]
                    local.localPhotoThumbnailPath = localPaths["photoThumb"]
                case .video:
                    local.localVideoPath = localPaths["video"]
                    local.localVideoThumbnailPath = localPaths["videoThumb"]
                    local.localAudioPath = localPaths["audio"]
                case .import:
                    local.localImportMediaPath = localPaths["importMedia"]
                    local.localImportThumbnailPath = localPaths["importThumb"]
                    local.localImportAudioPath = localPaths["importAudio"]
                case .embed:
                    local.localEmbedOgImagePath = localPaths["embedOgImage"]
                case .audio:
                    local.localAudioPath = localPaths["audio"]
                }
                local.localScreenshotPath = request.screenshotPath

                // Verify local files actually exist before marking as done.
                // If any required file is missing, stay in "creating" state so the
                // card remains non-tappable and SyncEngine will download on next sync.
                let allLocalFilesExist = verifyLocalFiles(local: local, mixType: request.mixType)
                if allLocalFilesExist {
                    local.creationStatus = nil
                    local.creationRequestPath = nil
                    local.isSynced = true
                } else {
                    // Files were supposedly saved but don't exist — mark failed so user can retry
                    local.creationStatus = "failed"
                }
                try? modelContext.save()
            }

            // 8. Clean up request.json
            let requestPath = "\(mixId.uuidString)/request.json"
            let requestURL = fileManager.fileURL(for: requestPath)
            try? FileManager.default.removeItem(at: requestURL)

            activeTasks[mixId] = nil
            NotificationCenter.default.post(name: .mixCreationStatusChanged, object: nil)

        } catch is CancellationError {
            // Task was cancelled (user discarded) — do nothing
            activeTasks[mixId] = nil
        } catch {
            // Mark as failed
            if let local = fetchLocalMix(mixId: mixId, modelContext: modelContext) {
                local.creationStatus = "failed"
                try? modelContext.save()
            }
            activeTasks[mixId] = nil
            NotificationCenter.default.post(name: .mixCreationStatusChanged, object: nil)
        }
    }

    // MARK: - Helpers

    /// Check that all required local media files actually exist on disk.
    private func verifyLocalFiles(local: LocalMix, mixType: MixType) -> Bool {
        func exists(_ path: String?) -> Bool {
            guard let path else { return false }
            return fileManager.fileExists(at: path)
        }
        func optionalExists(_ path: String?, remote: String?) -> Bool {
            // If there's no remote URL, the file is optional (e.g. no TTS for empty text)
            guard remote != nil else { return true }
            return exists(path)
        }

        let screenshotOk = exists(local.localScreenshotPath)

        switch mixType {
        case .text:
            return exists(local.localTtsAudioPath) && screenshotOk
        case .photo:
            return exists(local.localPhotoPath) && screenshotOk
        case .video:
            return exists(local.localVideoPath) && exists(local.localAudioPath) && screenshotOk
        case .import:
            // Audio-only imports have no video file — just need audio
            let hasMedia = exists(local.localImportMediaPath) || exists(local.localImportAudioPath)
            return hasMedia && screenshotOk
        case .embed:
            return screenshotOk
        case .audio:
            return exists(local.localAudioPath) && screenshotOk
        }
    }

    private func fetchLocalMix(mixId: UUID, modelContext: ModelContext) -> LocalMix? {
        try? modelContext.fetch(FetchDescriptor<LocalMix>()).first(where: { $0.mixId == mixId })
    }

    private func readFile(_ relativePath: String) -> Data? {
        let url = fileManager.fileURL(for: relativePath)
        return try? Data(contentsOf: url)
    }

    // MARK: - Media Compression (moved from CreateMixViewModel)

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
