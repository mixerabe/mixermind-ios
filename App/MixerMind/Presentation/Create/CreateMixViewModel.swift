import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

@Observable @MainActor
final class CreateMixViewModel {
    var mixType: MixType = .text

    var textContent: String = ""

    // Photo state
    var photoData: Data?
    var photoThumbnail: UIImage?

    // Video state
    var videoData: Data?
    var videoThumbnail: UIImage?

    // Import state
    var importSourceUrl: String?
    var importMediaData: Data?
    var importAudioData: Data?
    var importThumbnail: UIImage?

    // Audio state
    var audioData: Data?
    var audioFileName: String?
    var isAudioFromTTS = false

    // Embed state
    var embedUrl: String = ""
    var embedOg: OGMetadata?
    var embedOgImageData: Data?
    var isFetchingOG = false
    var hasEmbed: Bool { !embedUrl.isEmpty }

    // Sheet toggles
    var isShowingTextSheet = false
    var isShowingPhotoPicker = false
    var isShowingRecordAudio = false
    var isShowingURLImport = false
    var isShowingTagSheet = false
    var isShowingEmbedSheet = false

    // MARK: - Tags

    var selectedTagIds: Set<UUID> = []
    private var selectedTagOrder: [UUID] = []
    var allTags: [Tag] = []
    private var mixTagMap: [UUID: Set<UUID>] = [:]

