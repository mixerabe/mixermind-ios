import SwiftUI
import SwiftData
import AVFoundation

@Observable @MainActor
final class MixViewerViewModel {
    var mixes: [Mix]
    var scrolledID: UUID?
    private(set) var activeID: UUID?

    var isScrubbing = false
    var tagsForCurrentMix: [Tag] = []
    var allTags: [Tag] = []
    var isAutoScroll = false

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

    init(mixes: [Mix], startIndex: Int) {
        self.mixes = mixes
        if mixes.indices.contains(startIndex) {
            let id = mixes[startIndex].id
            self.scrolledID = id
            self.activeID = id
        }
    }

    // MARK: - Lifecycle

    func onAppear() {
        guard !mixes.isEmpty else { return }
        hasAppeared = true
        coordinator.loadQueue(mixes, startingAt: activeID)
        coordinator.isLooping = !isAutoScroll
        coordinator.play()
        loadCurrentMix()
    }

    func onDisappear() {
        stopVideoPlayback()
    }

    func onScrollChanged() {
        guard let scrolledID, scrolledID != activeID else { return }
        stopVideoPlayback()
        activeID = scrolledID
        videoProgress = 0
        pendingLoad = true
    }

    func onScrollIdle() {
        guard pendingLoad else { return }
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
        coordinator.resume()
        videoPlayer?.play()
    }

    // MARK: - Coordinator Sync

    /// Called when coordinator's currentTrackIndex changes externally (lock screen, track finish).
    /// Scrolls the viewer to match and loads video.
    func syncFromCoordinator() {
        guard let track = coordinator.currentTrack,
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
                audioUrl: mixes[index].audioUrl,
                screenshotUrl: mixes[index].screenshotUrl,
                previewScaleX: mixes[index].previewScaleX,
                previewScaleY: mixes[index].previewScaleY
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
                    local.localAudioPath, local.localScreenshotPath,
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
