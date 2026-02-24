import SwiftUI

// MARK: - Temporary preview screen — delete when done

struct TitleStylePreview: View {
    @Environment(\.dismiss) private var dismiss

    private let dummyImage = "https://picsum.photos/seed/mixer/400/300"
    private let title = "Song Title"
    private let subtitle = "Artist Name"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Pick a title style")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        PreviewCard(label: "A — Liquid Glass", title: title, subtitle: subtitle, style: .liquidGlass)
                        PreviewCard(label: "B — Ultra Thin Material", title: title, subtitle: subtitle, style: .ultraThinMaterial)
                        PreviewCard(label: "C — Gradient Overlay", title: title, subtitle: subtitle, style: .gradient)
                        PreviewCard(label: "D — Glass Rounded", title: title, subtitle: subtitle, style: .liquidGlassRounded)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Title Styles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Card styles

private enum TitleStyle {
    case liquidGlass        // A: glassEffect rect, sharp corners
    case ultraThinMaterial  // B: .ultraThinMaterial blur
    case gradient           // C: gradient fade, title floats on image
    case liquidGlassRounded // D: glassEffect rect with rounded bottom corners
}

private struct PreviewCard: View {
    let label: String
    let title: String
    let subtitle: String
    let style: TitleStyle

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            ZStack(alignment: .bottom) {
                // Dummy image placeholder
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hue: 0.6, saturation: 0.4, brightness: 0.4),
                                     Color(hue: 0.8, saturation: 0.5, brightness: 0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        // Fake image texture
                        VStack {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                    .frame(height: 160)

                titleOverlay
            }
            .clipShape(.rect(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var titleOverlay: some View {
        switch style {

        // A: Full Liquid Glass rect, sharp edges, separate block below image
        case .liquidGlass:
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(in: .rect(cornerRadius: 0))

        // B: Ultra thin material blur, separate block
        case .ultraThinMaterial:
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)

        // C: Gradient fade, title floats over image — no separate block
        case .gradient:
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

        // D: Liquid Glass with rounded bottom corners matching card
        case .liquidGlassRounded:
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(in: .rect(cornerRadius: 0))
            .clipShape(
                .rect(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 12,
                    bottomTrailingRadius: 12,
                    topTrailingRadius: 0
                )
            )
        }
    }
}
