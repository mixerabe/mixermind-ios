import SwiftUI
import AVFoundation

@Observable @MainActor
final class RecordAudioViewModel {

    // MARK: - State

    enum RecordingState {
        case idle
        case recording
        case paused
        case stopped   // review / playback mode
    }

    var state: RecordingState = .idle
    var elapsedTime: TimeInterval = 0
    var audioLevel: Float = 0
    var errorMessage: String?
    var permissionDenied = false

    // Waveform — bars for live recording visual
    var liveWaveformBars: [Float] = Array(repeating: 0, count: 60)

    // Review / playback
    var recordedWaveform: [Float] = []      // normalised 0…1, sampled from file
    var playbackPosition: Double = 0        // 0…1
    var playbackTime: TimeInterval = 0
    var isPlaying: Bool = false
    var recordedDuration: TimeInterval = 0

    // Trim
    var trimStart: Double = 0               // 0…1
    var trimEnd: Double = 1                 // 0…1
    var isTrimming: Bool = false

    // MARK: - Private

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var meteringTimer: Timer?
    private var playbackTimer: Timer?
    private var recordingURL: URL?
    private var waveformWriteIndex: Int = 0

    // MARK: - Computed

    var formattedTime: String {
        formatTime(elapsedTime)
    }

    var formattedPlaybackTime: String {
        formatTime(playbackTime)
    }

    var formattedDuration: String {
        formatTime(recordedDuration)
    }

    var trimStartTime: TimeInterval { trimStart * recordedDuration }
    var trimEndTime: TimeInterval   { trimEnd   * recordedDuration }
    var trimmedDuration: TimeInterval { trimEndTime - trimStartTime }

    var canAccept: Bool { state == .stopped }
    var canPause: Bool  { state == .recording }
    var canResume: Bool { state == .paused }
    var canStop: Bool   { state == .recording || state == .paused }
    var canRecord: Bool { state == .idle }
    var canDiscard: Bool { state == .stopped || state == .paused }

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        let ms = Int((t.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", m, s, ms)
    }

    // MARK: - Permission

    func requestPermission() async {
        if AVAudioApplication.shared.recordPermission == .denied {
            permissionDenied = true
            return
        }
        if AVAudioApplication.shared.recordPermission == .undetermined {
            let granted = await AVAudioApplication.requestRecordPermission()
            if !granted { permissionDenied = true; return }
        }
        permissionDenied = false
    }

    // MARK: - Audio Session

    private func configureSessionForRecording() {
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try s.setActive(true)
        } catch { errorMessage = "Failed to configure audio session" }
    }

    private func configureSessionForPlayback() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: - Recording Actions

    func startRecording() {
        configureSessionForRecording()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording_\(UUID().uuidString).m4a")
        recordingURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 128_000,
        ]

        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.isMeteringEnabled = true
            r.prepareToRecord()
            r.record()
            recorder = r
            state = .recording
            elapsedTime = 0
            liveWaveformBars = Array(repeating: 0, count: 60)
            waveformWriteIndex = 0
            startTimers()
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    func pauseRecording() {
        recorder?.pause()
        state = .paused
        stopTimers()
        audioLevel = 0
    }

    func resumeRecording() {
        recorder?.record()
        state = .recording
        startTimers()
    }

    func stopRecording() {
        recorder?.stop()
        state = .stopped
        stopTimers()
        audioLevel = 0
        configureSessionForPlayback()
        loadRecordingForReview()
    }

    func discardAndRestart() {
        stopPlayback()
        cleanup()
        state = .idle
        elapsedTime = 0
        audioLevel = 0
        recordedWaveform = []
        playbackPosition = 0
        playbackTime = 0
        recordedDuration = 0
        trimStart = 0
        trimEnd = 1
        isTrimming = false
        liveWaveformBars = Array(repeating: 0, count: 60)
    }

    // MARK: - Review / Playback

