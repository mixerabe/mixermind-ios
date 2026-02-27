import SwiftUI
import SwiftData
import AVFoundation
import UIKit

@Observable @MainActor
final class MixViewModel {

    enum Mode { case view, edit }

    struct EditState {
        var ttsAudioData: Data?
        var ttsAudioFileURL: URL?
        var isGeneratingTTS = false
        var ttsError: String?
        var selectedTagIds: Set<UUID> = []
        var embedOgImageData: Data?
        // Photo/video media carried from CreatorView
        var photoData: Data?
        var videoData: Data?
        var mediaThumbnail: UIImage?
        var isLoadingMedia = false
        // Audio recording carried from CreatorView
        var audioData: Data?
        var audioFileName: String?
        // Audio chip state
        var audioRemoved = false
        var aiSummaryAudioData: Data?
        var aiSummaryAudioFileURL: URL?
        var isGeneratingAISummary = false
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

    /// Edit mode — editing a single unpublished mix
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
        // Clean up temp files in edit mode
        if mode == .edit {
            if let url = editState.ttsAudioFileURL {
                try? FileManager.default.removeItem(at: url)
                editState.ttsAudioFileURL = nil
            }
            if let url = editState.aiSummaryAudioFileURL {
                try? FileManager.default.removeItem(at: url)
                editState.aiSummaryAudioFileURL = nil
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
        case .video:
            if let urlString = mix.videoUrl, let url = URL(string: urlString) {
                startVideoPlayback(url: url)
            }

        case .import:
            if let urlString = mix.importMediaUrl, let url = URL(string: urlString) {
                startVideoPlayback(url: url)
            }

        case .audio, .text, .photo, .embed:
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

    /// Called when coordinator's currentTrackIndex changes externally (lock screen, track finish).
    /// Scrolls the viewer to match and loads video.
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

    /// Lightweight sync — updates activeID and tags only, no video. Safe to call while minimized.
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

    private let tagRepo: TagRepository = resolve()
    var modelContext: ModelContext?

    func loadTagsForCurrentMix() {
        tagsForCurrentMix = currentMix.tags
    }

    /// Selected tags first, then the rest alphabetically
    var sortedTags: [Tag] {
        let selectedIds = Set(tagsForCurrentMix.map(\.id))
        let selected = allTags.filter { selectedIds.contains($0.id) }
        let unselected = allTags.filter { !selectedIds.contains($0.id) }
        return selected + unselected
    }

    func loadAllTags() {
        guard let modelContext else { return }
        do {
            let localTags = try modelContext.fetch(FetchDescriptor<LocalTag>())
            allTags = localTags.map { $0.toTag() }
        } catch {}
    }

    func toggleTag(_ tag: Tag) {
        if mode == .edit {
            // Edit mode: toggle in editState only (no SwiftData/Supabase)
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

        // View mode: persist to SwiftData + Supabase
        guard let modelContext else { return }
        let mixId = currentMix.id
        let isOn = tagsForCurrentMix.contains { $0.id == tag.id }

        if isOn {
            tagsForCurrentMix.removeAll { $0.id == tag.id }
            if let row = try? modelContext.fetch(FetchDescriptor<LocalMixTag>()).first(where: {
                $0.mixId == mixId && $0.tagId == tag.id
            }) {
                modelContext.delete(row)
            }
        } else {
            tagsForCurrentMix.append(tag)
            modelContext.insert(LocalMixTag(mixId: mixId, tagId: tag.id))
        }

        if let i = mixes.firstIndex(where: { $0.id == mixId }) {
            mixes[i].tags = tagsForCurrentMix
        }
        try? modelContext.save()

        let newIds = Set(tagsForCurrentMix.map(\.id))
        Task { try? await tagRepo.setTagsForMix(mixId: mixId, tagIds: newIds) }
    }

    func createAndAddTag(name: String) {
        guard let modelContext else { return }
        let tagId = UUID()
        let now = Date()
        let tag = Tag(id: tagId, name: name, createdAt: now)

        // Tags are global entities — always persist to SwiftData + Supabase
        modelContext.insert(LocalTag(tagId: tagId, name: name, createdAt: now))
        try? modelContext.save()

        allTags.append(tag)
        allTags.sort { $0.name < $1.name }
        toggleTag(tag) // Delegates to mode-aware toggleTag

        // Fire-and-forget Supabase call
        Task {
            if let remoteTag = try? await tagRepo.createTag(name: name) {
                if remoteTag.id != tagId {
                    await MainActor.run {
                        if let local = try? modelContext.fetch(FetchDescriptor<LocalTag>()).first(where: { $0.tagId == tagId }) {
                            local.tagId = remoteTag.id
                        }
                        // Only update LocalMixTag references in view mode
                        if self.mode == .view {
                            if let rows = try? modelContext.fetch(FetchDescriptor<LocalMixTag>()) {
                                for row in rows where row.tagId == tagId {
                                    row.tagId = remoteTag.id
                                }
                            }
                        }
                        // Update editState reference if in edit mode
                        if self.mode == .edit && self.editState.selectedTagIds.contains(tagId) {
                            self.editState.selectedTagIds.remove(tagId)
                            self.editState.selectedTagIds.insert(remoteTag.id)
                        }
                        try? modelContext.save()
                    }
                }
            }
        }
    }

    /// Reload tags from local SwiftData
    func reloadTagsFromLocal() {
        guard let modelContext else { return }
        let mixId = currentMix.id
        do {
            let localTags = try modelContext.fetch(FetchDescriptor<LocalTag>())
            allTags = localTags.map { $0.toTag() }

            let localMixTags = try modelContext.fetch(FetchDescriptor<LocalMixTag>())
            let tagIdsForMix = Set(localMixTags.filter { $0.mixId == mixId }.map(\.tagId))
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

    private let repo: MixRepository = resolve()

    func saveTitle(_ text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String? = trimmed.isEmpty ? nil : trimmed
        let mixId = currentMix.id

        if mode == .edit {
            // Edit mode: local-only update (not persisted yet)
            if let index = mixes.firstIndex(where: { $0.id == mixId }) {
                mixes[index] = reconstructMix(mixes[index], title: title)
            }
            return true
        }

        // View mode: persist to SwiftData + Supabase
        if let modelContext {
            if let local = try? modelContext.fetch(FetchDescriptor<LocalMix>()).first(where: { $0.mixId == mixId }) {
                local.title = title
                try? modelContext.save()
            }
        }
        if let index = mixes.firstIndex(where: { $0.id == mixId }) {
            mixes[index] = reconstructMix(mixes[index], title: title)
        }

        Task { _ = try? await repo.updateTitle(id: mixId, title: title) }
        return true
    }

    /// Reconstruct a mix with a new title, preserving all other fields.
    private func reconstructMix(_ mix: Mix, title: String?) -> Mix {
        Mix(
            id: mix.id,
            type: mix.type,
            createdAt: mix.createdAt,
            title: title,
            tags: mix.tags,
            textContent: mix.textContent,
            ttsAudioUrl: mix.ttsAudioUrl,
            photoUrl: mix.photoUrl,
            photoThumbnailUrl: mix.photoThumbnailUrl,
            videoUrl: mix.videoUrl,
            videoThumbnailUrl: mix.videoThumbnailUrl,
            importSourceUrl: mix.importSourceUrl,
            importMediaUrl: mix.importMediaUrl,
            importThumbnailUrl: mix.importThumbnailUrl,
            importAudioUrl: mix.importAudioUrl,
            embedUrl: mix.embedUrl,
            embedOg: mix.embedOg,
            audioUrl: mix.audioUrl,
            screenshotUrl: mix.screenshotUrl,
            previewScaleY: mix.previewScaleY,
            gradientTop: mix.gradientTop,
            gradientBottom: mix.gradientBottom
        )
    }

    // MARK: - Delete

    /// Deletes the current mix. Returns `true` if the viewer still has mixes to show,
    /// `false` if it was the last one (caller should dismiss).
    func deleteCurrentMix() async -> Bool {
        isDeleting = true

        let mixId = currentMix.id
        let currentIndex = mixes.firstIndex(where: { $0.id == mixId }) ?? 0

        // 1. Figure out which mix to land on before removing
        let nextId: UUID? = {
            if mixes.count <= 1 { return nil }
            if currentIndex + 1 < mixes.count {
                return mixes[currentIndex + 1].id
            }
            return mixes[currentIndex - 1].id
        }()

        // 2. Scroll to the neighbor first (animated)
        if let nextId {
            stopVideoPlayback()
            activeID = nextId
            videoProgress = 0
            // Reset scroll position so the binding recognizes the new target
            // (after a previous delete, scrolledID may already equal the current position)
            scrolledID = nil
            withAnimation(.spring(duration: 0.35)) {
                scrolledID = nextId
            }
        }

        // 3. Wait for scroll animation, then remove the deleted mix from the array
        try? await Task.sleep(for: .milliseconds(nextId != nil ? 400 : 0))

        mixes.removeAll { $0.id == mixId }

        // 4. Load the new current mix (video, tags)
        if nextId != nil {
            coordinator.loadQueue(mixes, startingAt: activeID)
            loadCurrentMix()
        }

        // 5. Keep flag true until SwiftUI layout settles after array mutation
        try? await Task.sleep(for: .milliseconds(300))
        isDeleting = false

        // 5. Delete from local storage
        if let modelContext {
            if let local = try? modelContext.fetch(FetchDescriptor<LocalMix>()).first(where: { $0.mixId == mixId }) {
                let fileManager = LocalFileManager.shared
                let paths = [
                    local.localTtsAudioPath, local.localPhotoPath, local.localPhotoThumbnailPath,
                    local.localVideoPath, local.localVideoThumbnailPath, local.localImportMediaPath,
                    local.localImportThumbnailPath, local.localImportAudioPath, local.localEmbedOgImagePath,
                    local.localAudioPath, local.localScreenshotPath,
                ]
                for path in paths {
                    if let path { fileManager.deleteFile(at: path) }
                }
                modelContext.delete(local)
            }
            if let rows = try? modelContext.fetch(FetchDescriptor<LocalMixTag>()) {
                for row in rows where row.mixId == mixId {
                    modelContext.delete(row)
                }
            }
            try? modelContext.save()
        }

        // 6. Fire-and-forget Supabase call
        Task { try? await repo.deleteMix(id: mixId) }

        return !mixes.isEmpty
    }

    // MARK: - Edit Mode: TTS Preview

    func generateTTS() {
        guard mode == .edit, let text = currentMix.textContent, !text.isEmpty else { return }

        editState.isGeneratingTTS = true
        editState.ttsError = nil

        Task {
            do {
                let data = try await TextToSpeechService.synthesize(text: text)
                editState.ttsAudioData = data

                // Write to temp file
                let tempDir = FileManager.default.temporaryDirectory
                let tempFile = tempDir.appendingPathComponent("tts_preview_\(UUID().uuidString).mp3")
                try data.write(to: tempFile)
                editState.ttsAudioFileURL = tempFile

                // Update mix with the temp file URL so coordinator can play it
                let mix = currentMix
                if let i = mixes.firstIndex(where: { $0.id == mix.id }) {
                    mixes[i] = Mix(
                        id: mix.id, type: mix.type, createdAt: mix.createdAt,
                        title: mix.title, tags: mix.tags,
                        textContent: mix.textContent,
                        ttsAudioUrl: tempFile.absoluteString,
                        gradientTop: mix.gradientTop,
                        gradientBottom: mix.gradientBottom
                    )
                }

                // Load and play via coordinator
                coordinator.loadQueue(mixes, startingAt: activeID)
                coordinator.play()

                editState.isGeneratingTTS = false
            } catch {
                editState.ttsError = error.localizedDescription
                editState.isGeneratingTTS = false
            }
        }
    }

    var hasTTSPreview: Bool { editState.ttsAudioFileURL != nil }

    // MARK: - Audio Chip (Editor)

    /// Whether the current import is audio-only (no video track).
    var isAudioOnlyImport: Bool {
        let mix = currentMix
        guard mix.type == .import else { return false }
        // Audio-only imports have importAudioUrl but no importMediaUrl
        if mode == .edit {
            return editState.audioData != nil && editState.videoData == nil
        }
        return mix.importAudioUrl != nil && mix.importMediaUrl == nil
    }

    var editChipLabel: String {
        let mix = currentMix
        switch mix.type {
        case .text:
            return hasTTSPreview ? "AI Transcribe" : "Add audio"
        case .photo:
            return editState.aiSummaryAudioFileURL != nil ? "AI Summary" : "Add audio"
        case .video:
            return editState.audioRemoved ? "No audio" : "Video audio"
        case .import:
            if isAudioOnlyImport { return "Original audio" }
            return editState.audioRemoved ? "No audio" : "Video audio"
        case .audio:
            return "Original audio"
        case .embed:
            return editState.aiSummaryAudioFileURL != nil ? "AI Summary" : "Add audio"
        }
    }

    var editChipIcon: String {
        let mix = currentMix
        switch mix.type {
        case .text:
            return hasTTSPreview ? "waveform.circle.fill" : "waveform.circle"
        case .photo, .embed:
            return editState.aiSummaryAudioFileURL != nil ? "waveform.circle.fill" : "waveform.circle"
        case .video, .import:
            if isAudioOnlyImport { return "waveform.circle.fill" }
            return editState.audioRemoved ? "speaker.slash" : "speaker.wave.2.fill"
        case .audio:
            return "waveform.circle.fill"
        }
    }

    /// Whether tapping the chip triggers audio generation (TTS or AI Summary).
    var chipHasGenerateAction: Bool {
        let mix = currentMix
        switch mix.type {
        case .text:
            return !hasTTSPreview
        case .photo, .embed:
            return editState.aiSummaryAudioFileURL == nil
        default:
            return false
        }
    }

    /// Whether the chip should offer a "Remove audio" option.
    var canRemoveAudio: Bool {
        let mix = currentMix
        switch mix.type {
        case .text:
            return hasTTSPreview
        case .photo, .embed:
            return editState.aiSummaryAudioFileURL != nil
        case .video:
            return !editState.audioRemoved
        case .import:
            if isAudioOnlyImport { return false }
            return !editState.audioRemoved
        case .audio:
            return false
        }
    }

    /// Viewer chip label — nil means don't show the chip.
    var viewerChipLabel: String? {
        let mix = currentMix
        switch mix.type {
        case .text:
            return mix.ttsAudioUrl != nil ? "AI Transcribe" : nil
        case .video:
            // audioUrl being silence-generated would be marked via lack of real audio
            return mix.audioUrl == nil ? "No audio" : nil
        case .import:
            if isAudioOnlyImport { return nil }
            return mix.importAudioUrl == nil ? "No audio" : nil
        default:
            return nil
        }
    }

    var viewerChipIcon: String? {
        guard let label = viewerChipLabel else { return nil }
        switch label {
        case "AI Transcribe": return "waveform.circle.fill"
        case "No audio": return "speaker.slash"
        default: return "waveform.circle"
        }
    }

    /// Whether the chip is in a loading state.
    var chipIsLoading: Bool {
        editState.isGeneratingTTS || editState.isGeneratingAISummary
    }

    // MARK: - Audio Chip Actions

    func removeAudio() {
        let mix = currentMix
        switch mix.type {
        case .text:
            // Remove TTS preview
            if let url = editState.ttsAudioFileURL {
                try? FileManager.default.removeItem(at: url)
            }
            editState.ttsAudioData = nil
            editState.ttsAudioFileURL = nil
            // Revert mix ttsAudioUrl
            if let i = mixes.firstIndex(where: { $0.id == mix.id }) {
                mixes[i] = reconstructMix(mixes[i], audioUrl: nil)
            }
            coordinator.stop()

        case .photo, .embed:
            // Remove AI Summary
            if let url = editState.aiSummaryAudioFileURL {
                try? FileManager.default.removeItem(at: url)
            }
            editState.aiSummaryAudioData = nil
            editState.aiSummaryAudioFileURL = nil
            coordinator.stop()

        case .video, .import:
            guard !isAudioOnlyImport else { return }
            editState.audioRemoved = true
            // Generate local silence so coordinator can still time playback
            generateLocalSilenceForVideo()

        case .audio:
            break
        }
    }

    func generateAISummary() {
        guard mode == .edit else { return }
        editState.isGeneratingAISummary = true

        Task {
            do {
                // Placeholder: 5s silence
                let silenceData = try generateSilence(duration: 5.0)
                editState.aiSummaryAudioData = silenceData

                let tempFile = FileManager.default.temporaryDirectory
                    .appendingPathComponent("ai_summary_\(UUID().uuidString).m4a")
                try silenceData.write(to: tempFile)
                editState.aiSummaryAudioFileURL = tempFile

                // Load into coordinator for preview playback
                let mix = currentMix
                if let i = mixes.firstIndex(where: { $0.id == mix.id }) {
                    mixes[i] = reconstructMix(mixes[i], audioUrl: tempFile.absoluteString)
                }
                coordinator.loadQueue(mixes, startingAt: activeID)
                coordinator.play()

                editState.isGeneratingAISummary = false
            } catch {
                editState.isGeneratingAISummary = false
            }
        }
    }

    func generateLocalSilenceForVideo() {
        Task {
            do {
                let mix = currentMix
                let videoData: Data? = editState.videoData
                guard let videoData else { return }

                let duration = try await Self.videoDuration(from: videoData)
                let silenceData = try generateSilence(duration: duration)

                let tempFile = FileManager.default.temporaryDirectory
                    .appendingPathComponent("silence_\(UUID().uuidString).m4a")
                try silenceData.write(to: tempFile)

                // Update mix so coordinator uses silence for timing
                if let i = mixes.firstIndex(where: { $0.id == mix.id }) {
                    mixes[i] = reconstructMix(mixes[i], audioUrl: tempFile.absoluteString)
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

    /// Reconstruct a mix with a new audio URL, preserving all other fields.
    private func reconstructMix(_ mix: Mix, audioUrl: String?) -> Mix {
        Mix(
            id: mix.id,
            type: mix.type,
            createdAt: mix.createdAt,
            title: mix.title,
            tags: mix.tags,
            textContent: mix.textContent,
            ttsAudioUrl: mix.type == .text ? audioUrl : mix.ttsAudioUrl,
            photoUrl: mix.photoUrl,
            photoThumbnailUrl: mix.photoThumbnailUrl,
            videoUrl: mix.videoUrl,
            videoThumbnailUrl: mix.videoThumbnailUrl,
            importSourceUrl: mix.importSourceUrl,
            importMediaUrl: mix.importMediaUrl,
            importThumbnailUrl: mix.importThumbnailUrl,
            importAudioUrl: mix.type == .import ? audioUrl : mix.importAudioUrl,
            embedUrl: mix.embedUrl,
            embedOg: mix.embedOg,
            audioUrl: (mix.type != .text && mix.type != .import) ? audioUrl : mix.audioUrl,
            screenshotUrl: mix.screenshotUrl,
            previewScaleY: mix.previewScaleY,
            gradientTop: mix.gradientTop,
            gradientBottom: mix.gradientBottom
        )
    }

    /// Download embed OG image for screenshot capture during publish.
    private func downloadEmbedOgImageIfNeeded() {
        guard currentMix.type == .embed,
              let imageUrlStr = currentMix.embedOg?.imageUrl,
              let imageUrl = URL(string: imageUrlStr) else { return }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: imageUrl)
                editState.embedOgImageData = data
            } catch {
                // Image download failed — continue without image
            }
        }
    }

    // MARK: - Edit Mode: Publish

    func publishMix() -> Bool {
        guard mode == .edit, let modelContext else { return false }

        let mix = currentMix
        let localFileManager = LocalFileManager.shared
        let mixId = mix.id
        let mixDir = mixId.uuidString

        // Ensure mix directory exists
        let dirURL = localFileManager.fileURL(for: mixDir)
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        func writeSmall(_ data: Data?, name: String) -> String? {
            guard let data else { return nil }
            let path = "\(mixDir)/\(name)"
            let url = localFileManager.fileURL(for: path)
            do { try data.write(to: url); return path } catch { return nil }
        }

        // Build request
        var request = MixCreationRequest(
            mixId: mixId,
            mixType: mix.type,
            createdAt: mix.createdAt,
            textContent: mix.textContent,
            title: mix.title,
            selectedTagIds: Array(editState.selectedTagIds),
            embedUrl: mix.type == .embed ? mix.embedUrl : nil,
            isAudioFromTTS: mix.type == .text,
            audioRemoved: editState.audioRemoved
        )

        // Prepare media
        var media = MixCreationMedia()

        switch mix.type {
        case .photo:
            if let photoData = editState.photoData {
                media.photoData = photoData
                let thumbData = editState.mediaThumbnail.flatMap { $0.jpegData(compressionQuality: 0.7) }
                media.photoThumbnailData = thumbData
                request.rawPhotoPath = writeSmall(photoData, name: "photo.jpg")
                request.rawPhotoThumbnailPath = writeSmall(thumbData, name: "photo_thumb.jpg")
            }
            // AI Summary audio for photo
            if let aiAudioData = editState.aiSummaryAudioData {
                request.rawAudioPath = writeSmall(aiAudioData, name: "ai_summary.m4a")
            }
        case .video:
            if let videoData = editState.videoData {
                media.videoData = videoData
                let thumbData = editState.mediaThumbnail.flatMap { $0.jpegData(compressionQuality: 0.7) }
                media.videoThumbnailData = thumbData
                request.rawVideoPath = writeSmall(videoData, name: "video.mp4")
                request.rawVideoThumbnailPath = writeSmall(thumbData, name: "video_thumb.jpg")
            }
        case .import:
            // Video already written to a file:// URL in mix.importMediaUrl by CreatorView
            if let importVideoData = editState.videoData {
                media.importMediaData = importVideoData
                let thumbData = editState.mediaThumbnail.flatMap { $0.jpegData(compressionQuality: 0.7) }
                media.importThumbnailData = thumbData
                request.rawImportMediaPath = writeSmall(importVideoData, name: "import_video.mp4")
                request.rawImportThumbnailPath = writeSmall(thumbData, name: "import_thumb.jpg")
            }
            request.importSourceUrl = mix.importSourceUrl
        case .embed:
            if let ogImageData = editState.embedOgImageData {
                media.embedOgImageData = ogImageData
                request.rawEmbedOgImagePath = writeSmall(ogImageData, name: "embed_og.jpg")
            }
            // AI Summary audio for embed
            if let aiAudioData = editState.aiSummaryAudioData {
                request.rawAudioPath = writeSmall(aiAudioData, name: "ai_summary.m4a")
            }
        case .audio:
            if let audioData = editState.audioData {
                media.audioData = audioData
                request.audioFileName = editState.audioFileName
                request.rawAudioPath = writeSmall(audioData, name: "audio.m4a")
            }
        case .text:
            break
        }

        // Encode OG metadata for embed type (moved out of earlier block)
        if mix.type == .embed, let og = mix.embedOg {
            request.embedOgJson = try? JSONEncoder().encode(og)
        }

        // Screenshot
        let embedImage: UIImage? = editState.embedOgImageData.flatMap { UIImage(data: $0) }
        let thumbnail = editState.mediaThumbnail

        // Extract gradients from thumbnail (photo/video) or screenshot (text/embed)
        if let thumb = thumbnail {
            let (top, bottom) = ScreenshotService.extractGradients(from: thumb)
            request.gradientTop = top
            request.gradientBottom = bottom
        }

        if let screenshot = ScreenshotService.capture(
            mixType: mix.type,
            textContent: mix.textContent ?? "",
            mediaThumbnail: thumbnail,
            embedUrl: mix.embedUrl,
            embedOg: mix.embedOg,
            embedImage: embedImage,
            gradientTop: request.gradientTop ?? mix.gradientTop,
            gradientBottom: request.gradientBottom ?? mix.gradientBottom
        ) {
            let jpegData = screenshot.jpegData(compressionQuality: 0.85)
            request.screenshotPath = writeSmall(jpegData, name: "screenshot.jpg")

            if thumbnail == nil {
                let (top, bottom) = ScreenshotService.extractGradients(from: screenshot)
                request.gradientTop = top
                request.gradientBottom = bottom
            }

            request.previewScaleY = ScreenshotService.computeScaleY(
                mixType: mix.type,
                textContent: mix.textContent ?? "",
                mediaThumbnail: thumbnail,
                importHasVideo: false,
                embedImage: embedImage,
                embedUrl: mix.embedUrl,
                embedOg: mix.embedOg
            )
        }

        // Enqueue — creates LocalMix with "creating" status immediately
        let creationService: MixCreationService = resolve()
        creationService.enqueue(request: request, media: media, modelContext: modelContext)

        // Notify home grid to reload and show the new "creating" card
        NotificationCenter.default.post(name: .mixCreationStatusChanged, object: nil)

        // Clean up coordinator + temp files
        coordinator.stop()
        if let url = editState.ttsAudioFileURL {
            try? FileManager.default.removeItem(at: url)
            editState.ttsAudioFileURL = nil
        }
        if let url = editState.aiSummaryAudioFileURL {
            try? FileManager.default.removeItem(at: url)
            editState.aiSummaryAudioFileURL = nil
        }

        return true
    }
}
