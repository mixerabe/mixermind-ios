import SwiftUI
import CoreData
import AVFoundation
import UIKit

@Observable @MainActor
final class MixViewModel {

    enum Mode { case view, edit }

    struct EditState {
        var audioData: Data?
        var audioFileURL: URL?
        var isGeneratingAudio = false
        var audioError: String?
        var selectedTagIds: Set<UUID> = []
        var embedOgImageData: Data?
        // Media (photo or video) carried from CreatorView
        var mediaData: Data?
        var mediaThumbnail: UIImage?
        var mediaIsVideo: Bool = false
        var isLoadingMedia = false
        // Audio chip state
        var audioRemoved = false
        // File
        var fileData: Data?
        var fileName: String?
        // Widgets
        var widgets: [MixWidget] = []
    }

    let mode: Mode
    var editState = EditState()

    var mixes: [Mix]
    var scrolledID: UUID?
    private(set) var activeID: UUID?

    var isScrubbing = false
    private var wasPlayingBeforeScrub = false
    var tagsForCurrentMix: [Tag] = []
    var allTags: [Tag] = []
    var isAutoScroll = false
    private var isDeleting = false

    var videoPlayer: AVPlayer?
    var videoProgress: Double = 0
    private var loopObserver: Any?
    private var timeObserver: Any?
    var pendingLoad = false
    private(set) var hasAppeared = false

    let coordinator: AudioPlaybackCoordinator = resolve()

    var currentMix: Mix {
        mixes.first { $0.id == activeID } ?? mixes.first!
    }

    var hasPlayback: Bool { true }

    /// View mode — browsing existing mixes with paging
    init(mixes: [Mix], startIndex: Int) {
        self.mode = .view
        self.mixes = mixes
        if mixes.indices.contains(startIndex) {
            let id = mixes[startIndex].id
            self.scrolledID = id
            self.activeID = id
        }
    }

    /// Edit mode — editing a single unsaved mix
    init(editing mix: Mix) {
        self.mode = .edit
        self.mixes = [mix]
        self.scrolledID = mix.id
        self.activeID = mix.id
    }

    // MARK: - Lifecycle

    func onAppear() {
        guard !mixes.isEmpty else { return }
        hasAppeared = true

        if mode == .view {
            coordinator.loadQueue(mixes, startingAt: activeID)
            coordinator.isLooping = !isAutoScroll
            coordinator.play()
        }

        if mode == .edit {
            downloadEmbedOgImageIfNeeded()
        }

        loadCurrentMix()
    }

    func onDisappear() {
        stopVideoPlayback()
        if mode == .edit {
            if let url = editState.audioFileURL {
                try? FileManager.default.removeItem(at: url)
                editState.audioFileURL = nil
            }
        }
    }

    func onScrollChanged() {
        guard mode == .view else { return }
        guard !isDeleting, let scrolledID, scrolledID != activeID else { return }
        stopVideoPlayback()
        activeID = scrolledID
        videoProgress = 0
        pendingLoad = true
    }

    func onScrollIdle() {
        guard mode == .view else { return }
        guard !isDeleting, pendingLoad else { return }
        pendingLoad = false
        coordinator.jumpToTrack(id: activeID?.uuidString ?? "")
        loadCurrentMix()
    }

    // MARK: - Load Mix (video only)

    func loadCurrentMix() {
        let mix = currentMix
        loadTagsForCurrentMix()

        switch mix.type {
        case .media:
            if mix.mediaIsVideo, let urlString = mix.mediaUrl, let url = URL(string: urlString) {
                startVideoPlayback(url: url)
            }

        case .`import`:
            if mix.mediaIsVideo, let urlString = mix.mediaUrl, let url = URL(string: urlString) {
                startVideoPlayback(url: url)
            }

        case .note, .voice, .canvas:
            break
        }
    }

    // MARK: - Video Playback

