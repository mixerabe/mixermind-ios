import SwiftUI
import AVFoundation

// MARK: - Main Page

struct CreateRecordAudioPage: View {
    @State private var createViewModel = CreateMixViewModel()
    @State private var vm = RecordAudioViewModel()
    @State private var isSaving = false
    @State private var isEditingTitle = false
    @State private var titleDraft = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            backgroundLayer

            if isSaving {
                savingOverlay
            } else {
                mainContent
            }

            if let error = createViewModel.errorMessage {
                VStack {
                    Spacer()
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 100)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle("placeholder")
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                titleChipButton
            }
        }
        .sheet(isPresented: $isEditingTitle) {
            RecordTitleEditSheet(
                title: $titleDraft,
                onDone: {
                    createViewModel.title = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    isEditingTitle = false
                },
                onCancel: {
                    titleDraft = createViewModel.title
                    isEditingTitle = false
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled()
        }
        .onAppear { createViewModel.modelContext = modelContext }
        .task { await vm.requestPermission() }
        .onDisappear { vm.cleanup() }
        .alert("Microphone Access Required", isPresented: $vm.permissionDenied) {
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

    // MARK: - Title Chip Button (navbar center)

    private var titleChipButton: some View {
        Button {
            titleDraft = createViewModel.title
            isEditingTitle = true
        } label: {
            Text(createViewModel.title.isEmpty ? "Add title" : createViewModel.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(createViewModel.title.isEmpty ? .white.opacity(0.4) : .white)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(in: .capsule)
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Subtle coloured glow that changes with state
            let glowColor: Color = {
                switch vm.state {
                case .idle:      return .white.opacity(0.03)
                case .recording: return .red.opacity(0.08 + Double(vm.audioLevel) * 0.07)
                case .paused:    return .orange.opacity(0.06)
                case .stopped:   return .blue.opacity(0.07)
                }
            }()

            RadialGradient(
                colors: [glowColor, .clear],
                center: .center,
                startRadius: 0,
                endRadius: 400
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.4), value: vm.state)
        }
    }

    // MARK: - Custom Top Bar

    private var customTopBar: some View {
        HStack(spacing: 0) {
            // Left: back button
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .glassEffect(in: .circle)

            Spacer()

            // Center: title chip
            titleChipButton

            Spacer()

            // Right: keep symmetry with left back button
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            Spacer()

            // Central visualizer zone — transitions between states
            ZStack {
                if vm.state == .stopped {
                    ReviewWaveformView(vm: vm)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    LiveRecordingVisual(vm: vm)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .animation(.spring(duration: 0.45), value: vm.state == .stopped)
            .frame(height: 280)

            Spacer()
                .frame(height: 16)

            // Time display
            timeDisplay
                .padding(.bottom, 8)

            Spacer()
                .frame(maxHeight: 24)

            controlBar
                .padding(.bottom, 56)
        }
        .animation(.spring(duration: 0.35), value: vm.state)
    }

    // MARK: - Saving Overlay

    private var savingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Saving…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Time Display

    private var timeDisplay: some View {
        VStack(spacing: 6) {
            // Show playback time in review, elapsed in recording
            if vm.state == .stopped {
                HStack(spacing: 4) {
                    Text(vm.formattedPlaybackTime)
                        .font(.system(size: 42, weight: .thin, design: .monospaced))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.linear(duration: 0.05), value: vm.playbackTime)
                    Text("/")
                        .font(.system(size: 28, weight: .thin, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                    Text(vm.formattedDuration)
                        .font(.system(size: 28, weight: .thin, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .contentTransition(.numericText())
                }
            } else {
                Text(vm.formattedTime)
                    .font(.system(size: 56, weight: .thin, design: .monospaced))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.linear(duration: 0.1), value: vm.elapsedTime)
            }

            stateTagView
        }
    }

    private var stateTagView: some View {
        HStack(spacing: 6) {
            if vm.state == .recording {
                Circle()
                    .fill(.red)
                    .frame(width: 7, height: 7)
                    .modifier(BlinkingModifier())
            } else if vm.state == .paused {
                Image(systemName: "pause.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
            } else if vm.state == .stopped {
                Image(systemName: "waveform")
                    .font(.system(size: 9))
                    .foregroundStyle(.blue.opacity(0.8))
            }

            Text(stateLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(stateLabelColor)
                .textCase(.uppercase)
                .tracking(2)
        }
        .animation(.default, value: vm.state)
    }

    private var stateLabel: String {
        switch vm.state {
        case .idle:      return "Ready"
        case .recording: return "Recording"
        case .paused:    return "Paused"
        case .stopped:   return "Review"
        }
    }

    private var stateLabelColor: Color {
        switch vm.state {
        case .idle:      return .white.opacity(0.4)
        case .recording: return .red.opacity(0.9)
        case .paused:    return .orange.opacity(0.8)
        case .stopped:   return .blue.opacity(0.8)
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        VStack(spacing: 0) {
            if vm.state == .stopped {
                reviewControlBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                recordingControlBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: vm.state == .stopped)
    }

    // Recording controls: [Discard|Trash] [Record|Pause|Resume] [Stop]
    private var recordingControlBar: some View {
        HStack(alignment: .center, spacing: 0) {
            // Left
            Group {
                if vm.canDiscard && vm.state == .paused {
                    auxButton("trash", label: "Discard", color: .red.opacity(0.8)) {
                        withAnimation { vm.discardAndRestart() }
                    }
                } else {
                    Color.clear.frame(width: 64, height: 64)
                }
            }
            .frame(maxWidth: .infinity)

            // Center
            Group {
                switch vm.state {
                case .idle:
                    bigRecordButton { vm.startRecording() }
                case .recording:
                    bigPauseButton { vm.pauseRecording() }
                case .paused:
                    bigResumeButton { vm.resumeRecording() }
                case .stopped:
                    EmptyView()
                }
            }

            // Right
            Group {
                if vm.canStop {
                    auxButton("stop.fill", label: "Stop", color: .white) {
                        vm.stopRecording()
                    }
                } else {
                    Color.clear.frame(width: 64, height: 64)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
    }

    // Review controls: [Re-record] [Play/Pause] [Use]
    private var reviewControlBar: some View {
        VStack(spacing: 24) {
            // Playback row
            HStack(alignment: .center, spacing: 0) {
                auxButton("arrow.counterclockwise", label: "Re-record", color: .white.opacity(0.7)) {
                    withAnimation { vm.discardAndRestart() }
                }
                .frame(maxWidth: .infinity)

                bigPlayButton {
                    vm.togglePlayback()
                }

                auxButton("checkmark", label: "Use", color: .green) {
                    acceptRecording()
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Big Buttons

    private func bigRecordButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(0.6), lineWidth: 3)
                    .frame(width: 80, height: 80)
                Circle()
                    .fill(.red)
                    .frame(width: 66, height: 66)
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private func bigPauseButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 80, height: 80)
                Circle()
                    .strokeBorder(.white.opacity(0.5), lineWidth: 2)
                    .frame(width: 80, height: 80)
                Image(systemName: "pause.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private func bigResumeButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(.orange.opacity(0.7), lineWidth: 3)
                    .frame(width: 80, height: 80)
                Circle()
                    .fill(.red.opacity(0.7))
                    .frame(width: 66, height: 66)
                Image(systemName: "mic.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private func bigPlayButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 80, height: 80)
                Circle()
                    .strokeBorder(.white.opacity(0.5), lineWidth: 2)
                    .frame(width: 80, height: 80)
                Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.default, value: vm.isPlaying)
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private func auxButton(_ icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 48, height: 48)
                    .background(color.opacity(0.1), in: Circle())
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(color.opacity(0.75))
                    .tracking(0.5)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Accept & Save

    private func acceptRecording() {
        guard let (data, fileName) = vm.getRecordingData() else { return }
        vm.stopPlayback()
        vm.cleanup()
        createViewModel.setRecordedAudio(data: data, fileName: fileName)
        isSaving = true
        Task {
            let success = await createViewModel.saveMix()
            if success { dismiss() } else { isSaving = false }
        }
    }
}

// MARK: - Record Title Edit Sheet

struct RecordTitleEditSheet: View {
    @Binding var title: String
    var onDone: () -> Void
    var onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                TextField("Add title", text: $title)
                    .focused($isFocused)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.medium))
                    .multilineTextAlignment(.center)
                    .submitLabel(.done)
                    .onSubmit { onDone() }
                    .onChange(of: title) { _, newValue in
                        if newValue.count > 60 {
                            title = String(newValue.prefix(60))
                        }
                    }
                    .padding(.horizontal, 32)
                Spacer()
            }
            .navigationTitle("Title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { onCancel() } label: {
                        Image(systemName: "xmark")
                            .fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { onDone() } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .onAppear { isFocused = true }
    }
}

// MARK: - Live Recording Visual

struct LiveRecordingVisual: View {
    var vm: RecordAudioViewModel

    var body: some View {
        VStack(spacing: 32) {
            // Scrolling waveform bars
            WaveformBarsView(
                bars: vm.liveWaveformBars,
                isActive: vm.state == .recording,
                activeColor: .red,
                inactiveColor: .white.opacity(0.15)
            )
            .frame(height: 100)
            .padding(.horizontal, 20)

            // Central mic orb
            MicOrbView(level: vm.audioLevel, state: vm.state)
        }
    }
}

// MARK: - Mic Orb

struct MicOrbView: View {
    var level: Float
    var state: RecordAudioViewModel.RecordingState

    private var isRecording: Bool { state == .recording }
    private var isPaused: Bool { state == .paused }

    var body: some View {
        ZStack {
            // Outer pulse ring
            Circle()
                .strokeBorder(
                    isRecording
                        ? .red.opacity(0.25 + Double(level) * 0.4)
                        : isPaused ? .orange.opacity(0.3) : .white.opacity(0.08),
                    lineWidth: 1.5
                )
                .frame(width: 120, height: 120)
                .scaleEffect(isRecording ? 1.0 + Double(level) * 0.25 : 1.0)
                .animation(.easeOut(duration: 0.07), value: level)

            // Mid glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: isRecording
                            ? [.red.opacity(0.35 + Double(level) * 0.25), .clear]
                            : isPaused
                                ? [.orange.opacity(0.2), .clear]
                                : [.white.opacity(0.05), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 50
                    )
                )
                .frame(width: 100, height: 100)
                .animation(.easeOut(duration: 0.07), value: level)
                .animation(.easeInOut(duration: 0.3), value: state)

            // Inner mic icon circle
            Circle()
                .fill(
                    isPaused
                        ? AnyShapeStyle(.orange.opacity(0.8))
                        : isRecording
                            ? AnyShapeStyle(.red.opacity(0.9))
                            : AnyShapeStyle(.white.opacity(0.15))
                )
                .frame(width: 64, height: 64)
                .scaleEffect(isRecording ? 1.0 + Double(level) * 0.12 : 1.0)
                .animation(.easeOut(duration: 0.06), value: level)
                .animation(.spring(duration: 0.3), value: state)

            Image(systemName: isPaused ? "pause.fill" : "mic.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .animation(.default, value: isPaused)
        }
    }
}

// MARK: - Waveform Bars (live recording)

struct WaveformBarsView: View {
    var bars: [Float]
    var isActive: Bool
    var activeColor: Color
    var inactiveColor: Color

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(bars.indices, id: \.self) { i in
                    // Idle: show a gentle random-ish static pattern using index
                    let idleH: CGFloat = 4 + CGFloat((i * 7 + 3) % 16)
                    let activeH = max(4, CGFloat(bars[i]) * geo.size.height)
                    let h = isActive ? activeH : idleH
                    Capsule()
                        .fill(barColor(index: i, value: bars[i]))
                        .frame(maxWidth: .infinity)
                        .frame(height: h)
                        .animation(isActive
                                   ? .easeOut(duration: 0.06)
                                   : .easeOut(duration: 0.3),
                                   value: bars[i])
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func barColor(index: Int, value: Float) -> Color {
        guard isActive else { return inactiveColor }
        let recency = Double(index) / Double(max(bars.count - 1, 1))
        return activeColor.opacity(0.3 + recency * 0.7)
    }
}

// MARK: - Review Waveform View

struct ReviewWaveformView: View {
    var vm: RecordAudioViewModel
    @State private var isDraggingScrubber = false
    @State private var dragScrubValue: Double = 0
    @State private var waveformWidth: CGFloat = 300

    // Trim drag state
    @State private var isDraggingTrimStart = false
    @State private var isDraggingTrimEnd = false

    var body: some View {
        VStack(spacing: 20) {
            // Static waveform + scrubber + trim
            ZStack(alignment: .leading) {
                waveformBackground
                playheadOverlay
                if vm.isTrimming { trimOverlay }
            }
            .frame(height: 120)
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
            .onGeometryChange(for: CGFloat.self) { $0.size.width - 40 } action: { waveformWidth = $0 }
            .gesture(scrubGesture)

            // Trim toggle button
            trimToggleRow
        }
    }

    // MARK: - Waveform Background

    private var waveformBackground: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let barCount = vm.recordedWaveform.count
            let barW: CGFloat = barCount > 0 ? (w - CGFloat(barCount - 1) * 2) / CGFloat(barCount) : 4
            let progress = vm.playbackPosition

            HStack(alignment: .center, spacing: 2) {
                ForEach(vm.recordedWaveform.indices, id: \.self) { i in
                    let fraction = Double(i) / Double(max(barCount - 1, 1))
                    let barH = max(4, CGFloat(vm.recordedWaveform[i]) * h * 0.85)
                    let isPlayed = fraction <= progress
                    let inTrim = fraction >= vm.trimStart && fraction <= vm.trimEnd

                    Capsule()
                        .fill(barFill(isPlayed: isPlayed, inTrim: inTrim, fraction: fraction))
                        .frame(width: barW, height: barH)
                        .animation(.linear(duration: 0.03), value: progress)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func barFill(isPlayed: Bool, inTrim: Bool, fraction: Double) -> Color {
        if vm.isTrimming {
            if !inTrim { return .white.opacity(0.1) }
            return isPlayed ? .blue : .white.opacity(0.45)
        }
        return isPlayed ? .blue.opacity(0.9) : .white.opacity(0.3)
    }

    // MARK: - Playhead Overlay

    private var playheadOverlay: some View {
        GeometryReader { geo in
            let x = CGFloat(vm.playbackPosition) * geo.size.width
            Capsule()
                .fill(.white)
                .frame(width: 2.5, height: geo.size.height)
                .offset(x: x - 1.25)
                .animation(.linear(duration: 0.03), value: vm.playbackPosition)
        }
    }

    // MARK: - Trim Overlay

    private var trimOverlay: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let sx = CGFloat(vm.trimStart) * w
            let ex = CGFloat(vm.trimEnd) * w

            ZStack(alignment: .leading) {
                // Darkened zones outside trim
                Rectangle()
                    .fill(.black.opacity(0.5))
                    .frame(width: sx, height: h)

                Rectangle()
                    .fill(.black.opacity(0.5))
                    .frame(width: max(0, w - ex), height: h)
                    .offset(x: ex)

                // Trim bracket
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(.yellow.opacity(0.9), lineWidth: 2)
                    .frame(width: max(0, ex - sx), height: h)
                    .offset(x: sx)

                // Start handle
                trimHandle(at: sx, height: h, isDragging: isDraggingTrimStart)
                    .gesture(trimStartGesture(totalWidth: w))

                // End handle
                trimHandle(at: ex - 16, height: h, isDragging: isDraggingTrimEnd)
                    .gesture(trimEndGesture(totalWidth: w))
            }
        }
    }

    private func trimHandle(at x: CGFloat, height: CGFloat, isDragging: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.yellow.opacity(isDragging ? 1.0 : 0.85))
            .frame(width: 16, height: height)
            .overlay {
                VStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule()
                            .fill(.black.opacity(0.6))
                            .frame(width: 2, height: 10)
                    }
                }
            }
            .offset(x: x)
            .scaleEffect(isDragging ? 1.05 : 1.0)
            .animation(.spring(duration: 0.2), value: isDragging)
    }

    // MARK: - Trim Toggle

    private var trimToggleRow: some View {
        Button {
            withAnimation(.spring(duration: 0.3)) {
                vm.isTrimming.toggle()
                if !vm.isTrimming {
                    vm.trimStart = 0
                    vm.trimEnd = 1
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: vm.isTrimming ? "scissors.badge.ellipsis" : "scissors")
                    .font(.system(size: 13, weight: .medium))
                Text(vm.isTrimming ? "Clear Trim" : "Trim")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(vm.isTrimming ? .yellow : .white.opacity(0.55))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(vm.isTrimming ? .yellow.opacity(0.15) : .white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Gestures

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { val in
                // Don't scrub if dragging trim handles
                guard !isDraggingTrimStart && !isDraggingTrimEnd else { return }
                isDraggingScrubber = true
                vm.stopPlayback()
                let frac = val.location.x / max(1, waveformWidth)
                vm.seekTo(max(0, min(1, frac)))
            }
            .onEnded { _ in isDraggingScrubber = false }
    }

    private func trimStartGesture(totalWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { val in
                isDraggingTrimStart = true
                let frac = val.location.x / totalWidth
                vm.trimStart = max(0, min(vm.trimEnd - 0.05, frac))
            }
            .onEnded { _ in isDraggingTrimStart = false }
    }

    private func trimEndGesture(totalWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { val in
                isDraggingTrimEnd = true
                let frac = val.location.x / totalWidth
                vm.trimEnd = max(vm.trimStart + 0.05, min(1, frac))
            }
            .onEnded { _ in isDraggingTrimEnd = false }
    }
}

// MARK: - Blinking Modifier

struct BlinkingModifier: ViewModifier {
    @State private var isVisible = true

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever()) {
                    isVisible = false
                }
            }
    }
}

// MARK: - Scale Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
