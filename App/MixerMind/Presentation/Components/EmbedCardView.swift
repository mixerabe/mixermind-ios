import SwiftUI

struct EmbedCardView: View {
    let urlString: String
    var og: OGMetadata?
    var onTap: (() -> Void)?

    private var displayHost: String {
        if let host = og?.host, !host.isEmpty { return host }
        guard let url = URL(string: urlString), let host = url.host else {
            return urlString
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var body: some View {
        VStack {
            Spacer()
            card
                .padding(.horizontal, 32)
                .contentShape(.rect)
                .onTapGesture {
                    onTap?()
                }
            Spacer()
        }
        .allowsHitTesting(onTap != nil)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            // OG image — large, fills the top
            if let imageUrlString = og?.imageUrl, let imageUrl = URL(string: imageUrlString) {
                AsyncImage(url: imageUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 180)
                            .clipped()
                    case .failure:
                        imagePlaceholder
                    default:
                        Color.white.opacity(0.08)
                            .frame(height: 180)
                            .overlay {
                                ProgressView()
                                    .tint(.white.opacity(0.3))
                            }
                    }
                }
            } else {
                imagePlaceholder
            }

            // Text content
            VStack(alignment: .leading, spacing: 6) {
                if let title = og?.title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }

                if let description = og?.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(3)
                }

                // Host row
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.caption2)
                    Text(displayHost.uppercased())
                        .font(.caption2.weight(.medium))
                    Spacer()
                    if onTap != nil {
                        Image(systemName: "arrow.up.right")
                            .font(.caption2.weight(.semibold))
                    }
                }
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .glassEffect(in: .rect(cornerRadius: 16))
    }

    private var imagePlaceholder: some View {
        ZStack {
            Color.white.opacity(0.06)
            VStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.2))
                if og == nil {
                    // Still loading
                    ProgressView()
                        .tint(.white.opacity(0.3))
                }
            }
        }
        .frame(height: 120)
    }
}

// MARK: - Static Embed Card (for ImageRenderer previews)

struct StaticEmbedCard: View {
    let urlString: String
    var og: OGMetadata?
    let image: UIImage

    private var displayHost: String {
        if let host = og?.host, !host.isEmpty { return host }
        guard let url = URL(string: urlString), let host = url.host else {
            return urlString
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var body: some View {
        VStack {
            Spacer()
            card
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 180)
                .clipped()

            VStack(alignment: .leading, spacing: 6) {
                if let title = og?.title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }

                if let description = og?.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(3)
                }

                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.caption2)
                    Text(displayHost.uppercased())
                        .font(.caption2.weight(.medium))
                    Spacer()
                }
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(Color.white.opacity(0.1))
        .clipShape(.rect(cornerRadius: 16))
    }
}
