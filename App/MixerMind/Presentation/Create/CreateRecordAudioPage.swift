import SwiftUI

struct CreateRecordAudioPage: View {
    @State private var createViewModel = CreateMixViewModel()
    @State private var recorderViewModel = RecordAudioViewModel()
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isSaving {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(createViewModel.isGeneratingTitle ? "Generating title..." : "Saving...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 0) {
                    Spacer()

                    timerDisplay

                    Spacer()
                        .frame(height: 48)

                    audioLevelIndicator

                    Spacer()

                    if recorderViewModel.state == .stopped {
                        autoTitleToggle
                            .padding(.horizontal, 32)
                            .padding(.bottom, 20)
                    }

                    controlBar
                        .padding(.bottom, 60)
                }
            }

            if let error = createViewModel.errorMessage {
                VStack {
                    Spacer()
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding()
                }
            }
        }
        .navigationTitle("Record Audio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear { createViewModel.modelContext = modelContext }
        .task {
            await recorderViewModel.requestPermission()
        }
        .onDisappear {
            recorderViewModel.cleanup()
        }
        .alert("Microphone Access Required", isPresented: $recorderViewModel.permissionDenied) {
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
            Text(recorderViewModel.formattedTime)
                .font(.system(size: 56, weight: .thin, design: .monospaced))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.linear(duration: 0.1), value: recorderViewModel.elapsedTime)

            Text(stateLabel)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
                .tracking(1.5)
        }
    }

    private var stateLabel: String {
        switch recorderViewModel.state {
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
                .scaleEffect(recorderViewModel.state == .recording
                    ? 1.0 + CGFloat(recorderViewModel.audioLevel) * 0.5
                    : 1.0)
                .opacity(recorderViewModel.state == .recording ? 1 : 0.3)
                .animation(.easeOut(duration: 0.08), value: recorderViewModel.audioLevel)

            Circle()
                .fill(.red.opacity(recorderViewModel.state == .recording ? 0.8 : 0.4))
                .frame(width: 80, height: 80)
                .scaleEffect(recorderViewModel.state == .recording
                    ? 1.0 + CGFloat(recorderViewModel.audioLevel) * 0.2
                    : 1.0)
                .animation(.easeOut(duration: 0.08), value: recorderViewModel.audioLevel)
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: 0) {
            // Left: Discard / Re-record
            Group {
                if recorderViewModel.canDiscard && recorderViewModel.state == .paused {
                    controlButton("trash", label: "Discard") {
                        recorderViewModel.discardAndRestart()
                    }
                } else if recorderViewModel.state == .stopped {
                    controlButton("arrow.counterclockwise", label: "Re-record") {
                        recorderViewModel.discardAndRestart()
                    }
                } else {
                    Color.clear.frame(width: 70, height: 70)
                }
            }
            .frame(maxWidth: .infinity)

            // Center: Record / Pause / Resume
            Group {
                switch recorderViewModel.state {
                case .idle:
                    recordButton {
                        recorderViewModel.startRecording()
                    }
                case .recording:
                    pauseButton {
                        recorderViewModel.pauseRecording()
                    }
                case .paused:
                    recordButton {
                        recorderViewModel.resumeRecording()
                    }
                case .stopped:
                    Color.clear.frame(width: 70, height: 70)
                }
            }
            .frame(maxWidth: .infinity)

            // Right: Stop / Accept
            Group {
                if recorderViewModel.canStop {
                    controlButton("stop.fill", label: "Done") {
                        recorderViewModel.stopRecording()
                    }
                } else if recorderViewModel.state == .stopped {
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

    // MARK: - Auto Title Toggle

    private var autoTitleToggle: some View {
        Toggle(isOn: $createViewModel.autoCreateTitle) {
            Label("Auto-create title", systemImage: "sparkles")
                .font(.subheadline)
                .foregroundStyle(.white)
        }
        .tint(.accentColor)
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
            .contentShape(.circle)
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
            .contentShape(.circle)
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
            .contentShape(Rectangle())
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Accept & Save

    private func acceptRecording() {
        guard let (data, fileName) = recorderViewModel.getRecordingData() else { return }
        recorderViewModel.cleanup()
        createViewModel.setRecordedAudio(data: data, fileName: fileName)
        isSaving = true
        Task {
            let success = await createViewModel.saveMix()
            if success {
                dismiss()
            } else {
                isSaving = false
            }
        }
    }
}
