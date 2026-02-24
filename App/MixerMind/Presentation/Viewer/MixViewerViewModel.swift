import SwiftUI
import SwiftData
import AVFoundation

@Observable @MainActor
final class MixViewerViewModel: NSObject, AVAudioPlayerDelegate {
    var mixes: [Mix]
    var scrolledID: UUID?
    private var activeID: UUID?

    var isMuted = false
    var isPaused = false
    var isScrubbing = false
    var playbackProgress: Double = 0
    var tagsForCurrentMix: [Tag] = []
    var allTags: [Tag] = []
    var isAutoScroll = false

    var videoPlayer: AVPlayer?
    private var audioPlayer: AVAudioPlayer?
    private var loopObserver: Any?
    private var timeObserver: Any?
    private var progressTimer: Timer?
    var pendingLoad = false

    var currentMix: Mix {
        mixes.first { $0.id == activeID } ?? mixes.first!
    }

    var hasPlayback: Bool { true }

    var currentDuration: TimeInterval {
        if let audio = audioPlayer, audio.duration > 0 {
            return audio.duration
        }
        if let item = videoPlayer?.currentItem,
           item.duration.seconds.isFinite, item.duration.seconds > 0 {
            return item.duration.seconds
        }
        return 0
    }

    private var hasRealMedia: Bool {
        switch currentMix.type {
        case .video, .import:
            return true
        case .audio:
            return currentMix.audioUrl != nil
        case .text:
            return currentMix.ttsAudioUrl != nil
        case .photo, .embed:
            return false
        }
    }

    private static let fallbackDuration: TimeInterval = 15
    private var fallbackTimer: Timer?
    private var fallbackPausedElapsed: TimeInterval = 0

    init(mixes: [Mix], startIndex: Int) {
        self.mixes = mixes
        if mixes.indices.contains(startIndex) {
            let id = mixes[startIndex].id
            self.scrolledID = id
            self.activeID = id
        }
        super.init()
    }

    // MARK: - Lifecycle

    func onAppear() {
        guard !mixes.isEmpty else { return }
        configureAudioSession()
        loadCurrentMix()
    }

    func onDisappear() {
        stopAllPlayback()
    }

    func onScrollChanged() {
        guard let scrolledID, scrolledID != activeID else { return }
        stopAllPlayback()
        activeID = scrolledID
        isMuted = false
        isPaused = false
        playbackProgress = 0
        fallbackPausedElapsed = 0
        pendingLoad = true
    }

    func onScrollIdle() {
        guard pendingLoad else { return }
        pendingLoad = false
        loadCurrentMix()
    }

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .default,
            options: [.mixWithOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: - Load Mix

    func reloadCurrentMix() {
        loadCurrentMix()
    }

    private func loadCurrentMix() {
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
            if let urlString = mix.importAudioUrl, let url = URL(string: urlString) {
                loadAudioFromURL(url)
            }

        case .audio:
            if let urlString = mix.audioUrl, let url = URL(string: urlString) {
                loadAudioFromURL(url)
            }

        case .text:
            if let urlString = mix.ttsAudioUrl, let url = URL(string: urlString) {
                loadAudioFromURL(url)
            }

        case .photo, .embed:
            break
        }

        if !hasRealMedia {
            startFallbackTimer()
        }
    }

    // MARK: - Video Playback

