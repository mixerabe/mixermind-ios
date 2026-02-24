import SwiftUI

struct RecordAudioView: View {
    var onRecordingAccepted: (Data, String) -> Void
    @State private var viewModel = RecordAudioViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    timerDisplay

                    Spacer()
                        .frame(height: 48)

                    audioLevelIndicator

                    Spacer()

                    controlBar
                        .padding(.bottom, 60)
                }
            }
            .navigationTitle("Record Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        viewModel.cleanup()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .task {
            await viewModel.requestPermission()
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .alert("Microphone Access Required", isPresented: $viewModel.permissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { dismiss() }
        } message: {
            Text("Allow microphone access in Settings to record audio.")
        }
    }

    // MARK: - Timer Display

    private var timerDisplay: some View {
        VStack(spacing: 8) {
            Text(viewModel.formattedTime)
                .font(.system(size: 56, weight: .thin, design: .monospaced))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.linear(duration: 0.1), value: viewModel.elapsedTime)

            Text(stateLabel)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
                .tracking(1.5)
        }
    }

    private var stateLabel: String {
        switch viewModel.state {
        case .idle: return "Ready"
        case .recording: return "Recording"
        case .paused: return "Paused"
        case .stopped: return "Review"
        }
    }

    // MARK: - Audio Level Indicator

    private var audioLevelIndicator: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.red.opacity(0.3), .red.opacity(0)],
                        center: .center,
                        startRadius: 40,
                        endRadius: 80
                    )
                )
                .frame(width: 160, height: 160)
                .scaleEffect(viewModel.state == .recording
                    ? 1.0 + CGFloat(viewModel.audioLevel) * 0.5
                    : 1.0)
                .opacity(viewModel.state == .recording ? 1 : 0.3)
                .animation(.easeOut(duration: 0.08), value: viewModel.audioLevel)

            Circle()
                .fill(.red.opacity(viewModel.state == .recording ? 0.8 : 0.4))
                .frame(width: 80, height: 80)
                .scaleEffect(viewModel.state == .recording
                    ? 1.0 + CGFloat(viewModel.audioLevel) * 0.2
                    : 1.0)
                .animation(.easeOut(duration: 0.08), value: viewModel.audioLevel)
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: 0) {
            // Left: Discard / Re-record
            Group {
                if viewModel.canDiscard && viewModel.state == .paused {
                    controlButton("trash", label: "Discard") {
                        viewModel.discardAndRestart()
                    }
                } else if viewModel.state == .stopped {
                    controlButton("arrow.counterclockwise", label: "Re-record") {
                        viewModel.discardAndRestart()
                    }
                } else {
                    Color.clear.frame(width: 70, height: 70)
                }
            }
            .frame(maxWidth: .infinity)

            // Center: Record / Pause / Resume
            Group {
                switch viewModel.state {
                case .idle:
                    recordButton {
                        viewModel.startRecording()
                    }
                case .recording:
                    pauseButton {
                        viewModel.pauseRecording()
                    }
                case .paused:
                    recordButton {
                        viewModel.resumeRecording()
                    }
                case .stopped:
                    Color.clear.frame(width: 70, height: 70)
                }
            }
            .frame(maxWidth: .infinity)

            // Right: Stop / Accept
            Group {
                if viewModel.canStop {
                    controlButton("stop.fill", label: "Done") {
                        viewModel.stopRecording()
                    }
                } else if viewModel.state == .stopped {
                    acceptButton {
                        acceptRecording()
                    }
                } else {
                    Color.clear.frame(width: 70, height: 70)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Button Helpers

    private func recordButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 70, height: 70)
                Circle()
                    .fill(.red)
                    .frame(width: 58, height: 58)
            }
        }
    }

    private func pauseButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 70, height: 70)
                Image(systemName: "pause.fill")
                    .font(.title)
                    .foregroundStyle(.white)
            }
        }
    }

    private func controlButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .glassEffect(in: .circle)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
    }

    private func acceptButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .tint(.green)
                    .glassEffect(in: .circle)
                Text("Use")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Accept

    private func acceptRecording() {
        guard let (data, fileName) = viewModel.getRecordingData() else { return }
        viewModel.cleanup()
        onRecordingAccepted(data, fileName)
        dismiss()
    }
}