    var selectedTagsOrdered: [Tag] {
        let lookup = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0) })
        return selectedTagOrder.compactMap { lookup[$0] }
    }

    var unselectedTagsByFrequency: [Tag] {
        var counts: [UUID: Int] = [:]
        for tagIds in mixTagMap.values {
            for tagId in tagIds { counts[tagId, default: 0] += 1 }
        }
        return allTags
            .filter { !selectedTagIds.contains($0.id) }
            .sorted {
                let a = counts[$0.id] ?? 0
                let b = counts[$1.id] ?? 0
                return a != b ? a > b : $0.name < $1.name
            }
    }

    var isGeneratingTTS = false

    // Title
    var title: String = ""

    // MARK: - Edit Mode

    private var editingMixId: UUID?
    var isEditing: Bool { editingMixId != nil }

    var isCreating = false
    var errorMessage: String?

    var selectedPhotoItem: PhotosPickerItem? {
        didSet { loadPhoto() }
    }

    var hasText: Bool { !textContent.isEmpty }
    var hasUnsavedContent: Bool { mixType != .text || hasText }

    private let repo: MixRepository = resolve()
    private let tagRepo: TagRepository = resolve()
    var modelContext: ModelContext?

    init() {}

    init(editing mix: Mix, skipPlayback: Bool = false) {
        self.editingMixId = mix.id
        self.mixType = mix.type
        self.textContent = mix.textContent ?? ""
        self.embedUrl = mix.embedUrl ?? ""
        self.embedOg = mix.embedOg

        if !skipPlayback {
            loadExistingContent(mix: mix)
        }
    }

    // MARK: - Edit Mode Loaders

    private func loadExistingContent(mix: Mix) {
        switch mix.type {
        case .video:
            if let urlString = mix.videoUrl, let url = URL(string: urlString) {
                loadExistingVideo(from: url)
            }
        case .photo:
            if let urlString = mix.photoUrl, let url = URL(string: urlString) {
                loadExistingImage(from: url)
            }
        case .audio:
            if let urlString = mix.audioUrl, let url = URL(string: urlString) {
                loadExistingAudio(from: url)
            }
        case .import:
            if let urlString = mix.importMediaUrl, let url = URL(string: urlString) {
                loadExistingVideo(from: url)
            }
            if let urlString = mix.importAudioUrl, let url = URL(string: urlString) {
                loadExistingAudio(from: url)
            }
        case .text:
            if let urlString = mix.ttsAudioUrl, let url = URL(string: urlString) {
                loadExistingAudio(from: url)
            }
        case .embed:
            break
        }
    }

    private func loadExistingVideo(from url: URL) {
        Task {
            guard let data = try? await URLSession.shared.data(from: url).0 else { return }
            self.videoData = data
            self.generateVideoThumbnail(from: data)
        }
    }

    private func loadExistingImage(from url: URL) {
        Task {
            guard let data = try? await URLSession.shared.data(from: url).0 else { return }
            self.photoData = data
            self.photoThumbnail = UIImage(data: data)
        }
    }

    private func loadExistingAudio(from url: URL) {
        Task {
            guard let data = try? await URLSession.shared.data(from: url).0 else { return }
            self.audioData = data
        }
    }

    // MARK: - Photo/Video Loading

    private func loadPhoto() {
        guard let item = selectedPhotoItem else { return }

        Task {
            do {
                if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                    if let data = try await item.loadTransferable(type: Data.self) {
                        let duration = try await videoDuration(from: data)
                        if duration > 600 {
                            self.errorMessage = "Video is too long (max 10 minutes)"
                            self.selectedPhotoItem = nil
                            return
                        }
                        self.mixType = .video
                        self.videoData = data
                        self.generateVideoThumbnail(from: data)
                        return
                    }
                }

                if let data = try await item.loadTransferable(type: Data.self) {
                    self.mixType = .photo
                    self.photoData = data
                    self.photoThumbnail = UIImage(data: data)
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
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

    // MARK: - Video Thumbnail

    private func generateVideoThumbnail(from data: Data) {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")
        do {
            try data.write(to: tempURL)
        } catch { return }

        let asset = AVURLAsset(url: tempURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0, preferredTimescale: 600)
        Task {
            defer { try? FileManager.default.removeItem(at: tempURL) }
            do {
                let (cgImage, _) = try await generator.image(at: time)
                self.videoThumbnail = UIImage(cgImage: cgImage)
            } catch {}
        }
    }

    /// Awaitable version — ensures thumbnail is ready before returning.
    private func ensureVideoThumbnail(from data: Data) async {
        guard videoThumbnail == nil else { return }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")
        do {
            try data.write(to: tempURL)
        } catch { return }
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let asset = AVURLAsset(url: tempURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0, preferredTimescale: 600)
        do {
            let (cgImage, _) = try await generator.image(at: time)
            self.videoThumbnail = UIImage(cgImage: cgImage)
        } catch {}
    }

    // MARK: - Audio File Loading & Playback

    func handleAudioResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                handleAudioFile(url: url)
            }
        case .failure:
            errorMessage = "Failed to pick audio file"
        }
    }

    func handleAudioFile(url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            errorMessage = "Failed to read audio file"
            return
        }

        if let player = try? AVAudioPlayer(data: data) {
            if player.duration > 1500 {
                errorMessage = "Audio is too long (max 25 minutes)"
                return
            }
        }

        mixType = .audio
        audioData = data
        audioFileName = url.lastPathComponent
        isAudioFromTTS = false
    }

    // MARK: - Recorded Audio

    func setRecordedAudio(data: Data, fileName: String) {
        if let player = try? AVAudioPlayer(data: data) {
            if player.duration > 1500 {
                errorMessage = "Recording is too long (max 25 minutes)"
                return
            }
        }

        mixType = .audio
        audioData = data
        audioFileName = fileName
        isAudioFromTTS = false
    }


    // MARK: - Import from URL

    enum ImportMode { case video, audio }

    var isImportingURL = false
    var importProgress: String?

    func importFromURL(_ urlString: String, mode: ImportMode) async {
        isImportingURL = true
        importProgress = "Fetching media info..."
        errorMessage = nil

        do {
            // Spotify URLs go through a dedicated download path (audio only)
            if MediaURLService.isSpotifyQuery(urlString) {
                try await importSpotify(query: urlString)
            } else {
                let result = try await MediaURLService.resolve(urlString)

                switch mode {
                case .video:
                    try await importVideo(from: result, sourceUrl: urlString)
                case .audio:
                    try await importAudio(from: result, sourceUrl: urlString)
                }
            }

            importProgress = nil
            isImportingURL = false
        } catch {
            importProgress = nil
            isImportingURL = false
            errorMessage = error.localizedDescription
        }
    }

    /// Import a Spotify track by URL — downloads MP3 via backend spotDL.
    func importSpotify(query: String) async throws {
        importProgress = "Downloading from Spotify..."
        let result = try await MediaURLService.downloadSpotify(query)

        self.mixType = .import
        self.importSourceUrl = query
        self.importAudioData = result.audioData
        self.audioFileName = result.artist.isEmpty ? result.title : "\(result.artist) - \(result.title)"
    }

    private func importVideo(from result: MediaURLService.Result, sourceUrl: String) async throws {
        importProgress = "Downloading video..."
        let videoData = try await MediaURLService.downloadMerged(result.originalURL)

        let duration = try await videoDuration(from: videoData)
        if duration > 600 {
            throw MediaURLService.MediaError.serverError("Video is too long (max 10 minutes)")
        }

        self.mixType = .import
        self.importSourceUrl = sourceUrl
        self.importMediaData = videoData
        self.generateVideoThumbnail(from: videoData)
    }

    private func importAudio(from result: MediaURLService.Result, sourceUrl: String) async throws {
        importProgress = "Downloading..."
        let videoData = try await MediaURLService.downloadMerged(result.originalURL)

        importProgress = "Extracting audio..."
        let audioData = try await extractAudioFromVideo(data: videoData)

        self.mixType = .import
        self.importSourceUrl = sourceUrl
        self.importAudioData = audioData
        self.audioFileName = result.title ?? "Imported audio"
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
            throw MediaURLService.MediaError.serverError("No audio track found in video")
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            try? FileManager.default.removeItem(at: inputURL)
            throw MediaURLService.MediaError.serverError("Failed to create audio export session")
        }
        session.outputURL = outputURL
        session.outputFileType = .m4a

        await session.export()

        try? FileManager.default.removeItem(at: inputURL)

        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: outputURL)
            let errorMsg = session.error?.localizedDescription ?? "status: \(session.status.rawValue)"
            throw MediaURLService.MediaError.serverError("Audio extraction failed: \(errorMsg)")
        }

        let audioData = try Data(contentsOf: outputURL)
        try? FileManager.default.removeItem(at: outputURL)
        return audioData
    }

    // MARK: - Tag Management

    func loadTags() {
        guard let modelContext else { return }
        do {
            let localTags = try modelContext.fetch(FetchDescriptor<LocalTag>())
            allTags = localTags.map { $0.toTag() }

            let localMixTags = try modelContext.fetch(FetchDescriptor<LocalMixTag>())
            var map: [UUID: Set<UUID>] = [:]
            for row in localMixTags { map[row.mixId, default: []].insert(row.tagId) }
            mixTagMap = map
        } catch {}
    }

    func loadExistingTags() {
        guard let modelContext, let mixId = editingMixId else { return }
        do {
            let localMixTags = try modelContext.fetch(FetchDescriptor<LocalMixTag>())
            let ids = localMixTags.filter { $0.mixId == mixId }.map(\.tagId)
            selectedTagIds = Set(ids)
            selectedTagOrder = ids
        } catch {}
    }

    func toggleTag(_ tagId: UUID) {
        if selectedTagIds.contains(tagId) {
            selectedTagIds.remove(tagId)
            selectedTagOrder.removeAll { $0 == tagId }
        } else {
            selectedTagIds.insert(tagId)
            selectedTagOrder.append(tagId)
        }
    }

    func createNewTag(name: String) async -> Tag? {
        let sanitized = name
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()

        guard !sanitized.isEmpty else { return nil }

        if allTags.contains(where: { $0.name.lowercased() == sanitized }) {
            return nil
        }

        // Optimistic local create
        let tagId = UUID()
        let now = Date()
        let tag = Tag(id: tagId, name: sanitized, createdAt: now)

        if let modelContext {
            modelContext.insert(LocalTag(tagId: tagId, name: sanitized, createdAt: now))
            try? modelContext.save()
        }

        allTags.append(tag)
        selectedTagIds.insert(tag.id)

        // Fire-and-forget Supabase call
        Task {
            if let remoteTag = try? await tagRepo.createTag(name: sanitized) {
                if remoteTag.id != tagId, let modelContext {
                    await MainActor.run {
                        if let local = try? modelContext.fetch(FetchDescriptor<LocalTag>()).first(where: { $0.tagId == tagId }) {
                            local.tagId = remoteTag.id
                        }
                        if let rows = try? modelContext.fetch(FetchDescriptor<LocalMixTag>()) {
                            for row in rows where row.tagId == tagId {
                                row.tagId = remoteTag.id
                            }
                        }
                        try? modelContext.save()
                    }
                }
            }
        }

        return tag
    }

    func renameTag(id: UUID, newName: String) async {
        let sanitized = newName
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()

        guard !sanitized.isEmpty else { return }

        // Optimistic local rename
        if let modelContext,
           let local = try? modelContext.fetch(FetchDescriptor<LocalTag>()).first(where: { $0.tagId == id }) {
            local.name = sanitized
            try? modelContext.save()
        }
        if let index = allTags.firstIndex(where: { $0.id == id }) {
            allTags[index] = Tag(id: id, name: sanitized, createdAt: allTags[index].createdAt)
        }

        // Fire-and-forget Supabase call
        Task { _ = try? await tagRepo.updateTag(id: id, name: sanitized) }
    }

    func deleteTag(id: UUID) async {
        // Optimistic local delete
        if let modelContext {
            if let local = try? modelContext.fetch(FetchDescriptor<LocalTag>()).first(where: { $0.tagId == id }) {
                modelContext.delete(local)
            }
            // Delete mix_tag relationships for this tag
            if let rows = try? modelContext.fetch(FetchDescriptor<LocalMixTag>()) {
                for row in rows where row.tagId == id {
                    modelContext.delete(row)
                }
            }
            try? modelContext.save()
        }

        allTags.removeAll { $0.id == id }
        selectedTagIds.remove(id)

        // Fire-and-forget Supabase call
        Task { try? await tagRepo.deleteTag(id: id) }
    }

    // MARK: - Embed URL

    func setEmbedUrl(_ urlString: String) async {
        var normalized = urlString
        if !normalized.hasPrefix("http://") && !normalized.hasPrefix("https://") {
            normalized = "https://\(normalized)"
        }
        mixType = .embed
        embedUrl = normalized
        embedOg = nil
        embedOgImageData = nil
        isFetchingOG = true
        do {
            embedOg = try await OpenGraphService.fetch(normalized)
        } catch {
            embedOg = OGMetadata(title: nil, description: nil, imageUrl: nil, host: URL(string: normalized)?.host ?? normalized)
        }

        // Download OG image immediately so we own a local copy
        if let imageUrlString = embedOg?.imageUrl,
           let imageUrl = URL(string: imageUrlString) {
            do {
                let (data, _) = try await URLSession.shared.data(from: imageUrl)
                embedOgImageData = data
            } catch {
                // Image download failed — continue without image
            }
        }

        isFetchingOG = false
    }

    // MARK: - Clear

    func clearAll() {
        textContent = ""
        embedUrl = ""
        embedOg = nil
        embedOgImageData = nil
        photoData = nil
        photoThumbnail = nil
        videoData = nil
        videoThumbnail = nil
        importSourceUrl = nil
        importMediaData = nil
        importAudioData = nil
        importThumbnail = nil
        audioData = nil
        audioFileName = nil
        isAudioFromTTS = false
        selectedPhotoItem = nil
        mixType = .text
    }

    // MARK: - Media Compression (used by performUpdate)

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

    private func compressAudio(data: Data) async throws -> Data {
        let ext = (audioFileName as? NSString)?.pathExtension ?? "mp3"
        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_audio_in." + ext)
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

    private func extractOrGenerateSilence(from videoData: Data) async throws -> Data {
        do {
            return try await extractAudioFromVideo(data: videoData)
        } catch {
            let duration = try await videoDuration(from: videoData)
            return try generateSilence(duration: duration)
        }
    }

    // MARK: - Save (Create or Update)

    func saveMix() async -> Bool {
        if isEditing {
            return await performUpdate()
        } else {
            return await performCreate()
        }
    }

    private func performCreate() async -> Bool {
        guard let modelContext else {
            errorMessage = "Internal error: no model context"
            return false
        }

        let localFileManager = LocalFileManager.shared
        let mixId = UUID()
        let mixDir = mixId.uuidString

        // Ensure mix directory exists
        let dirURL = localFileManager.fileURL(for: mixDir)
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        var request = MixCreationRequest(
            mixId: mixId,
            mixType: mixType,
            createdAt: Date(),
            textContent: hasText ? textContent : nil,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : title.trimmingCharacters(in: .whitespacesAndNewlines),
            selectedTagIds: Array(selectedTagIds),
            embedUrl: hasEmbed ? embedUrl : nil,
            importSourceUrl: importSourceUrl,
            isAudioFromTTS: isAudioFromTTS,
            audioFileName: audioFileName
        )

        // Encode OG metadata if present
        if let og = embedOg {
            request.embedOgJson = try? JSONEncoder().encode(og)
        }

        // Helper: write small data to disk (thumbnails, screenshots only)
        func writeSmall(_ data: Data?, name: String) -> String? {
            guard let data else { return nil }
            let path = "\(mixDir)/\(name)"
            let url = localFileManager.fileURL(for: path)
            do { try data.write(to: url); return path } catch { return nil }
        }

        func makeThumbnailData(_ image: UIImage?) -> Data? {
            guard let image else { return nil }
            let targetWidth: CGFloat = 300
            let scale = targetWidth / image.size.width
            let targetSize = CGSize(width: targetWidth, height: image.size.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1.0
            let resized = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            return resized.jpegData(compressionQuality: 0.5)
        }

        // Ensure video thumbnail is ready (generateVideoThumbnail runs in a fire-and-forget Task)
        if mixType == .video, videoThumbnail == nil, let data = videoData {
            await ensureVideoThumbnail(from: data)
        } else if mixType == .import, videoThumbnail == nil, importThumbnail == nil, let data = importMediaData {
            await ensureVideoThumbnail(from: data)
        }

        // Build in-memory media blob — large files are NOT written to disk here.
        // MixCreationService writes them to disk in the background.
        var media = MixCreationMedia()

        switch mixType {
        case .text:
            break
        case .photo:
            media.photoData = photoData
            let thumbData = makeThumbnailData(photoThumbnail)
            media.photoThumbnailData = thumbData
            request.rawPhotoThumbnailPath = writeSmall(thumbData, name: "photo_thumb.jpg")
        case .video:
            media.videoData = videoData
            let thumbData = makeThumbnailData(videoThumbnail)
            media.videoThumbnailData = thumbData
            request.rawVideoThumbnailPath = writeSmall(thumbData, name: "video_thumb.jpg")
        case .import:
            media.importMediaData = importMediaData
            media.importAudioData = importAudioData
            let thumbData = makeThumbnailData(importThumbnail ?? videoThumbnail)
            media.importThumbnailData = thumbData
            request.rawImportThumbnailPath = writeSmall(thumbData, name: "import_thumb.jpg")
        case .embed:
            media.embedOgImageData = embedOgImageData
            request.rawEmbedOgImagePath = writeSmall(embedOgImageData, name: "embed_og.jpg")
        case .audio:
            media.audioData = audioData
        }

        // Capture screenshot locally (pure ImageRenderer, no network)
        // Audio-only imports (no video) render as .audio type for the screenshot
        let isAudioOnlyImport = mixType == .import && importMediaData == nil
        let screenshotMixType = isAudioOnlyImport ? MixType.audio : mixType

        let thumbnail: UIImage? = switch mixType {
        case .photo: photoThumbnail
        case .video: videoThumbnail
        case .import: importThumbnail ?? videoThumbnail
        default: nil
        }
        let embedImg: UIImage? = if let data = embedOgImageData { UIImage(data: data) } else { nil }

        let gradients: (top: String, bottom: String)?
        if let thumb = thumbnail {
            gradients = ScreenshotService.extractGradients(from: thumb)
        } else {
            gradients = nil
        }
        request.gradientTop = gradients?.top
        request.gradientBottom = gradients?.bottom

        if let screenshot = ScreenshotService.capture(
            mixType: screenshotMixType,
            textContent: textContent,
            mediaThumbnail: thumbnail,
            embedUrl: hasEmbed ? embedUrl : nil,
            embedOg: embedOg,
            embedImage: embedImg,
            gradientTop: gradients?.top,
            gradientBottom: gradients?.bottom
        ), let jpegData = screenshot.jpegData(compressionQuality: 0.7) {
            request.screenshotPath = writeSmall(jpegData, name: "screenshot.jpg")

            request.previewScaleY = ScreenshotService.computeScaleY(
                mixType: screenshotMixType,
                textContent: textContent,
                mediaThumbnail: thumbnail,
                importHasVideo: importMediaData != nil,
                embedImage: embedImg,
                embedUrl: hasEmbed ? embedUrl : nil,
                embedOg: embedOg
            )
        }

        // Enqueue to MixCreationService (creates LocalMix, spawns background Task)
        let creationService: MixCreationService = resolve()
        creationService.enqueue(request: request, media: media, modelContext: modelContext)

        return true
    }

    private func performUpdate() async -> Bool {
        guard let mixId = editingMixId else { return false }
        isCreating = true
        errorMessage = nil

        do {
            var payload = UpdateMixPayload()

            switch mixType {
            case .text:
                payload.textContent = hasText ? textContent : nil
                if hasText {
                    isGeneratingTTS = true
                    do {
                        let ttsData = try await TextToSpeechService.synthesize(text: textContent)
                        let ttsUrl = try await repo.uploadMedia(data: ttsData, fileName: "tts.mp3", contentType: "audio/mpeg")
                        payload.ttsAudioUrl = ttsUrl
                    } catch {}
                    isGeneratingTTS = false
                }

            case .photo:
                if let data = photoData {
                    let url = try await repo.uploadMedia(data: data, fileName: "image.jpg", contentType: "image/jpeg")
                    payload.photoUrl = url
                }

            case .video:
                if let data = videoData {
                    let compressed = try await compressVideo(data: data)
                    let url = try await repo.uploadMedia(data: compressed, fileName: "video.mp4", contentType: "video/mp4")
                    payload.videoUrl = url
                    // Extract audio track (or generate silence for muted videos)
                    let audioTrackData = try await extractOrGenerateSilence(from: data)
                    let compressedAudio = try await compressAudio(data: audioTrackData)
                    let audioUrl = try await repo.uploadMedia(data: compressedAudio, fileName: "video_audio.m4a", contentType: "audio/aac")
                    payload.audioUrl = audioUrl
                }

            case .import:
                payload.importSourceUrl = importSourceUrl
                if let data = importMediaData {
                    let compressed = try await compressVideo(data: data)
                    let url = try await repo.uploadMedia(data: compressed, fileName: "import_video.mp4", contentType: "video/mp4")
                    payload.importMediaUrl = url
                    // If no separate audio was provided, extract from the video
                    if importAudioData == nil {
                        importAudioData = try await extractOrGenerateSilence(from: data)
                    }
                }
                if var data = importAudioData {
                    data = try await compressAudio(data: data)
                    let url = try await repo.uploadMedia(data: data, fileName: "import_audio.m4a", contentType: "audio/aac")
                    payload.importAudioUrl = url
                }

            case .embed:
                payload.embedUrl = embedUrl
                if let imageData = embedOgImageData {
                    let imageUrl = try await repo.uploadMedia(data: imageData, fileName: "embed_og.jpg", contentType: "image/jpeg")
                    payload.embedOg = OGMetadata(
                        title: embedOg?.title,
                        description: embedOg?.description,
                        imageUrl: imageUrl,
                        host: embedOg?.host ?? ""
                    )
                } else {
                    payload.embedOg = OGMetadata(
                        title: embedOg?.title,
                        description: embedOg?.description,
                        imageUrl: nil,
                        host: embedOg?.host ?? ""
                    )
                }

            case .audio:
                if var data = audioData {
                    if isAudioFromTTS {
                        let url = try await repo.uploadMedia(data: data, fileName: "audio.mp3", contentType: "audio/mpeg")
                        payload.audioUrl = url
                    } else {
                        data = try await compressAudio(data: data)
                        let url = try await repo.uploadMedia(data: data, fileName: "audio.m4a", contentType: "audio/aac")
                        payload.audioUrl = url
                    }
                }
            }

            // Regenerate searchable content (non-fatal)
            do {
                switch mixType {
                case .text:
                    if hasText {
                        payload.content = ContentService.fromText(textContent)
                    }
                case .photo:
                    if let data = photoData {
                        payload.content = try await ContentService.fromImage(imageData: data)
                    }
                case .video:
                    if let data = videoData {
                        let audioTrack = try await extractAudioFromVideo(data: data)
                        payload.content = try await ContentService.fromAudio(data: audioTrack, fileName: "video_audio.m4a")
                    }
                case .import:
                    if let data = importAudioData {
                        payload.content = try await ContentService.fromAudio(data: data, fileName: "import_audio.m4a")
                    } else if let data = importMediaData {
                        let audioTrack = try await extractAudioFromVideo(data: data)
                        payload.content = try await ContentService.fromAudio(data: audioTrack, fileName: "import_audio.m4a")
                    }
                case .audio:
                    if let data = audioData, !isAudioFromTTS {
                        let name = audioFileName ?? "audio.m4a"
                        let ct = name.hasSuffix(".mp3") ? "audio/mpeg" : "audio/m4a"
                        payload.content = try await ContentService.fromAudio(data: data, fileName: name, contentType: ct)
                    }
                case .embed:
                    payload.content = ContentService.fromEmbed(og: embedOg, url: embedUrl)
                }
            } catch {
                // Content generation failed — continue saving without content
            }

            // Local embedding is generated during sync (SyncEngine)
            // No need to send embedding to Supabase — search is fully on-device

            // Capture screenshot (non-fatal)
            do {
                let isAudioOnlyImportUpdate = mixType == .import && importMediaData == nil
                let screenshotMixTypeUpdate = isAudioOnlyImportUpdate ? MixType.audio : mixType

                let thumbnail: UIImage? = switch mixType {
                case .photo: photoThumbnail
                case .video: videoThumbnail
                case .import: importThumbnail ?? videoThumbnail
                default: nil
                }
                let embedImg: UIImage? = if let data = embedOgImageData { UIImage(data: data) } else { nil }

                // Extract gradient colors from source image before capturing screenshot
                let gradients: (top: String, bottom: String)?
                if let thumb = thumbnail {
                    gradients = ScreenshotService.extractGradients(from: thumb)
                } else {
                    gradients = nil
                }

                if let gradients {
                    payload.gradientTop = gradients.top
                    payload.gradientBottom = gradients.bottom
                }

                if let screenshot = ScreenshotService.capture(
                    mixType: screenshotMixTypeUpdate,
                    textContent: textContent,
                    mediaThumbnail: thumbnail,
                    embedUrl: hasEmbed ? embedUrl : nil,
                    embedOg: embedOg,
                    embedImage: embedImg,
                    gradientTop: gradients?.top,
                    gradientBottom: gradients?.bottom
                ), let jpegData = screenshot.jpegData(compressionQuality: 0.7) {
                    let screenshotUrl = try await repo.uploadMedia(data: jpegData, fileName: "screenshot.jpg", contentType: "image/jpeg")
                    payload.screenshotUrl = screenshotUrl

                    let scaleY = ScreenshotService.computeScaleY(
                        mixType: screenshotMixTypeUpdate,
                        textContent: textContent,
                        mediaThumbnail: thumbnail,
                        importHasVideo: importMediaData != nil,
                        embedImage: embedImg,
                        embedUrl: hasEmbed ? embedUrl : nil,
                        embedOg: embedOg
                    )
                    payload.previewScaleY = scaleY
                }
            } catch {
                // Screenshot capture/upload failed — continue without it
            }

            _ = try await repo.updateMix(id: mixId, payload)

            try? await tagRepo.setTagsForMix(mixId: mixId, tagIds: selectedTagIds)

            isCreating = false
            return true
        } catch {
            isGeneratingTTS = false
            isCreating = false
            errorMessage = error.localizedDescription
            return false
        }
    }
}
