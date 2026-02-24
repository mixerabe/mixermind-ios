import SwiftUI
import AVFoundation
import MusicKit

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
    private var musicPlayer = ApplicationMusicPlayer.shared
    private var isUsingMusicPlayer = false
    private var musicProgressTimer: Timer?
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
        if isUsingMusicPlayer, musicSongDuration > 0 {
            return musicSongDuration
        }
        return 0
    }

    private var hasRealMedia: Bool {
        switch currentMix.type {
        case .video, .import:
            return true
        case .audio:
            return currentMix.audioUrl != nil
        case .appleMusic:
            return currentMix.appleMusicId != nil
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

        case .appleMusic:
            if let musicId = mix.appleMusicId {
                startAppleMusicPlayback(id: musicId)
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

    private var musicSongDuration: TimeInterval = 0

    private func startAppleMusicPlayback(id: String) {
        Task {
            do {
                let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(id))
                let response = try await request.response()
                guard let song = response.items.first else { return }

                #if targetEnvironment(simulator)
                // ApplicationMusicPlayer unavailable on Simulator — use 30s preview
                if let previewURL = song.previewAssets?.first?.url {
                    let (data, _) = try await URLSession.shared.data(from: previewURL)
                    startAudioPlayback(from: data)
                }
                #else
                musicSongDuration = song.duration ?? 0
                musicPlayer.queue = [song]
                try await musicPlayer.play()
                isUsingMusicPlayer = true
                startMusicProgressTimer()
                #endif
            } catch {}
        }
    }

    private func startMusicProgressTimer() {
        musicProgressTimer?.invalidate()
        let vm = self
        musicProgressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                guard vm.isUsingMusicPlayer, !vm.isScrubbing else { return }
                let duration = vm.musicSongDuration
                guard duration > 0 else { return }
                let currentTime = vm.musicPlayer.playbackTime
                vm.playbackProgress = currentTime / duration

                // Song ended
                let status = vm.musicPlayer.state.playbackStatus
                if (status == .stopped || status == .paused) && currentTime >= duration - 0.5 {
                    if vm.isAutoScroll {
                        vm.advanceToNext()
                    } else {
                        vm.musicPlayer.restartCurrentEntry()
                        try? await vm.musicPlayer.play()
                    }
                }
            }
        }
    }

    private func stopMusicPlayback() {
        musicProgressTimer?.invalidate()
        musicProgressTimer = nil
        if isUsingMusicPlayer {
            musicPlayer.stop()
            isUsingMusicPlayer = false
        }
    }

    // MARK: - Video Playback

    private func startVideoPlayback(url: URL) {
        stopVideoPlayback()

        let player = AVPlayer(url: url)
        player.volume = 1.0
        let hasSeparateAudio = currentMix.importAudioUrl != nil || currentMix.appleMusicId != nil
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
        guard currentMix.importAudioUrl != nil || currentMix.appleMusicId != nil else { return }
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
        let hasSeparateAudio = currentMix.importAudioUrl != nil || currentMix.appleMusicId != nil
        videoPlayer?.isMuted = isMuted || hasSeparateAudio
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            videoPlayer?.pause()
            audioPlayer?.pause()
            if isUsingMusicPlayer { musicPlayer.pause() }
            if let start = fallbackStartDate {
                fallbackPausedElapsed = Date().timeIntervalSince(start)
                fallbackTimer?.invalidate()
                fallbackTimer = nil
            }
        } else {
            videoPlayer?.play()
            audioPlayer?.play()
            if isUsingMusicPlayer {
                Task { try? await musicPlayer.play() }
            }
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
        if isUsingMusicPlayer { musicPlayer.pause() }
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

        if isUsingMusicPlayer, musicSongDuration > 0 {
            musicPlayer.playbackTime = clamped * musicSongDuration
        }
    }

    func endScrub() {
        isScrubbing = false
        if wasPlayingBeforeScrub {
            videoPlayer?.play()
            audioPlayer?.play()
            if isUsingMusicPlayer {
                Task { try? await musicPlayer.play() }
            }
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
        stopMusicPlayback()
        stopFallbackTimer()
        playbackProgress = 0
    }

    // MARK: - Tags

    private let tagRepo: TagRepository = resolve()

    func loadTagsForCurrentMix() {
        tagsForCurrentMix = currentMix.tags
    }

    func loadAllTags() {
        Task {
            do {
                allTags = try await tagRepo.listTags()
            } catch {}
        }
    }

    func toggleTag(_ tag: Tag) {
        let mixId = currentMix.id
        let isOn = tagsForCurrentMix.contains { $0.id == tag.id }
        if isOn {
            tagsForCurrentMix.removeAll { $0.id == tag.id }
        } else {
            tagsForCurrentMix.append(tag)
        }
        let newIds = Set(tagsForCurrentMix.map(\.id))
        Task {
            try? await tagRepo.setTagsForMix(mixId: mixId, tagIds: newIds)
            if let i = mixes.firstIndex(where: { $0.id == mixId }) {
                mixes[i].tags = tagsForCurrentMix
            }
        }
    }

    func createAndAddTag(name: String) {
        Task {
            do {
                let tag = try await tagRepo.createTag(name: name)
                allTags.append(tag)
                allTags.sort { $0.name < $1.name }
                toggleTag(tag)
            } catch {}
        }
    }

    /// Reload tags from Supabase for current mix (after editing)
    func reloadTagsFromRemote() {
        let mixId = currentMix.id
        Task {
            do {
                let tagIds = try await tagRepo.getTagIdsForMix(mixId: mixId)
                let fetched = try await tagRepo.listTags()
                allTags = fetched
                let tagIdSet = Set(tagIds)
                let tags = fetched.filter { tagIdSet.contains($0.id) }
                if let i = mixes.firstIndex(where: { $0.id == mixId }) {
                    mixes[i].tags = tags
                }
                if currentMix.id == mixId {
                    tagsForCurrentMix = tags
                }
            } catch {}
        }
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

    func saveTitle(_ text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String? = trimmed.isEmpty ? nil : trimmed
        do {
            let updated = try await repo.updateTitle(id: currentMix.id, title: title)
            if let index = mixes.firstIndex(where: { $0.id == updated.id }) {
                mixes[index] = updated
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Caption

    func saveCaption(_ text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let caption: String? = trimmed.isEmpty ? nil : trimmed
        do {
            let updated = try await repo.updateCaption(id: currentMix.id, caption: caption)
            if let index = mixes.firstIndex(where: { $0.id == updated.id }) {
                mixes[index] = updated
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Delete

    private let repo: MixRepository = resolve()

    func deleteCurrentMix() async -> Bool {
        do {
            try await repo.deleteMix(id: currentMix.id)
            return true
        } catch {
            return false
        }
    }
}
