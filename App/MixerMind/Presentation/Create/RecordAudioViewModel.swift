import SwiftUI
import AVFoundation

@Observable @MainActor
final class RecordAudioViewModel {

    // MARK: - State

    enum RecordingState {
        case idle
        case recording
        case paused
        case stopped
    }

    var state: RecordingState = .idle
    var elapsedTime: TimeInterval = 0
    var audioLevel: Float = 0
    var errorMessage: String?
    var permissionDenied = false

    // MARK: - Private

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var meteringTimer: Timer?
    private var recordingURL: URL?

    // MARK: - Computed

    var formattedTime: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        let tenths = Int((elapsedTime.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }

    var canAccept: Bool { state == .stopped }
    var canPause: Bool { state == .recording }
    var canResume: Bool { state == .paused }
    var canStop: Bool { state == .recording || state == .paused }
    var canRecord: Bool { state == .idle }
    var canDiscard: Bool { state == .stopped || state == .paused }

    // MARK: - Permission

    func requestPermission() async {
        if AVAudioApplication.shared.recordPermission == .denied {
            permissionDenied = true
            return
        }

        if AVAudioApplication.shared.recordPermission == .undetermined {
            let granted = await AVAudioApplication.requestRecordPermission()
            if !granted {
                permissionDenied = true
                return
            }
        }

        permissionDenied = false
    }

    // MARK: - Audio Session

    private func configureSessionForRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            errorMessage = "Failed to configure audio session"
        }
    }

    private func restoreSessionForPlayback() {
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
            let audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder.isMeteringEnabled = true
            audioRecorder.prepareToRecord()
            audioRecorder.record()
            recorder = audioRecorder
            state = .recording
            elapsedTime = 0
            startTimers()
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    func pauseRecording() {
        recorder?.pause()
        state = .paused
        stopTimers()
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
        restoreSessionForPlayback()
    }

    func discardAndRestart() {
        cleanup()
        state = .idle
        elapsedTime = 0
        audioLevel = 0
    }

    // MARK: - Data Extraction

    func getRecordingData() -> (Data, String)? {
        guard let url = recordingURL,
              let data = try? Data(contentsOf: url) else {
            errorMessage = "Failed to read recording"
            return nil
        }

        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
            .replacingOccurrences(of: ":", with: "-")
        let fileName = "Recording \(timestamp).m4a"

        return (data, fileName)
    }

    // MARK: - Timers

    private func startTimers() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .recording else { return }
                self.elapsedTime = self.recorder?.currentTime ?? self.elapsedTime
            }
        }

        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .recording else { return }
                self.recorder?.updateMeters()
                let power = self.recorder?.averagePower(forChannel: 0) ?? -160
                let minDb: Float = -60
                let clampedPower = max(power, minDb)
                self.audioLevel = (clampedPower - minDb) / (0 - minDb)
            }
        }
    }

    private func stopTimers() {
        timer?.invalidate()
        timer = nil
        meteringTimer?.invalidate()
        meteringTimer = nil
    }

    // MARK: - Cleanup

    func cleanup() {
        stopTimers()
        recorder?.stop()
        recorder = nil
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }
        restoreSessionForPlayback()
    }
}
