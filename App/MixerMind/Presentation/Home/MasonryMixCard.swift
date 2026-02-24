import SwiftUI

struct MasonryMixCard: View {
    let mix: Mix

    private static let darkBg = Color(red: 0.08, green: 0.08, blue: 0.08)

    /// Parse title around "--", "—" (em dash), or "–" (en dash) delimiter
    private var parsedTitle: (title: String, subtitle: String?)? {
        guard let raw = mix.title, !raw.isEmpty else { return nil }
        // Try " -- ", " — ", " – " (with spaces), then "—", "–" (without spaces)
        let separators = [" -- ", " \u{2014} ", " \u{2013} ", "\u{2014}", "\u{2013}"]
        for sep in separators {
            if let range = raw.range(of: sep) {
                let before = String(raw[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let after = String(raw[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                guard !before.isEmpty, !after.isEmpty else { continue }
                return (title: after, subtitle: before)
            }
        }
        return (title: raw, subtitle: nil)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
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
            }

            titleSection
        }
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: - Title Section

    @ViewBuilder
    private var titleSection: some View {
        if let parsed = parsedTitle {
            // Gradient fade behind text
            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: parsed.subtitle != nil ? 72 : 52)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    if let subtitle = parsed.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Text(parsed.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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
            LocalAsyncImage(url: URL(string: mix.photoThumbnailUrl ?? mix.photoUrl ?? "")) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                if mix.photoThumbnailUrl != nil || mix.photoUrl != nil {
                    Color(.systemGray6)
                        .frame(minHeight: 120)
                } else {
                    mediaPlaceholder(icon: "photo")
                }
            }
        }
    }

    // MARK: - Video Card

    private var videoCard: some View {
        ZStack {
            LocalAsyncImage(url: URL(string: mix.videoThumbnailUrl ?? "")) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                if mix.videoThumbnailUrl != nil {
                    Color(.systemGray6)
                        .frame(minHeight: 120)
                } else {
                    mediaPlaceholder(icon: "video")
                }
            }

            playIconOverlay
        }
    }

    // MARK: - Import Card

    private var importCard: some View {
        ZStack {
            if mix.importThumbnailUrl != nil {
                LocalAsyncImage(url: URL(string: mix.importThumbnailUrl ?? "")) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color(.systemGray6)
                        .frame(minHeight: 120)
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
        ZStack {
            LocalAsyncImage(url: URL(string: mix.embedOg?.imageUrl ?? "")) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                if mix.embedOg?.imageUrl != nil {
                    Color(.systemGray5)
                        .frame(height: 80)
                } else {
                    mediaPlaceholder(icon: "link")
                }
            }
        }
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