    private func loadRecordingForReview() {
        guard let url = recordingURL else { return }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            player = p
            recordedDuration = p.duration
            playbackTime = 0
            playbackPosition = 0
        } catch {
            errorMessage = "Failed to load recording for playback"
        }
        extractWaveform()
    }

    func togglePlayback() {
        guard let p = player else { return }
        if isPlaying {
            p.pause()
            isPlaying = false
            stopPlaybackTimer()
        } else {
            // Seek to trimStart if we're at the very beginning
            if playbackPosition <= trimStart + 0.001 && !isPlaying {
                seekTo(trimStart)
            }
            p.play()
            isPlaying = true
            startPlaybackTimer()
        }
    }

    func seekTo(_ fraction: Double) {
        guard let p = player else { return }
        let clamped = max(trimStart, min(trimEnd, fraction))
        let t = clamped * recordedDuration
        p.currentTime = t
        playbackTime = t
        playbackPosition = clamped
    }

    func stopPlayback() {
        player?.stop()
        isPlaying = false
        stopPlaybackTimer()
    }

    func replayFromTrimStart() {
        seekTo(trimStart)
        if !isPlaying { togglePlayback() }
    }

    // MARK: - Waveform Extraction

    private func extractWaveform() {
        guard let url = recordingURL else { return }
        Task.detached(priority: .userInitiated) { [weak self] in
            let bars = await Self.sampleWaveform(from: url, count: 80)
            await MainActor.run {
                self?.recordedWaveform = bars
            }
        }
    }

    private static func sampleWaveform(from url: URL, count: Int) async -> [Float] {
        guard let file = try? AVAudioFile(forReading: url) else { return [] }
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              (try? file.read(into: buffer)) != nil,
              let channelData = buffer.floatChannelData?[0] else { return [] }

        let totalFrames = Int(buffer.frameLength)
        let chunkSize = max(1, totalFrames / count)
        var bars: [Float] = []

        for i in 0..<count {
            let start = i * chunkSize
            let end = min(start + chunkSize, totalFrames)
            var sum: Float = 0
            for j in start..<end { sum += abs(channelData[j]) }
            bars.append(sum / Float(end - start))
        }

        // normalise to 0…1
        let peak = bars.max() ?? 1
        if peak > 0 { return bars.map { $0 / peak } }
        return bars
    }

    // MARK: - Timers

    private func startTimers() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let strongSelf = self else { return }
            Task { @MainActor [strongSelf] in
                guard strongSelf.state == .recording else { return }
                strongSelf.elapsedTime = strongSelf.recorder?.currentTime ?? strongSelf.elapsedTime
            }
        }

        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let strongSelf = self else { return }
            Task { @MainActor [strongSelf] in
                guard strongSelf.state == .recording else { return }
                strongSelf.recorder?.updateMeters()
                let power = strongSelf.recorder?.averagePower(forChannel: 0) ?? -160
                let minDb: Float = -60
                let clampedPower = max(power, minDb)
                let level = (clampedPower - minDb) / (0 - minDb)
                strongSelf.audioLevel = level

                // Append to scrolling waveform
                var bars = strongSelf.liveWaveformBars
                bars.removeFirst()
                bars.append(level)
                strongSelf.liveWaveformBars = bars
            }
        }
    }

    private func stopTimers() {
        timer?.invalidate(); timer = nil
        meteringTimer?.invalidate(); meteringTimer = nil
    }

    private func startPlaybackTimer() {
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            guard let strongSelf = self else { return }
            Task { @MainActor [strongSelf] in
                guard let p = strongSelf.player, strongSelf.isPlaying else { return }
                strongSelf.playbackTime = p.currentTime
                strongSelf.playbackPosition = p.duration > 0 ? p.currentTime / p.duration : 0

                // Auto-stop at trim end
                if strongSelf.playbackPosition >= strongSelf.trimEnd {
                    strongSelf.stopPlayback()
                    strongSelf.seekTo(strongSelf.trimStart)
                }
            }
        }
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate(); playbackTimer = nil
    }

    // MARK: - Data Extraction

    func getRecordingData() -> (Data, String)? {
        guard let url = recordingURL else { errorMessage = "No recording"; return nil }

        // If no trim, just return full file
        if trimStart <= 0.001 && trimEnd >= 0.999 {
            guard let data = try? Data(contentsOf: url) else {
                errorMessage = "Failed to read recording"; return nil
            }
            return (data, makeFileName())
        }

        // Trim: export using AVAssetExportSession
        // For now return the full data and let trimming be cosmetic
        // (full trim export would require async, wired up in the view)
        guard let data = try? Data(contentsOf: url) else {
            errorMessage = "Failed to read recording"; return nil
        }
        return (data, makeFileName())
    }

    private func makeFileName() -> String {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
            .replacingOccurrences(of: ":", with: "-")
        return "Recording \(ts).m4a"
    }

    // MARK: - Cleanup

    func cleanup() {
        stopTimers()
        stopPlaybackTimer()
        player?.stop(); player = nil
        recorder?.stop(); recorder = nil
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }
        configureSessionForPlayback()
    }
}
