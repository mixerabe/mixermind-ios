import SwiftUI

struct CreateEmbedPage: View {
    @State private var viewModel = CreateMixViewModel()
    @State private var urlText = ""
    @State private var isSaving = false
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var isDisabled: Bool {
        urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isFetchingOG || isSaving
    }

    var body: some View {
        VStack(spacing: 20) {
            TextField("apple.com", text: $urlText)
                .focused($isFocused)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding()
                .glassEffect(in: .rect(cornerRadius: 12))

            if viewModel.isFetchingOG {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Fetching preview...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if isSaving {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Saving...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }

            Spacer()

            Button {
                embedAndSave()
            } label: {
                Text("Embed")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.plain)
            .glassEffect(in: .capsule)
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.4 : 1)
        }
        .padding()
        .navigationTitle("Embed Link")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isFocused = true }
    }

    private func embedAndSave() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            await viewModel.setEmbedUrl(trimmed)
            isSaving = true
            let success = await viewModel.saveMix()
            if success {
                dismiss()
            } else {
                isSaving = false
            }
        }
    }
}
