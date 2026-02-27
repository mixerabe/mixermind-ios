import SwiftUI
import AVFoundation

struct MixCanvasView: View {
    // Content
    let mixType: MixType
    let textContent: String
    let mediaThumbnail: UIImage?
    let mediaUrl: String?
    let thumbnailUrl: String?
    let videoPlayer: AVPlayer?
    let embedUrl: String?
    let embedOg: OGMetadata?

    // Gradient background
    var gradientTop: String?
    var gradientBottom: String?

    let onEmbedTap: (() -> Void)?

    // Playback state
    @Binding var isPaused: Bool
    @Binding var isMuted: Bool
    @Binding var isScrubbing: Bool
    @Binding var playbackProgress: Double
    let hasPlayback: Bool
    var playbackDuration: TimeInterval = 0
    let onTogglePause: () -> Void
    let onToggleMute: () -> Void
    let onBeginScrub: () -> Void
    let onScrub: (Double) -> Void
    let onEndScrub: () -> Void

    // Canvas tap
    let onCanvasTap: (() -> Void)?

    // Placeholder tap (create mode empty text)
    let onPlaceholderTap: (() -> Void)?

    var isMinimized: Bool = false
    var dragProgress: CGFloat = 0

    @State private var scrubStartProgress: Double = 0
    @State private var textContentHeight: CGFloat = 0

    private static let darkBg = Color.blue

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(hex: gradientTop ?? "#1a1a2e"),
                Color(hex: gradientBottom ?? "#16213e")
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        ZStack {
            backgroundGradient

            // Content layer — centered
            contentLayer

            // Embed card
            if let url = embedUrl, !url.isEmpty {
                EmbedCardView(urlString: url, og: embedOg, onTap: onEmbedTap)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

        }
        .contentShape(.rect)
        .onTapGesture {
            onCanvasTap?()
        }
        .overlay {
            if isPaused, hasPlayback, !isMinimized {
                pausedOverlay
                    .opacity(Double(max(1 - dragProgress * 3, 0)))
            }
        }
        // Progress bar on top of everything so scrubbing works even when paused
        .overlay(alignment: .bottom) {
            progressBar
        }
    }

    // MARK: - Content Layer

    @ViewBuilder
    private var contentLayer: some View {
        switch mixType {
        case .video, .import:
            videoPreview
            if let player = videoPlayer {
                GeometryReader { geo in
                    LoopingVideoView(player: player, gravity: .resizeAspect)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            if hasText { textOverlay }

        case .photo:
            photoContent
            if hasText { textOverlay }

        case .audio:
            VStack(spacing: 24) {
                AudioWaveView(isPlaying: !isPaused)
                if playbackDuration > 0 {
                    Text(formatTime(playbackProgress * playbackDuration))
                        .font(.system(size: 48, weight: .thin, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .contentTransition(.numericText())
                        .animation(.linear(duration: 0.1), value: playbackProgress)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if hasText { textOverlay }

        case .embed:
            if hasText { textOverlay }

        case .text:
            if hasText {
                noteTextView
            } else if let action = onPlaceholderTap {
                Button {
                    action()
                } label: {
                    Text("Type something...")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.25))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Video Preview (first frame while player loads)

    @ViewBuilder
    private var videoPreview: some View {
        if let thumb = mediaThumbnail {
            Image(uiImage: thumb)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let urlString = thumbnailUrl, let url = URL(string: urlString) {
            LocalAsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                EmptyView()
            }
        }
    }

    // MARK: - Photo Content

    @ViewBuilder
    private var photoContent: some View {
        if let thumb = mediaThumbnail {
            Image(uiImage: thumb)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let urlString = mediaUrl, let url = URL(string: urlString) {
            LocalAsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                EmptyView()
            }
        }
    }

    // MARK: - Text Overlay

    private var textOverlay: some View {
        Text(textContent)
            .font(.system(size: dynamicFontSize, weight: .medium))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .shadow(radius: 2)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geo in
            let barHeight: CGFloat = isScrubbing ? 4 : 2
            let circleSize: CGFloat = 10
            let fillWidth = geo.size.width * playbackProgress

            ZStack(alignment: .bottomLeading) {
                Color.clear

                HStack(spacing: 0) {
                    Rectangle()
                        .fill(.white.opacity(0.4))
                        .frame(
                            width: max(fillWidth - (isScrubbing ? circleSize / 2 : 0), 0),
                            height: barHeight
                        )

                    if isScrubbing {
                        Circle()
                            .fill(.white)
                            .frame(width: circleSize, height: circleSize)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: isScrubbing)
            }
        }
        .frame(height: 44)
        .contentShape(.rect)
        .gesture(scrubGesture)
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard hasPlayback else { return }
                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                guard horizontal > vertical else { return }

                if !isScrubbing {
                    scrubStartProgress = playbackProgress
                    onBeginScrub()
                }
                let screenWidth = UIScreen.main.bounds.width
                let delta = value.translation.width / screenWidth
                onScrub(scrubStartProgress + delta)
            }
            .onEnded { _ in
                guard isScrubbing else { return }
                onEndScrub()
            }
    }

    // MARK: - Paused Overlay

    private var pausedOverlay: some View {
        VStack(spacing: 16) {
            // Play button → resume
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    onTogglePause()
                }
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .glassEffect(in: .circle)
            }
            .buttonStyle(.plain)

            // Mute button → toggle mute (does NOT resume)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    onToggleMute()
                }
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 44, height: 44)
                    .glassEffect(in: .circle)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // Background tap → resume playback
            Color.black.opacity(0.001)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        onTogglePause()
                    }
                }
        }
    }

    // MARK: - Note-style Text View

    private var noteTextView: some View {
        GeometryReader { container in
            let containerHeight = container.size.height

            Text(textContent)
                .font(.system(size: 17, weight: .regular))
                .lineSpacing(6)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.leading, 24)
                .padding(.trailing, 24)
                .padding(.top, 120)
                .padding(.bottom, 200)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    GeometryReader { textGeo in
                        Color.clear.preference(
                            key: TextHeightKey.self,
                            value: textGeo.size.height
                        )
                    }
                )
                .offset(y: noteScrollOffset(
                    contentHeight: textContentHeight,
                    containerHeight: containerHeight
                ))
                .onPreferenceChange(TextHeightKey.self) { height in
                    textContentHeight = height
                }
        }
        .clipped()
    }

    private func noteScrollOffset(contentHeight: CGFloat, containerHeight: CGFloat) -> CGFloat {
        let overflow = contentHeight - containerHeight
        guard overflow > 0, hasPlayback else { return 0 }
        return -overflow * playbackProgress
    }

    // MARK: - Helpers

    private var hasText: Bool { !textContent.isEmpty }

    private var dynamicFontSize: CGFloat {
        let length = textContent.count
        if length < 20 { return 32 }
        if length < 50 { return 26 }
        if length < 100 { return 22 }
        if length < 200 { return 18 }
        return 14
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let total = max(0, Int(time))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

private struct TextHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
