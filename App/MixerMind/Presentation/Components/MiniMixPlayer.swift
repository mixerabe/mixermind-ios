import SwiftUI

struct MiniMixPlayer: View {
    var viewModel: MixViewerViewModel
    var coordinator: AudioPlaybackCoordinator
    var onExpand: () -> Void
    var onDismiss: () -> Void

    @Binding var corner: Corner
    @State private var dragOffset: CGSize = .zero

    private static let darkBg = Color(red: 0.08, green: 0.08, blue: 0.08)

    static let cardWidth: CGFloat = 136
    static let cardHeight: CGFloat = 172 // thumbnail(120) + controls(34) + progress(8) + padding(16-ish)

    enum Corner {
        case topLeading, topTrailing, bottomLeading, bottomTrailing

        var alignment: Alignment {
            switch self {
            case .topLeading: .topLeading
            case .topTrailing: .topTrailing
            case .bottomLeading: .bottomLeading
            case .bottomTrailing: .bottomTrailing
            }
        }
    }

    var body: some View {
        miniPlayerCard
            .offset(dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { dragOffset = $0.translation }
                    .onEnded { value in
                        let isRight = value.predictedEndTranslation.width > 0
                        let isDown = value.predictedEndTranslation.height > 0
                        withAnimation(.spring(duration: 0.3)) {
                            switch (isRight, isDown) {
                            case (true, true): corner = .bottomTrailing
                            case (true, false): corner = .topTrailing
                            case (false, true): corner = .bottomLeading
                            case (false, false): corner = .topLeading
                            }
                            dragOffset = .zero
                        }
                    }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onChange(of: coordinator.currentTrackIndex) { _, _ in
                viewModel.syncActiveTrack()
            }
    }

    private var miniPlayerCard: some View {
        VStack(spacing: 0) {
            thumbnail
                .frame(width: 120, height: 120)
                .clipShape(.rect(cornerRadius: 12))

            HStack(spacing: 16) {
                Button { coordinator.previous() } label: {
                    Image(systemName: "backward.fill")
                        .font(.caption)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button { coordinator.togglePlayPause() } label: {
                    Image(systemName: coordinator.isPlaying ? "pause.fill" : "play.fill")
                        .font(.callout)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button { coordinator.next() } label: {
                    Image(systemName: "forward.fill")
                        .font(.caption)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.white)
            .padding(.top, 6)

            GeometryReader { geo in
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * coordinator.progress)
            }
            .frame(height: 2)
            .padding(.top, 6)
        }
        .padding(8)
        .frame(width: 136)
        .background(Self.darkBg, in: .rect(cornerRadius: 16))
        .glassEffect(in: .rect(cornerRadius: 16))
        .overlay(alignment: .topTrailing) {
            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .padding(4)
        }
        .contentShape(Rectangle())
        .onTapGesture { onExpand() }
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnail: some View {
        let mix = viewModel.currentMix
        switch mix.type {
        case .text:
            ZStack {
                Self.darkBg
                if let text = mix.textContent, !text.isEmpty {
                    Text(text)
                        .font(.system(size: 10, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .lineLimit(5)
                        .padding(6)
                }
            }
        case .photo:
            LocalAsyncImage(url: URL(string: mix.photoThumbnailUrl ?? mix.photoUrl ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Self.darkBg
            }
        case .video:
            LocalAsyncImage(url: URL(string: mix.videoThumbnailUrl ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Self.darkBg
            }
        case .import:
            if let thumb = mix.importThumbnailUrl {
                LocalAsyncImage(url: URL(string: thumb)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Self.darkBg
                }
            } else {
                ZStack {
                    Self.darkBg
                    Image(systemName: "waveform")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        case .embed:
            LocalAsyncImage(url: URL(string: mix.embedOg?.imageUrl ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ZStack {
                    Self.darkBg
                    Image(systemName: "link")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        case .audio:
            ZStack {
                Self.darkBg
                Image(systemName: "mic.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}
