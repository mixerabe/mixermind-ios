import SwiftUI

struct EmbedLinkSheet: View {
    @Bindable var viewModel: CreateMixViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var urlText: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField("apple.com", text: $urlText)
                    .focused($isFocused)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding()
                    .glassEffect(in: .rect(cornerRadius: 12))

                Button {
                    let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    dismiss()
                    Task { await viewModel.setEmbedUrl(trimmed) }
                } label: {
                    Text("Embed")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.plain)
                .glassEffect(in: .capsule)
                .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)

                Spacer()
            }
            .padding()
            .navigationTitle("Embed Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .onAppear {
                urlText = viewModel.embedUrl
                isFocused = true
            }
        }
        .preferredColorScheme(.dark)
    }
}
