import AVFoundation
import MediaPlayer
import Observation
import UIKit

struct AudioTrack: Identifiable, Sendable {
    let id: String
    let title: String
    let artist: String
    let url: URL
}

@Observable
@MainActor
final class AudioPlaybackCoordinator: NSObject, AVAudioPlayerDelegate {

    // MARK: - Observable State

    private(set) var isPlaying = false
    private(set) var currentTrackIndex = 0
    private(set) var elapsedTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var queue: [AudioTrack] = []
    private(set) var isMuted = false
    var isLooping = false

    var currentTrack: AudioTrack? {
        guard !queue.isEmpty, queue.indices.contains(currentTrackIndex) else { return nil }
        return queue[currentTrackIndex]
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return elapsedTime / duration
    }

    // MARK: - Private

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var commandTargets: [Any] = []
    private var placeholderArtwork: MPMediaItemArtwork?

    // MARK: - Queue from Mixes

    /// Extracts the playable audio URL from a Mix.
    /// Every mix should have audio (silence placeholder at minimum via audioUrl).
    static func audioURL(for mix: Mix) -> URL? {
        guard let urlString = mix.audioUrl, let url = URL(string: urlString) else { return nil }
        return url
    }

    /// Build a queue from an array of mixes, filtering to only those with playable audio.
    static func tracks(from mixes: [Mix]) -> [AudioTrack] {
        mixes.compactMap { mix in
            guard let url = audioURL(for: mix) else { return nil }
            let title = mix.title ?? mix.type.rawValue.capitalized
            return AudioTrack(
                id: mix.id.uuidString,
                title: title,
                artist: mix.tags.first?.name ?? mix.type.rawValue.capitalized,
                url: url
            )
        }
    }

    /// Build a queue from mixes without auto-playing. Call play() separately.
    func loadQueue(_ mixes: [Mix], startingAt mixId: UUID? = nil) {
        let tracks = Self.tracks(from: mixes)
        guard !tracks.isEmpty else { return }
        queue = tracks

        if let mixId, let idx = tracks.firstIndex(where: { $0.id == mixId.uuidString }) {
            currentTrackIndex = idx
        } else {
            currentTrackIndex = 0
        }

        // Reset state without starting playback
        player?.stop()
        player = nil
        stopTimer()
        isPlaying = false
        elapsedTime = 0
        duration = 0
    }

    // MARK: - Init

    override init() {
        super.init()
        placeholderArtwork = Self.makePlaceholderArtwork()
        configureAudioSession()
        configureRemoteCommands()
        observeInterruptions()
        observeForeground()
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
        } catch {
            print("[AudioPlaybackCoordinator] Failed to set audio session category: \(error)")
        }
    }

    private func activateSession() {
        // Re-assert category in case another view changed it (e.g. .mixWithOthers)
        configureAudioSession()
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[AudioPlaybackCoordinator] Failed to activate audio session: \(error)")
        }
    }

    private func deactivateSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("[AudioPlaybackCoordinator] Failed to deactivate audio session: \(error)")
        }
    }

    // MARK: - Remote Commands

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        let playTarget = center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.playCommand.isEnabled = true
        commandTargets.append(playTarget)

        let pauseTarget = center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.pauseCommand.isEnabled = true
        commandTargets.append(pauseTarget)

        let toggleTarget = center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.togglePlayPauseCommand.isEnabled = true
        commandTargets.append(toggleTarget)

        let nextTarget = center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.nextTrackCommand.isEnabled = true
        commandTargets.append(nextTarget)

        let prevTarget = center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.previousTrackCommand.isEnabled = true
        commandTargets.append(prevTarget)

        let scrubTarget = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in self?.seek(to: posEvent.positionTime) }
            return .success
        }
        center.changePlaybackPositionCommand.isEnabled = true
        commandTargets.append(scrubTarget)
    }

    // MARK: - Interruption Handling

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

            if type == .ended {
                let options = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                if AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                    Task { @MainActor in
                        self?.activateSession()
                        self?.resume()
                    }
                }
            }
        }
    }

    private func observeForeground() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard self?.isPlaying == true else { return }
                self?.activateSession()
            }
        }
    }

    // MARK: - Playback Controls

    func play() {
        guard !queue.isEmpty else { return }
        startPlayback()
    }

    func resume() {
        guard let player else { return }
        activateSession()
        player.play()
        isPlaying = true
        startTimer()
        updateNowPlayingRate(playing: true)
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
        updateNowPlayingRate(playing: false)
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        elapsedTime = 0
        duration = 0
        queue = []
        stopTimer()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        deactivateSession()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else if player != nil {
            resume()
        } else {
            play()
        }
    }

    func next() {
        guard !queue.isEmpty else { return }
        currentTrackIndex = (currentTrackIndex + 1) % queue.count
        startPlayback()
    }

    func previous() {
        guard !queue.isEmpty else { return }
        if elapsedTime > 3 {
            seek(to: 0)
        } else {
            currentTrackIndex = (currentTrackIndex - 1 + queue.count) % queue.count
            startPlayback()
        }
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = time
        elapsedTime = time
        updateNowPlayingElapsed()
    }

    /// Jump to a track by its ID (mix UUID string). Starts playback if found.
    func jumpToTrack(id: String) {
        guard let idx = queue.firstIndex(where: { $0.id == id }) else { return }
        guard idx != currentTrackIndex else { return }
        currentTrackIndex = idx
        startPlayback()
    }

    /// Set mute state and update player volume.
    func setMuted(_ muted: Bool) {
        isMuted = muted
        player?.volume = muted ? 0 : 1
    }

    // MARK: - Internal Playback

    private func startPlayback() {
        guard let track = currentTrack else { return }

        player?.stop()
        player = nil
        stopTimer()
        activateSession()

        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: track.url)
            audioPlayer.delegate = self
            audioPlayer.volume = isMuted ? 0 : 1
            audioPlayer.prepareToPlay()

            self.player = audioPlayer
            duration = audioPlayer.duration
            elapsedTime = 0

            audioPlayer.play()
            isPlaying = true
            startTimer()

            updateNowPlayingFull()
        } catch {
            print("[AudioPlaybackCoordinator] Failed to load \(track.title): \(error)")
        }
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.elapsedTime = player.currentTime
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if flag {
                if self.isLooping {
                    self.startPlayback()
                } else {
                    self.next()
                }
            } else {
                self.isPlaying = false
                self.stopTimer()
            }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            print("[AudioPlaybackCoordinator] Decode error: \(error?.localizedDescription ?? "Unknown")")
            self.isPlaying = false
            self.stopTimer()
        }
    }

    // MARK: - Now Playing Info

    private func updateNowPlayingFull() {
        guard let track = currentTrack else { return }

        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = track.title
        info[MPMediaItemPropertyArtist] = track.artist
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        if let artwork = placeholderArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingRate(playing: Bool) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player?.currentTime ?? elapsedTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingElapsed() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedTime
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Placeholder Artwork

    private static func makePlaceholderArtwork() -> MPMediaItemArtwork? {
        let size = CGSize(width: 600, height: 600)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.systemIndigo.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let config = UIImage.SymbolConfiguration(pointSize: 200, weight: .light)
            if let symbol = UIImage(systemName: "waveform", withConfiguration: config)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                let symbolSize = symbol.size
                let origin = CGPoint(
                    x: (size.width - symbolSize.width) / 2,
                    y: (size.height - symbolSize.height) / 2
                )
                symbol.draw(at: origin)
            }
        }

        return MPMediaItemArtwork(boundsSize: size) { [image] _ in image }
    }
}
