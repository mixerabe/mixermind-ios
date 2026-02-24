import SwiftUI
import AVFoundation

// MARK: - Static Canvas for Preview Rendering

struct MixCanvasContent: View {
    let mixType: MixType
    let textContent: String
    let mediaThumbnail: UIImage?
    var appleMusicTitle: String? = nil
    var appleMusicArtist: String? = nil
    var appleMusicArtworkUrl: String? = nil
    var embedUrl: String? = nil
    var embedOg: OGMetadata? = nil
    var embedImage: UIImage? = nil

    private var hasText: Bool { !textContent.isEmpty }
    private var hasEmbed: Bool { !(embedUrl ?? "").isEmpty }

    private static let darkBg = Color(red: 0.08, green: 0.08, blue: 0.08)

    var body: some View {
        ZStack {
            Self.darkBg

            switch mixType {
            case .video, .photo, .import:
                if let thumb = mediaThumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFit()
                }
                if hasText {
                    textView
                }

            case .audio:
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white)
                if hasText {
                    textView
                }

            case .appleMusic:
                VStack(spacing: 12) {
                    if let thumb = mediaThumbnail {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 160, height: 160)
                            .clipShape(.rect(cornerRadius: 10))
                    }
                    if let title = appleMusicTitle {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    if let artist = appleMusicArtist {
                        Text(artist)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                if hasText {
                    textView
                }

            case .embed:
                if hasText {
                    textView
                }

            case .text:
                if hasText {
                    textView
                }
            }

            if hasEmbed, let url = embedUrl {
                if let embedImg = embedImage {
                    StaticEmbedCard(urlString: url, og: embedOg, image: embedImg)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EmbedCardView(urlString: url, og: embedOg, onTap: nil)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var textView: some View {
        Text(textContent)
            .font(.system(size: dynamicFontSize, weight: .medium))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .shadow(radius: 2)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dynamicFontSize: CGFloat {
        let length = textContent.count
        if length < 20 { return 32 }
        if length < 50 { return 26 }
        if length < 100 { return 22 }
        if length < 200 { return 18 }
        return 14
    }
}

// MARK: - Text Input Sheet

struct TextInputSheet: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var originalText = ""

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($isFocused)
                .scrollContentBackground(.hidden)
                .padding()
                .navigationTitle("Add Text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { dismiss() } label: {
                            Image(systemName: "checkmark")
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        HStack(spacing: 12) {
                            Button {
                                text = originalText
                                dismiss()
                            } label: {
                                Image(systemName: "xmark")
                            }

                            if !originalText.isEmpty {
                                Button(role: .destructive) {
                                    text = ""
                                    dismiss()
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .foregroundStyle(.red)
                            }
                        }
                    }
                }
                .onAppear {
                    originalText = text
                    isFocused = true
                }
        }
    }
}
