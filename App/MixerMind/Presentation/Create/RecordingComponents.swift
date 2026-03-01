import SwiftUI

// MARK: - Live Recording Visual

struct LiveRecordingVisual: View {
    var vm: RecordAudioViewModel

    var body: some View {
        VStack(spacing: 32) {
            WaveformBarsView(
                bars: vm.liveWaveformBars,
                isActive: vm.state == .recording,
                activeColor: .red,
                inactiveColor: .white.opacity(0.15)
            )
            .frame(height: 100)
            .padding(.horizontal, 20)

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

    @State private var isDraggingTrimStart = false
    @State private var isDraggingTrimEnd = false

    var body: some View {
        VStack(spacing: 20) {
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

            trimToggleRow
        }
    }

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

    private var trimOverlay: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let sx = CGFloat(vm.trimStart) * w
            let ex = CGFloat(vm.trimEnd) * w

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.black.opacity(0.5))
                    .frame(width: sx, height: h)

                Rectangle()
                    .fill(.black.opacity(0.5))
                    .frame(width: max(0, w - ex), height: h)
                    .offset(x: ex)

                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(.yellow.opacity(0.9), lineWidth: 2)
                    .frame(width: max(0, ex - sx), height: h)
                    .offset(x: sx)

                trimHandle(at: sx, height: h, isDragging: isDraggingTrimStart)
                    .gesture(trimStartGesture(totalWidth: w))

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

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { val in
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
