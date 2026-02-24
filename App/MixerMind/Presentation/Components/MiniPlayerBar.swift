import SwiftUI

struct MiniPlayerBar: View {
    var coordinator: AudioPlaybackCoordinator

    private var hasTrack: Bool { coordinator.currentTrack != nil }

    var body: some View {
        if hasTrack {
            VStack(spacing: 0) {
                // Progress bar
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * coordinator.progress)
                }
                .frame(height: 2)

                HStack(spacing: 12) {
                    // Track info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(coordinator.currentTrack?.title ?? "")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(coordinator.currentTrack?.artist ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Controls
                    HStack(spacing: 16) {
                        Button {
                            coordinator.togglePlayPause()
                        } label: {
                            Image(systemName: coordinator.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title3)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            coordinator.next()
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.body)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .frame(height: 56)
            .glassEffect(in: .rect(cornerRadius: 16))
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

extension MiniPlayerBar {
    func animated() -> some View {
        self.animation(.spring(duration: 0.35), value: hasTrack)
    }
}
