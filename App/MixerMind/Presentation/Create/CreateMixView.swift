import SwiftUI
import AVFoundation

// MARK: - Static Canvas for Preview Rendering

struct MixCanvasContent: View {
    let mixType: MixType
    let textContent: String
    let mediaThumbnail: UIImage?
    var embedUrl: String? = nil
    var embedOg: OGMetadata? = nil
    var embedImage: UIImage? = nil
    var gradientTop: String? = nil
    var gradientBottom: String? = nil

    private var hasText: Bool { !textContent.isEmpty }
    private var hasEmbed: Bool { !(embedUrl ?? "").isEmpty }

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
            .font(.system(size: 17, weight: .regular))
            .lineSpacing(6)
            .multilineTextAlignment(.leading)
            .foregroundStyle(.white.opacity(0.9))
            .padding(.leading, 24)
            .padding(.trailing, 24)
            .padding(.top, 120)
            .padding(.bottom, 200)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