    private func startVideoPlayback(url: URL) {
        stopVideoPlayback()

        let player = AVPlayer(url: url)
        player.volume = 0 // Video is always muted — coordinator handles audio
        player.isMuted = true
        videoPlayer = player

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self, weak player] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isAutoScroll {
                    // Coordinator handles track advance; this is just for the video
                } else {
                    player?.seek(to: .zero)
                    player?.play()
                }
            }
        }

        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, !self.isScrubbing,
                      let duration = self.videoPlayer?.currentItem?.duration,
                      duration.seconds.isFinite, duration.seconds > 0 else { return }
                self.videoProgress = time.seconds / duration.seconds
            }
        }

        player.play()
    }

    private func stopVideoPlayback() {
        if let observer = timeObserver, let player = videoPlayer {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        videoPlayer?.pause()
        videoPlayer = nil
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
    }

    // MARK: - Controls (delegate to coordinator)

    func togglePause() {
        coordinator.togglePlayPause()
        if coordinator.isPlaying {
            videoPlayer?.play()
        } else {
            videoPlayer?.pause()
        }
    }

    func toggleMute() {
        coordinator.setMuted(!coordinator.isMuted)
    }

    func beginScrub() {
        wasPlayingBeforeScrub = coordinator.isPlaying
        isScrubbing = true
        coordinator.pause()
        videoPlayer?.pause()
    }

    func scrub(to progress: Double) {
        let clamped = min(max(progress, 0), 1)

        // Seek coordinator audio
        if coordinator.duration > 0 {
            coordinator.seek(to: clamped * coordinator.duration)
        }

        // Seek video
        if let player = videoPlayer,
           let duration = player.currentItem?.duration,
           duration.seconds.isFinite, duration.seconds > 0 {
            let target = CMTime(seconds: clamped * duration.seconds, preferredTimescale: 600)
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        videoProgress = clamped
    }

    func endScrub() {
        isScrubbing = false
        if wasPlayingBeforeScrub {
            coordinator.resume()
            videoPlayer?.play()
        }
    }

    // MARK: - Coordinator Sync

    func syncFromCoordinator() {
        guard !isDeleting,
              let track = coordinator.currentTrack,
              let mixId = UUID(uuidString: track.id),
              mixId != activeID else { return }

        if mixes.contains(where: { $0.id == mixId }) {
            stopVideoPlayback()
            activeID = mixId
            videoProgress = 0
            withAnimation {
                scrolledID = mixId
            }
            loadCurrentMix()
        }
    }

    func syncActiveTrack() {
        guard let track = coordinator.currentTrack,
              let mixId = UUID(uuidString: track.id),
              mixId != activeID,
              mixes.contains(where: { $0.id == mixId }) else { return }

        activeID = mixId
        scrolledID = mixId
        videoProgress = 0
        loadTagsForCurrentMix()
    }

    // MARK: - Auto Scroll

    func advanceToNext() {
        guard let currentIndex = mixes.firstIndex(where: { $0.id == activeID }),
              currentIndex + 1 < mixes.count else { return }
        let nextId = mixes[currentIndex + 1].id
        withAnimation {
            scrolledID = nextId
        }
    }

    // MARK: - Tags

    var modelContext: NSManagedObjectContext?

    func loadTagsForCurrentMix() {
        tagsForCurrentMix = currentMix.tags
    }

    var sortedTags: [Tag] {
        let selectedIds = Set(tagsForCurrentMix.map(\.id))
        let selected = allTags.filter { selectedIds.contains($0.id) }
        let unselected = allTags.filter { !selectedIds.contains($0.id) }
        return selected + unselected
    }

    func loadAllTags() {
        guard let modelContext else { return }
        do {
            let request = NSFetchRequest<LocalTag>(entityName: "LocalTag")
            let localTags = try modelContext.fetch(request)
            allTags = localTags.map { $0.toTag() }
        } catch {}
    }

    func toggleTag(_ tag: Tag) {
        if mode == .edit {
            let isOn = editState.selectedTagIds.contains(tag.id)
            if isOn {
                editState.selectedTagIds.remove(tag.id)
                tagsForCurrentMix.removeAll { $0.id == tag.id }
            } else {
                editState.selectedTagIds.insert(tag.id)
                tagsForCurrentMix.append(tag)
            }
            if let i = mixes.firstIndex(where: { $0.id == currentMix.id }) {
                mixes[i].tags = tagsForCurrentMix
            }
            return
        }

        guard let modelContext else { return }
        let mixId = currentMix.id
        let isOn = tagsForCurrentMix.contains { $0.id == tag.id }

        if isOn {
            tagsForCurrentMix.removeAll { $0.id == tag.id }
            let request = NSFetchRequest<LocalMixTag>(entityName: "LocalMixTag")
            request.predicate = NSPredicate(format: "mixId == %@ AND tagId == %@", mixId as CVarArg, tag.id as CVarArg)
            request.fetchLimit = 1
            if let row = try? modelContext.fetch(request).first {
                modelContext.delete(row)
            }
        } else {
            tagsForCurrentMix.append(tag)
            _ = LocalMixTag(mixId: mixId, tagId: tag.id, context: modelContext)
        }

        if let i = mixes.firstIndex(where: { $0.id == mixId }) {
            mixes[i].tags = tagsForCurrentMix
        }
        try? modelContext.save()
    }

    func createAndAddTag(name: String) {
        guard let modelContext else { return }
        let tagId = UUID()
        let now = Date()
        let tag = Tag(id: tagId, name: name, createdAt: now)

        _ = LocalTag(tagId: tagId, name: name, createdAt: now, context: modelContext)
        try? modelContext.save()

        allTags.append(tag)
        allTags.sort { $0.name < $1.name }
        toggleTag(tag)
    }

    func reloadTagsFromLocal() {
        guard let modelContext else { return }
        let mixId = currentMix.id
        do {
            let tagRequest = NSFetchRequest<LocalTag>(entityName: "LocalTag")
            let localTags = try modelContext.fetch(tagRequest)
            allTags = localTags.map { $0.toTag() }

            let mixTagRequest = NSFetchRequest<LocalMixTag>(entityName: "LocalMixTag")
            mixTagRequest.predicate = NSPredicate(format: "mixId == %@", mixId as CVarArg)
            let localMixTags = try modelContext.fetch(mixTagRequest)
            let tagIdsForMix = Set(localMixTags.map(\.tagId))
            let tags = allTags.filter { tagIdsForMix.contains($0.id) }

            if let i = mixes.firstIndex(where: { $0.id == mixId }) {
                mixes[i].tags = tags
            }
            if currentMix.id == mixId {
                tagsForCurrentMix = tags
            }
        } catch {}
    }

    // MARK: - Title

    var titleDraft = ""

    func beginTitleEdit() {
        titleDraft = currentMix.title ?? ""
    }

    func commitTitle() {
        let text = titleDraft
        Task { await saveTitle(text) }
    }

    func saveTitle(_ text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String? = trimmed.isEmpty ? nil : trimmed
        let mixId = currentMix.id

        if let index = mixes.firstIndex(where: { $0.id == mixId }) {
            mixes[index].title = title
        }

        if mode == .edit { return true }

        if let modelContext {
            let request = NSFetchRequest<LocalMix>(entityName: "LocalMix")
            request.predicate = NSPredicate(format: "mixId == %@", mixId as CVarArg)
            request.fetchLimit = 1
            if let local = try? modelContext.fetch(request).first {
                local.title = title
                try? modelContext.save()
            }
        }
        return true
    }

    // MARK: - Delete

    func deleteCurrentMix() async -> Bool {
        isDeleting = true

        let mixId = currentMix.id
        let currentIndex = mixes.firstIndex(where: { $0.id == mixId }) ?? 0

        let nextId: UUID? = {
            if mixes.count <= 1 { return nil }
            if currentIndex + 1 < mixes.count {
                return mixes[currentIndex + 1].id
            }
            return mixes[currentIndex - 1].id
        }()

        if let nextId {
            stopVideoPlayback()
            activeID = nextId
            videoProgress = 0
            scrolledID = nil
            withAnimation(.spring(duration: 0.35)) {
                scrolledID = nextId
            }
        }

        try? await Task.sleep(for: .milliseconds(nextId != nil ? 400 : 0))

        mixes.removeAll { $0.id == mixId }

        if nextId != nil {
            coordinator.loadQueue(mixes, startingAt: activeID)
            loadCurrentMix()
        }

        try? await Task.sleep(for: .milliseconds(300))
        isDeleting = false

        if let modelContext {
            let repo: MixRepository = resolve()
            try? repo.deleteMix(id: mixId, context: modelContext)
        }

        return !mixes.isEmpty
    }

    // MARK: - Edit Mode: Audio Preview

    func generateTTS() {
        guard mode == .edit, currentMix.type == .note, let text = currentMix.textContent, !text.isEmpty else { return }

        editState.isGeneratingAudio = true
        editState.audioError = nil

        Task {
            do {
                let data = try await TextToSpeechService.synthesize(text: text)
                editState.audioData = data

                let tempDir = FileManager.default.temporaryDirectory
                let tempFile = tempDir.appendingPathComponent("tts_preview_\(UUID().uuidString).mp3")
                try data.write(to: tempFile)
                editState.audioFileURL = tempFile

                let mix = currentMix
                if let i = mixes.firstIndex(where: { $0.id == mix.id }) {
                    mixes[i].audioUrl = tempFile.absoluteString
                }

                coordinator.loadQueue(mixes, startingAt: activeID)
                coordinator.play()

                editState.isGeneratingAudio = false
            } catch {
                editState.audioError = error.localizedDescription
                editState.isGeneratingAudio = false
            }
        }
    }

    var hasAudioPreview: Bool { editState.audioFileURL != nil }

    // MARK: - Audio Chip (Editor)

    var editChipLabel: String {
        let mix = currentMix
        switch mix.type {
        case .note:
            return "Add audio"
        case .media:
            if mix.mediaIsVideo {
                return editState.audioRemoved ? "No audio" : "Video audio"
            }
            return hasAudioPreview ? "AI Summary" : "Add audio"
        case .voice:
            return "Original audio"
        case .canvas:
            // Check for file widget with audio/video extension
            if let fw = mix.fileWidget {
                let ext = ((fw.fileName ?? "") as NSString).pathExtension.lowercased()
                let audioExts = Set(["mp3", "m4a", "wav", "aac", "flac", "ogg"])
                let videoExts = Set(["mp4", "mov", "m4v"])
                if audioExts.contains(ext) || videoExts.contains(ext) {
                    return "File audio"
                }
            }
            return hasAudioPreview ? "AI Summary" : "Add audio"
        case .`import`:
            if mix.mediaIsVideo {
                return editState.audioRemoved ? "No audio" : "Video audio"
            }
            return "Original audio"
        }
    }

    var editChipIcon: String {
        let mix = currentMix
        switch mix.type {
        case .note:
            return hasAudioPreview ? "waveform.circle.fill" : "waveform.circle"
        case .media:
            if mix.mediaIsVideo {
                return editState.audioRemoved ? "speaker.slash" : "speaker.wave.2.fill"
            }
            return hasAudioPreview ? "waveform.circle.fill" : "waveform.circle"
        case .voice:
            return "waveform.circle.fill"
        case .canvas:
            return hasAudioPreview ? "waveform.circle.fill" : "waveform.circle"
        case .`import`:
            if mix.mediaIsVideo {
                return editState.audioRemoved ? "speaker.slash" : "speaker.wave.2.fill"
            }
            return "waveform.circle.fill"
        }
    }

    var chipHasGenerateAction: Bool {
        let mix = currentMix
        switch mix.type {
        case .note:
            return !hasAudioPreview
        case .media:
            if mix.mediaIsVideo { return false }
            return !hasAudioPreview
        case .canvas:
            return !hasAudioPreview
        case .voice, .`import`:
            return false
        }
    }

    var canRemoveAudio: Bool {
        let mix = currentMix
        switch mix.type {
        case .note:
            return hasAudioPreview
        case .media:
            if mix.mediaIsVideo {
                return !editState.audioRemoved
            }
            return hasAudioPreview
        case .canvas:
            return hasAudioPreview
        case .voice:
            return false
        case .`import`:
            if mix.mediaIsVideo {
                return !editState.audioRemoved
            }
            return false
        }
    }

    var viewerChipLabel: String? {
        let mix = currentMix
        switch mix.type {
        case .note:
            return nil
        case .media:
            if mix.mediaIsVideo {
                return mix.audioUrl == nil ? "No audio" : nil
            }
            return nil
        case .voice, .canvas, .`import`:
            return nil
        }
    }

    var viewerChipIcon: String? {
        guard let label = viewerChipLabel else { return nil }
        switch label {
        case "No audio": return "speaker.slash"
        default: return "waveform.circle"
        }
    }

    var chipIsLoading: Bool {
        editState.isGeneratingAudio
    }

    // MARK: - Audio Chip Actions

    func removeAudio() {
        let mix = currentMix
        switch mix.type {
        case .note, .canvas:
            if let url = editState.audioFileURL {
                try? FileManager.default.removeItem(at: url)
            }
            editState.audioData = nil
            editState.audioFileURL = nil
            if let i = mixes.firstIndex(where: { $0.id == mix.id }) {
                mixes[i].audioUrl = nil
            }
            coordinator.stop()

        case .media, .`import`:
            if mix.mediaIsVideo {
                editState.audioRemoved = true
                generateLocalSilenceForVideo()
            } else {
                if let url = editState.audioFileURL {
                    try? FileManager.default.removeItem(at: url)
                }
                editState.audioData = nil
                editState.audioFileURL = nil
                if let i = mixes.firstIndex(where: { $0.id == mix.id }) {
                    mixes[i].audioUrl = nil
                }
                coordinator.stop()
            }

        case .voice:
            break
        }
    }

    func generateAISummary() {
        guard mode == .edit else { return }
        editState.isGeneratingAudio = true

        Task {
            do {
                let silenceData = try generateSilence(duration: 5.0)
                editState.audioData = silenceData

                let tempFile = FileManager.default.temporaryDirectory
                    .appendingPathComponent("ai_summary_\(UUID().uuidString).m4a")
                try silenceData.write(to: tempFile)
                editState.audioFileURL = tempFile

                let mix = currentMix
                if let i = mixes.firstIndex(where: { $0.id == mix.id }) {
                    mixes[i].audioUrl = tempFile.absoluteString
                }
                coordinator.loadQueue(mixes, startingAt: activeID)
                coordinator.play()

                editState.isGeneratingAudio = false
            } catch {
                editState.isGeneratingAudio = false
            }
        }
    }

    func generateLocalSilenceForVideo() {
        Task {
            do {
                let mix = currentMix
                let videoData: Data? = editState.mediaData
                guard let videoData else { return }

                let duration = try await Self.videoDuration(from: videoData)
                let silenceData = try generateSilence(duration: duration)

                let tempFile = FileManager.default.temporaryDirectory
                    .appendingPathComponent("silence_\(UUID().uuidString).m4a")
                try silenceData.write(to: tempFile)

                if let i = mixes.firstIndex(where: { $0.id == mix.id }) {
                    mixes[i].audioUrl = tempFile.absoluteString
                }
                coordinator.loadQueue(mixes, startingAt: activeID)
                if coordinator.isPlaying {
                    coordinator.play()
                }
            } catch {}
        }
    }

    private func generateSilence(duration: TimeInterval) throws -> Data {
        let sampleRate: Double = 44100
        let channels: AVAudioChannelCount = 1
        let totalFrames = AVAudioFrameCount(sampleRate * max(duration, 0.1))

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels) else {
            throw NSError(domain: "MixViewModel", code: -1)
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            throw NSError(domain: "MixViewModel", code: -1)
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

    private static func videoDuration(from data: Data) async throws -> Double {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let asset = AVURLAsset(url: tempURL)
        let duration = try await asset.load(.duration)
        return duration.seconds
    }

    /// Download embed OG image for screenshot capture during save.
    private func downloadEmbedOgImageIfNeeded() {
        guard let imageUrlStr = currentMix.embedOg?.imageUrl,
              let imageUrl = URL(string: imageUrlStr) else { return }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: imageUrl)
                editState.embedOgImageData = data
            } catch {}
        }
    }

    // MARK: - Edit Mode: Save

    func saveMix() -> Bool {
        guard mode == .edit, let modelContext else { return false }

        let mix = currentMix
        let localFileManager = LocalFileManager.shared
        let mixId = mix.id
        let mixDir = mixId.uuidString

        let dirURL = localFileManager.fileURL(for: mixDir)
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        func writeSmall(_ data: Data?, name: String) -> String? {
            guard let data else { return nil }
            let path = "\(mixDir)/\(name)"
            let url = localFileManager.fileURL(for: path)
            do { try data.write(to: url); return path } catch { return nil }
        }

        // Collect widgets from editState or mix
        let widgets = editState.widgets.isEmpty ? mix.widgets : editState.widgets

        var request = MixCreationRequest(
            mixId: mixId,
            mixType: mix.type,
            createdAt: mix.createdAt,
            textContent: mix.textContent,
            title: mix.title,
            selectedTagIds: Array(editState.selectedTagIds),
            embedUrl: mix.embedUrl,
            audioRemoved: editState.audioRemoved,
            mediaIsVideo: mix.mediaIsVideo,
            widgets: widgets
        )

        var media = MixCreationMedia()

        switch mix.type {
        case .media:
            if mix.mediaIsVideo {
                if let videoData = editState.mediaData {
                    media.mediaData = videoData
                    media.mediaIsVideo = true
                    let thumbData = editState.mediaThumbnail.flatMap { $0.jpegData(compressionQuality: 0.7) }
                    media.mediaThumbnailData = thumbData
                    request.rawMediaPath = writeSmall(videoData, name: "media.mp4")
                    request.rawMediaThumbnailPath = writeSmall(thumbData, name: "media_thumb.jpg")
                }
            } else {
                if let photoData = editState.mediaData {
                    media.mediaData = photoData
                    let thumbData = editState.mediaThumbnail.flatMap { $0.jpegData(compressionQuality: 0.7) }
                    media.mediaThumbnailData = thumbData
                    request.rawMediaPath = writeSmall(photoData, name: "media.jpg")
                    request.rawMediaThumbnailPath = writeSmall(thumbData, name: "media_thumb.jpg")
                }
            }
            if let audioData = editState.audioData {
                media.audioData = audioData
                request.rawAudioPath = writeSmall(audioData, name: "audio.m4a")
            }

        case .voice:
            if let audioData = editState.audioData {
                media.audioData = audioData
                request.rawAudioPath = writeSmall(audioData, name: "voice.m4a")
            }

        case .canvas:
            // Handle embed widget OG image
            if let ogImageData = editState.embedOgImageData {
                media.embedOgImageData = ogImageData
                request.rawEmbedOgImagePath = writeSmall(ogImageData, name: "embed_og.jpg")
            }
            // Handle file widget data
            if let fileData = editState.fileData {
                media.fileData = fileData
                media.fileName = editState.fileName
                request.fileName = editState.fileName
                let ext = ((editState.fileName ?? "") as NSString).pathExtension
                let name = ext.isEmpty ? "raw_file" : "raw_file.\(ext)"
                request.rawFilePath = writeSmall(fileData, name: name)
            }
            if let audioData = editState.audioData {
                media.audioData = audioData
                request.rawAudioPath = writeSmall(audioData, name: "audio.m4a")
            }

        case .note:
            if let audioData = editState.audioData {
                media.audioData = audioData
                request.rawAudioPath = writeSmall(audioData, name: "audio.mp3")
            }

        case .`import`:
            if mix.mediaIsVideo {
                // Video import — same as .media video
                if let videoData = editState.mediaData {
                    media.mediaData = videoData
                    media.mediaIsVideo = true
                    let thumbData = editState.mediaThumbnail.flatMap { $0.jpegData(compressionQuality: 0.7) }
                    media.mediaThumbnailData = thumbData
                    request.rawMediaPath = writeSmall(videoData, name: "media.mp4")
                    request.rawMediaThumbnailPath = writeSmall(thumbData, name: "media_thumb.jpg")
                }
            } else {
                // Audio-only import — write raw MP4 for audio extraction
                if let videoData = editState.mediaData {
                    media.mediaData = videoData
                    request.rawMediaPath = writeSmall(videoData, name: "raw_import.mp4")
                }
            }
            if let audioData = editState.audioData {
                media.audioData = audioData
                request.rawAudioPath = writeSmall(audioData, name: "audio.m4a")
            }
            request.sourceUrl = mix.sourceUrl
        }

        // Encode embed OG for storage
        if let og = mix.embedOg {
            request.embedOgJson = try? JSONEncoder().encode(og)
        }

        let embedImage: UIImage? = editState.embedOgImageData.flatMap { UIImage(data: $0) }
        let thumbnail = editState.mediaThumbnail

        // Determine text bucket for note mixes
        let textBucket: ScreenshotService.TextBucket? = (mix.type == .note) ? .current : nil

        // Skip gradient extraction for media/import — use solid black
        if mix.type != .media && mix.type != .import, let thumb = thumbnail {
            let (top, bottom) = ScreenshotService.extractGradients(from: thumb)
            request.gradientTop = top
            request.gradientBottom = bottom
        }

        if let screenshot = ScreenshotService.capture(
            mixType: mix.type,
            textContent: mix.textContent ?? "",
            mediaThumbnail: thumbnail,
            widgets: widgets,
            embedImage: embedImage,
            gradientTop: request.gradientTop ?? mix.gradientTop,
            gradientBottom: request.gradientBottom ?? mix.gradientBottom,
            textBucket: textBucket
        ) {
            let jpegData = screenshot.jpegData(compressionQuality: 0.85)
            request.screenshotPath = writeSmall(jpegData, name: "screenshot.jpg")

            if thumbnail == nil, mix.type != .media, mix.type != .import {
                let (top, bottom) = ScreenshotService.extractGradients(from: screenshot)
                request.gradientTop = top
                request.gradientBottom = bottom
            }

            let crop = ScreenshotService.computeCrop(
                mixType: mix.type,
                textContent: mix.textContent ?? "",
                mediaThumbnail: thumbnail,
                widgets: widgets,
                embedImage: embedImage,
                textBucket: textBucket
            )
            request.previewCropX = crop.cropX
            request.previewCropY = crop.cropY
            request.previewCropScale = crop.cropScale
        }

        request.screenshotBucket = textBucket?.rawValue

        let creationService: MixCreationService = resolve()
        creationService.create(request: request, media: media, context: modelContext)

        coordinator.stop()
        if let url = editState.audioFileURL {
            try? FileManager.default.removeItem(at: url)
            editState.audioFileURL = nil
        }

        return true
    }
}
