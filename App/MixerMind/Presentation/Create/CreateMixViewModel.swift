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
    var autoCreateTitle = true
    var isGeneratingTitle = false

    // MARK: - Edit Mode

    private var editingMixId: UUID?
    var isEditing: Bool { editingMixId != nil }

    var isCreating = false
    var errorMessage: String?
    var isMuted = false
    var isPaused = false
    var isScrubbing = false

    // Playback
    var videoPlayer: AVPlayer?
    var playbackProgress: Double = 0
    private var audioPlayer: AVAudioPlayer?
    private var videoTempURL: URL?
    private var audioTempURL: URL?
    private var loopObserver: Any?
    private var timeObserver: Any?
    private var progressTimer: Timer?

    var selectedPhotoItem: PhotosPickerItem? {
        didSet { loadPhoto() }
    }

    var hasText: Bool { !textContent.isEmpty }
    var hasUnsavedContent: Bool { mixType != .text || hasText }

    private let repo: MixRepository = resolve()
    private let tagRepo: TagRepository = resolve()
    var modelContext: ModelContext?

    init() {
        configureAudioSession()
    }

    init(editing mix: Mix, skipPlayback: Bool = false) {
        self.editingMixId = mix.id
        self.mixType = mix.type
        self.textContent = mix.textContent ?? ""
        self.embedUrl = mix.embedUrl ?? ""
        self.embedOg = mix.embedOg

        configureAudioSession()

        if !skipPlayback {
            loadExistingContent(mix: mix)
        }
    }

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .default,
            options: []
        )
        try? AVAudioSession.sharedInstance().setActive(true)
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
            self.startVideoPlayback(from: data)
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
                        self.startVideoPlayback(from: data)
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

    // MARK: - Video Playback

    private func startVideoPlayback(from data: Data) {
        stopVideoPlayback()
        configureAudioSession()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")
        do {
            try data.write(to: tempURL)
        } catch {
            return
        }
        videoTempURL = tempURL

        let player = AVPlayer(url: tempURL)
        player.volume = 1.0
        player.isMuted = isMuted
        videoPlayer = player

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }

        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, !self.isScrubbing,
                      let duration = self.videoPlayer?.currentItem?.duration,
                      duration.seconds.isFinite, duration.seconds > 0 else { return }
                self.playbackProgress = time.seconds / duration.seconds
            }
        }

        player.play()

        generateVideoThumbnail(from: tempURL)
    }

    private func stopVideoPlayback() {
        if let observer = timeObserver, let player = videoPlayer {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        videoPlayer?.pause()
        videoPlayer = nil
        playbackProgress = 0
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
        if let url = videoTempURL {
            try? FileManager.default.removeItem(at: url)
            videoTempURL = nil
        }
    }

    private func generateVideoThumbnail(from url: URL) {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0, preferredTimescale: 600)
        Task {
            do {
                let (cgImage, _) = try await generator.image(at: time)
                self.videoThumbnail = UIImage(cgImage: cgImage)
            } catch {}
        }
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

    // MARK: - Audio Playback

    private func stopAudioPlayback() {
        progressTimer?.invalidate()
        progressTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        if videoPlayer == nil { playbackProgress = 0 }
    }

    // MARK: - Mute

    func toggleMute() {
        isMuted.toggle()
        audioPlayer?.volume = isMuted ? 0 : 1
        videoPlayer?.isMuted = isMuted
    }

    // MARK: - Pause / Resume

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            videoPlayer?.pause()
            audioPlayer?.pause()
        } else {
            videoPlayer?.play()
            audioPlayer?.play()
        }
    }

    // MARK: - Scrubbing

    private var wasPlayingBeforeScrub = false

    func beginScrub() {
        isScrubbing = true
        wasPlayingBeforeScrub = !isPaused
        videoPlayer?.pause()
        audioPlayer?.pause()
    }

    func scrub(to progress: Double) {
        let clamped = min(max(progress, 0), 1)
        playbackProgress = clamped

        if let player = videoPlayer,
           let duration = player.currentItem?.duration,
           duration.seconds.isFinite, duration.seconds > 0 {
            let target = CMTime(seconds: clamped * duration.seconds, preferredTimescale: 600)
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        if let audio = audioPlayer, audio.duration > 0 {
            audio.currentTime = clamped * audio.duration
        }
    }

    func endScrub() {
        isScrubbing = false
        if wasPlayingBeforeScrub {
            videoPlayer?.play()
            audioPlayer?.play()
        }
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
        self.startVideoPlayback(from: videoData)
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

        // Auto-generate title: "Host -- Page Title" (capped at 50 chars)
        let ogTitle = embedOg?.title
        let host = embedOg?.host
        if let ogTitle, !ogTitle.isEmpty, let host, !host.isEmpty {
            title = String("\(host) -- \(ogTitle)".prefix(50))
        } else if let ogTitle, !ogTitle.isEmpty {
            title = String(ogTitle.prefix(50))
        } else if let host, !host.isEmpty {
            title = host
        }
    }

    // MARK: - Clear

    func clearAll() {
        stopVideoPlayback()
        stopAudioPlayback()
        isPaused = false
        playbackProgress = 0
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

    // MARK: - Cleanup

    func stopAllPlayback() {
        stopVideoPlayback()
        stopAudioPlayback()
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

    // MARK: - Save (Create or Update)

    func saveMix() async -> Bool {
        isEditing ? await performUpdate() : await performCreate()
    }

    private func performCreate() async -> Bool {
        isCreating = true
        errorMessage = nil
        do {
            var payload = CreateMixPayload(type: mixType)

            switch mixType {
            case .text:
                payload.textContent = hasText ? textContent : nil
                // Generate TTS (non-fatal — save the mix even if TTS fails)
                if hasText {
                    isGeneratingTTS = true
                    do {
                        let ttsData = try await TextToSpeechService.synthesize(text: textContent)
                        let ttsUrl = try await repo.uploadMedia(data: ttsData, fileName: "tts.mp3", contentType: "audio/mpeg")
                        payload.ttsAudioUrl = ttsUrl
                    } catch {
                        // TTS failed — continue saving without audio
                    }
                    isGeneratingTTS = false
                }
            case .photo:
                if var data = photoData {
                    let url = try await repo.uploadMedia(data: data, fileName: "image.jpg", contentType: "image/jpeg")
                    payload.photoUrl = url
                    // Generate thumbnail
                    if let thumb = photoThumbnail {
                        let targetWidth: CGFloat = 300
                        let scale = targetWidth / thumb.size.width
                        let targetSize = CGSize(width: targetWidth, height: thumb.size.height * scale)
                        let format = UIGraphicsImageRendererFormat()
                        format.scale = 1.0
                        let resized = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
                            thumb.draw(in: CGRect(origin: .zero, size: targetSize))
                        }
                        if let thumbData = resized.jpegData(compressionQuality: 0.5) {
                            let thumbUrl = try await repo.uploadMedia(data: thumbData, fileName: "photo_thumb.jpg", contentType: "image/jpeg")
                            payload.photoThumbnailUrl = thumbUrl
                        }
                    }
                }

            case .video:
                if var data = videoData {
                    data = try await compressVideo(data: data)
                    let url = try await repo.uploadMedia(data: data, fileName: "video.mp4", contentType: "video/mp4")
                    payload.videoUrl = url
                    if let thumb = videoThumbnail, let thumbData = thumb.jpegData(compressionQuality: 0.5) {
                        let thumbUrl = try await repo.uploadMedia(data: thumbData, fileName: "video_thumb.jpg", contentType: "image/jpeg")
                        payload.videoThumbnailUrl = thumbUrl
                    }
                }

            case .import:
                payload.importSourceUrl = importSourceUrl
                if var data = importMediaData {
                    data = try await compressVideo(data: data)
                    let url = try await repo.uploadMedia(data: data, fileName: "import_video.mp4", contentType: "video/mp4")
                    payload.importMediaUrl = url
                    if let thumb = videoThumbnail, let thumbData = thumb.jpegData(compressionQuality: 0.5) {
                        let thumbUrl = try await repo.uploadMedia(data: thumbData, fileName: "import_thumb.jpg", contentType: "image/jpeg")
                        payload.importThumbnailUrl = thumbUrl
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

            // Generate searchable content (non-fatal)
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
                    // Audio transcription of video — extract audio track first
                    if let data = videoData {
                        let audioTrack = try await extractAudioFromVideo(data: data)
                        payload.content = try await ContentService.fromAudio(data: audioTrack, fileName: "video_audio.m4a")
                    }
                case .import:
                    // Prefer import audio if available, otherwise extract from video
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

            // Generate embedding from content (non-fatal)
            if let contentText = payload.content, !contentText.isEmpty {
                do {
                    let embedding = try await EmbeddingService.generate(from: contentText)
                    payload.contentEmbedding = PgVector(values: embedding)
                } catch {
                    // Embedding generation failed — continue saving without embedding
                }
            }

            // Auto-generate title (non-fatal)
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTitle.isEmpty {
                payload.title = trimmedTitle
            } else if autoCreateTitle {
                isGeneratingTitle = true
                do {
                    let generated: String
                    switch mixType {
                    case .text:
                        if hasText {
                            generated = try await TitleService.fromText(textContent)
                        } else { generated = "" }
                    case .audio:
                        if let data = audioData {
                            let name = audioFileName ?? "audio.m4a"
                            let ct = name.hasSuffix(".mp3") ? "audio/mpeg" : "audio/m4a"
                            generated = try await TitleService.fromAudio(data: data, fileName: name, contentType: ct)
                        } else { generated = "" }
                    default:
                        generated = ""
                    }
                    if !generated.isEmpty { payload.title = generated }
                } catch {
                    // Title generation failed — continue saving without title
                }
                isGeneratingTitle = false
            }

            let createdMix = try await repo.createMix(payload)

            if !selectedTagIds.isEmpty {
                try? await tagRepo.setTagsForMix(mixId: createdMix.id, tagIds: selectedTagIds)
            }

            isCreating = false
            return true
        } catch {
            isGeneratingTitle = false
            isGeneratingTTS = false
            isCreating = false
            errorMessage = error.localizedDescription
            return false
        }
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
                if var data = videoData {
                    data = try await compressVideo(data: data)
                    let url = try await repo.uploadMedia(data: data, fileName: "video.mp4", contentType: "video/mp4")
                    payload.videoUrl = url
                }

            case .import:
                payload.importSourceUrl = importSourceUrl
                if var data = importMediaData {
                    data = try await compressVideo(data: data)
                    let url = try await repo.uploadMedia(data: data, fileName: "import_video.mp4", contentType: "video/mp4")
                    payload.importMediaUrl = url
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

            // Generate embedding from content (non-fatal)
            if let contentText = payload.content, !contentText.isEmpty {
                do {
                    let embedding = try await EmbeddingService.generate(from: contentText)
                    payload.contentEmbedding = PgVector(values: embedding)
                } catch {
                    // Embedding generation failed — continue saving without embedding
                }
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
