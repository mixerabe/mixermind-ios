import SwiftUI

struct CreateURLImportPage: View {
    @State private var viewModel = CreateMixViewModel()
    @State private var urlText = ""
    @State private var isSaving = false
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var isDisabled: Bool { urlText.isEmpty || viewModel.isImportingURL }

    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Paste an Instagram or X link")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("https://...", text: $urlText)
                    .focused($isFocused)
                    .padding(12)
                    .glassEffect(in: .rect(cornerRadius: 10))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            }

            if let progress = viewModel.importProgress {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(progress)
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

            HStack(spacing: 12) {
                Button {
                    importAndSave(mode: .video)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Video")
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(height: 48)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .glassEffect(in: .capsule)
                .disabled(isDisabled || isSaving)
                .opacity((isDisabled || isSaving) ? 0.4 : 1)

                Button {
                    importAndSave(mode: .audio)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Audio Only")
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(height: 48)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .glassEffect(in: .capsule)
                .disabled(isDisabled || isSaving)
                .opacity((isDisabled || isSaving) ? 0.4 : 1)
            }
        }
        .padding()
        .navigationTitle("Import Media")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isFocused = true }
    }

    private func importAndSave(mode: CreateMixViewModel.ImportMode) {
        Task {
            await viewModel.importFromURL(urlText, mode: mode)
            guard viewModel.errorMessage == nil else { return }
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
