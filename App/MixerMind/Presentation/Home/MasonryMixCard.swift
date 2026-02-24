import SwiftUI

struct MasonryMixCard: View {
    let mix: Mix

    private static let darkBg = Color(red: 0.08, green: 0.08, blue: 0.08)

    var body: some View {
        VStack(spacing: 0) {
            if let title = mix.title, !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 40)
                    .glassEffect(in: .rect(cornerRadius: 0))
            }

            Group {
                switch mix.type {
                case .text:
                    textCard
                case .photo:
                    photoCard
                case .video:
                    videoCard
                case .import:
                    importCard
                case .embed:
                    embedCard
                case .audio:
                    audioCard
                case .appleMusic:
                    appleMusicCard
                }
            }
        }
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: - Text Card

    private var textCard: some View {
        ZStack {
            Self.darkBg

            if let text = mix.textContent, !text.isEmpty {
                Text(text)
                    .font(.system(size: dynamicFontSize(for: text), weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .lineLimit(6)
                    .truncationMode(.tail)
                    .padding(12)
            }
        }
        .frame(minHeight: 80)
    }

    // MARK: - Photo Card

    private var photoCard: some View {
        ZStack {
            if let urlString = mix.photoThumbnailUrl ?? mix.photoUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        mediaPlaceholder(icon: "photo")
                    default:
                        Color(.systemGray6)
                            .frame(minHeight: 120)
                    }
                }
            } else {
                mediaPlaceholder(icon: "photo")
            }
        }
    }

    // MARK: - Video Card

    private var videoCard: some View {
        ZStack {
            if let urlString = mix.videoThumbnailUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        mediaPlaceholder(icon: "video")
                    default:
                        Color(.systemGray6)
                            .frame(minHeight: 120)
                    }
                }
            } else {
                mediaPlaceholder(icon: "video")
            }

            playIconOverlay
        }
    }

    // MARK: - Import Card

    private var importCard: some View {
        ZStack {
            if let urlString = mix.importThumbnailUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        mediaPlaceholder(icon: "square.and.arrow.down")
                    default:
                        Color(.systemGray6)
                            .frame(minHeight: 120)
                    }
                }
            } else if mix.importAudioUrl != nil {
                // Audio-only import
                ZStack {
                    Self.darkBg
                    VStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(12)
                }
                .frame(minHeight: 80)
            } else {
                mediaPlaceholder(icon: "square.and.arrow.down")
            }

            if mix.importMediaUrl != nil {
                playIconOverlay
            }
        }
    }

    // MARK: - Embed Card

    private var embedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let imageUrl = mix.embedOg?.imageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxHeight: 120)
                            .clipped()
                    default:
                        Color(.systemGray5)
                            .frame(height: 80)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                if let title = mix.embedOg?.title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                if let host = mix.embedOg?.host {
                    Text(host)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(10)
        }
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Audio Card

    private var audioCard: some View {
        ZStack {
            Self.darkBg

            VStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.7))

                if let text = mix.textContent, !text.isEmpty {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
            .padding(12)
        }
        .frame(minHeight: 80)
    }

    // MARK: - Apple Music Card

    private var appleMusicCard: some View {
        VStack(spacing: 0) {
            if let artworkUrl = mix.appleMusicArtworkUrl, let url = URL(string: artworkUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Color(.systemGray5)
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }

            if mix.appleMusicTitle != nil || mix.appleMusicArtist != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let title = mix.appleMusicTitle {
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    if let artist = mix.appleMusicArtist {
                        Text(artist)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Helpers

    private func mediaPlaceholder(icon: String) -> some View {
        ZStack {
            Self.darkBg
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(height: 160)
    }

    private var playIconOverlay: some View {
        Image(systemName: "play.fill")
            .font(.title3)
            .foregroundStyle(.white.opacity(0.8))
            .padding(8)
            .background(.ultraThinMaterial, in: .circle)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(8)
    }

    private func dynamicFontSize(for text: String) -> CGFloat {
        let length = text.count
        if length < 20 { return 22 }
        if length < 50 { return 18 }
        if length < 100 { return 15 }
        return 13
    }
}
