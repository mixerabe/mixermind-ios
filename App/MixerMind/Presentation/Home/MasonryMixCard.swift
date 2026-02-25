import SwiftUI

struct MasonryMixCard: View {
    let mix: Mix

    private static let darkBg = Color(red: 0.08, green: 0.08, blue: 0.08)
    private static let canvasAspect: CGFloat = 9.0 / 17.0 // width / height

    /// Parse title around "--", "—" (em dash), or "–" (en dash) delimiter
    private var parsedTitle: (title: String, subtitle: String?)? {
        guard let raw = mix.title, !raw.isEmpty else { return nil }
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

    private var scaleY: Double { mix.previewScaleY ?? 1.0 }

    /// Cropped aspect ratio: full width, visible height = canvasHeight / scaleY
    private var croppedAspectRatio: CGFloat {
        Self.canvasAspect * scaleY
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let url = mix.screenshotUrl, let screenshotURL = URL(string: url) {
                GeometryReader { geo in
                    let cardW = geo.size.width
                    let cardH = cardW / croppedAspectRatio
                    // Full-width image at original 9:17 proportions, clipped vertically from center
                    let imgH = cardW / Self.canvasAspect

                    LocalAsyncImage(url: screenshotURL) { image in
                        image
                            .resizable()
                            .frame(width: cardW, height: imgH)
                            .frame(width: cardW, height: cardH)
                            .clipped()
                    } placeholder: {
                        Self.darkBg
                            .frame(width: cardW, height: cardH)
                    }
                }
                .aspectRatio(croppedAspectRatio, contentMode: .fit)
            } else {
                ZStack {
                    Self.darkBg
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.3))
                }
                .frame(height: 120)
            }

            titleSection

            // Creation status overlay
            if let status = mix.creationStatus {
                ZStack {
                    Color.black.opacity(0.3)
                    if status == "creating" {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else if status == "failed" {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.title3)
                    }
                }
            }
        }
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: - Title Section

    @ViewBuilder
    private var titleSection: some View {
        if let parsed = parsedTitle {
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
}
