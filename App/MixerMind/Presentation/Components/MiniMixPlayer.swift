import SwiftUI

struct MiniMixPlayer: View {
    var viewModel: MixViewerViewModel
    var coordinator: AudioPlaybackCoordinator
    var animation: Namespace.ID
    var onExpand: () -> Void
    var onDismiss: () -> Void

    private static let darkBg = Color(red: 0.08, green: 0.08, blue: 0.08)

    var body: some View {
        VStack(spacing: 0) {
            // Thumbnail area
            thumbnail
                .frame(width: 120, height: 120)
                .clipShape(.rect(cornerRadius: 12))

            // Controls
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

            // Progress bar
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
        .matchedGeometryEffect(id: "viewer", in: animation)
        .contentShape(Rectangle())
        .onTapGesture { onExpand() }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.height > 40 {
                        onDismiss()
                    }
                }
        )
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onChange(of: coordinator.currentTrackIndex) { _, _ in
            viewModel.syncActiveTrack()
        }
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
