import SwiftUI

struct ImportURLSheet: View {
    @Bindable var viewModel: CreateMixViewModel
    @State private var urlText = ""
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    private var isDisabled: Bool { urlText.isEmpty || viewModel.isImportingURL }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Paste an Instagram or YouTube link")
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

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }

                HStack(spacing: 12) {
                    Button {
                        Task {
                            await viewModel.importFromURL(urlText, mode: .video)
                            if viewModel.errorMessage == nil { dismiss() }
                        }
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
                    .disabled(isDisabled)
                    .opacity(isDisabled ? 0.4 : 1)

                    Button {
                        Task {
                            await viewModel.importFromURL(urlText, mode: .audio)
                            if viewModel.errorMessage == nil { dismiss() }
                        }
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
                    .disabled(isDisabled)
                    .opacity(isDisabled ? 0.4 : 1)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Import from Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .onAppear { isFocused = true }
        }
        .interactiveDismissDisabled()
    }
}