    private func startVideoPlayback(url: URL) {
        stopVideoPlayback()

        let player = AVPlayer(url: url)
        player.volume = 1.0
        let hasSeparateAudio = currentMix.importAudioUrl != nil
        player.isMuted = isMuted || hasSeparateAudio
        videoPlayer = player

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self, weak player] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isAutoScroll {
                    self.advanceToNext()
                } else {
                    player?.seek(to: .zero)
                    player?.play()
                    self.onVideoLooped()
                }
            }
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

    // MARK: - Audio Playback

    private func loadAudioFromURL(_ url: URL) {
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                startAudioPlayback(from: data)
            } catch {}
        }
    }

    private func startAudioPlayback(from data: Data) {
        stopAudioPlayback()

        do {
            let player = try AVAudioPlayer(data: data)
            player.volume = isMuted ? 0 : 1

            if videoPlayer != nil {
                player.numberOfLoops = 0
            } else {
                player.numberOfLoops = isAutoScroll ? 0 : -1
                startAudioProgressTimer()
            }

            player.prepareToPlay()
            player.play()
            audioPlayer = player
        } catch {}
    }

    private func onVideoLooped() {
        guard currentMix.importAudioUrl != nil else { return }
        audioPlayer?.currentTime = 0
        audioPlayer?.play()
    }

    private func startAudioProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isScrubbing,
                      let player = self.audioPlayer,
                      player.duration > 0 else { return }
                let progress = player.currentTime / player.duration
                self.playbackProgress = progress
                // Standalone audio finished — advance if auto-scroll
                if self.isAutoScroll, !player.isPlaying, progress >= 0.95 {
                    self.advanceToNext()
                }
            }
        }
    }

    private func stopAudioPlayback() {
        progressTimer?.invalidate()
        progressTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
    }

    // MARK: - Fallback Timer (15s for text/photo/embed mixes)

    private var fallbackStartDate: Date?

    private func startFallbackTimer() {
        stopFallbackTimer()
        fallbackStartDate = Date()
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isScrubbing, !self.isPaused,
                      let start = self.fallbackStartDate else { return }
                let elapsed = Date().timeIntervalSince(start)
                let progress = elapsed / Self.fallbackDuration
                if progress >= 1 {
                    if self.isAutoScroll {
                        self.advanceToNext()
                    } else {
                        self.fallbackStartDate = Date()
                        self.playbackProgress = 0
                    }
                } else {
                    self.playbackProgress = progress
                }
            }
        }
    }

    private func stopFallbackTimer() {
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        fallbackStartDate = nil
    }

    // MARK: - Controls

    func toggleMute() {
        isMuted.toggle()
        audioPlayer?.volume = isMuted ? 0 : 1
        let hasSeparateAudio = currentMix.importAudioUrl != nil
        videoPlayer?.isMuted = isMuted || hasSeparateAudio
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            videoPlayer?.pause()
            audioPlayer?.pause()
            if let start = fallbackStartDate {
                fallbackPausedElapsed = Date().timeIntervalSince(start)
                fallbackTimer?.invalidate()
                fallbackTimer = nil
            }
        } else {
            videoPlayer?.play()
            audioPlayer?.play()
            if fallbackPausedElapsed > 0, !hasRealMedia {
                fallbackStartDate = Date().addingTimeInterval(-fallbackPausedElapsed)
                fallbackPausedElapsed = 0
                startFallbackTimer()
            }
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
            if !hasRealMedia {
                let elapsed = playbackProgress * Self.fallbackDuration
                fallbackStartDate = Date().addingTimeInterval(-elapsed)
                startFallbackTimer()
            }
        } else if !hasRealMedia {
            fallbackPausedElapsed = playbackProgress * Self.fallbackDuration
        }
    }

    // MARK: - Cleanup

    func stopAllPlayback() {
        stopVideoPlayback()
        stopAudioPlayback()
        stopFallbackTimer()
        playbackProgress = 0
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
        guard let modelContext else { return }
        let mixId = currentMix.id
        let isOn = tagsForCurrentMix.contains { $0.id == tag.id }

        // Optimistic local update
        if isOn {
            tagsForCurrentMix.removeAll { $0.id == tag.id }
            // Delete from SwiftData
            if let row = try? modelContext.fetch(FetchDescriptor<LocalMixTag>()).first(where: {
                $0.mixId == mixId && $0.tagId == tag.id
            }) {
                modelContext.delete(row)
            }
        } else {
            tagsForCurrentMix.append(tag)
            // Add to SwiftData
            modelContext.insert(LocalMixTag(mixId: mixId, tagId: tag.id))
        }

        if let i = mixes.firstIndex(where: { $0.id == mixId }) {
            mixes[i].tags = tagsForCurrentMix
        }
        try? modelContext.save()

        // Fire-and-forget Supabase call
        let newIds = Set(tagsForCurrentMix.map(\.id))
        Task { try? await tagRepo.setTagsForMix(mixId: mixId, tagIds: newIds) }
    }

    func createAndAddTag(name: String) {
        guard let modelContext else { return }
        let tagId = UUID()
        let now = Date()
        let tag = Tag(id: tagId, name: name, createdAt: now)

        // Optimistic: add to SwiftData + local state immediately
        modelContext.insert(LocalTag(tagId: tagId, name: name, createdAt: now))
        try? modelContext.save()

        allTags.append(tag)
        allTags.sort { $0.name < $1.name }
        toggleTag(tag)

        // Fire-and-forget Supabase call
        Task {
            if let remoteTag = try? await tagRepo.createTag(name: name) {
                // If remote ID differs, update local
                if remoteTag.id != tagId {
                    await MainActor.run {
                        // Update LocalTag
                        if let local = try? modelContext.fetch(FetchDescriptor<LocalTag>()).first(where: { $0.tagId == tagId }) {
                            local.tagId = remoteTag.id
                        }
                        // Update LocalMixTag references
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

    // MARK: - Auto Scroll

    func advanceToNext() {
        guard let currentIndex = mixes.firstIndex(where: { $0.id == activeID }),
              currentIndex + 1 < mixes.count else { return }
        let nextId = mixes[currentIndex + 1].id
        withAnimation {
            scrolledID = nextId
        }
    }

    // MARK: - Title

    private let repo: MixRepository = resolve()

    func saveTitle(_ text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String? = trimmed.isEmpty ? nil : trimmed
        let mixId = currentMix.id

        // Optimistic local update
        if let modelContext {
            if let local = try? modelContext.fetch(FetchDescriptor<LocalMix>()).first(where: { $0.mixId == mixId }) {
                local.title = title
                try? modelContext.save()
            }
        }
        if let index = mixes.firstIndex(where: { $0.id == mixId }) {
            mixes[index] = Mix(
                id: mixes[index].id,
                type: mixes[index].type,
                createdAt: mixes[index].createdAt,
                title: title,
                tags: mixes[index].tags,
                textContent: mixes[index].textContent,
                ttsAudioUrl: mixes[index].ttsAudioUrl,
                photoUrl: mixes[index].photoUrl,
                photoThumbnailUrl: mixes[index].photoThumbnailUrl,
                videoUrl: mixes[index].videoUrl,
                videoThumbnailUrl: mixes[index].videoThumbnailUrl,
                importSourceUrl: mixes[index].importSourceUrl,
                importMediaUrl: mixes[index].importMediaUrl,
                importThumbnailUrl: mixes[index].importThumbnailUrl,
                importAudioUrl: mixes[index].importAudioUrl,
                embedUrl: mixes[index].embedUrl,
                embedOg: mixes[index].embedOg,
                audioUrl: mixes[index].audioUrl
            )
        }

        // Fire-and-forget Supabase call
        Task { _ = try? await repo.updateTitle(id: mixId, title: title) }
        return true
    }

    // MARK: - Delete

    func deleteCurrentMix() async -> Bool {
        let mixId = currentMix.id

        // Optimistic local delete
        if let modelContext {
            if let local = try? modelContext.fetch(FetchDescriptor<LocalMix>()).first(where: { $0.mixId == mixId }) {
                // Delete local media files
                let fileManager = LocalFileManager.shared
                let paths = [
                    local.localTtsAudioPath, local.localPhotoPath, local.localPhotoThumbnailPath,
                    local.localVideoPath, local.localVideoThumbnailPath, local.localImportMediaPath,
                    local.localImportThumbnailPath, local.localImportAudioPath, local.localEmbedOgImagePath,
                    local.localAudioPath,
                ]
                for path in paths {
                    if let path { fileManager.deleteFile(at: path) }
                }
                modelContext.delete(local)
            }
            // Delete mix_tag relationships
            if let rows = try? modelContext.fetch(FetchDescriptor<LocalMixTag>()) {
                for row in rows where row.mixId == mixId {
                    modelContext.delete(row)
                }
            }
            try? modelContext.save()
        }

        // Fire-and-forget Supabase call
        Task { try? await repo.deleteMix(id: mixId) }
        return true
    }
}
