import SwiftUI

struct CreateTextPage: View {
    @State private var viewModel = CreateMixViewModel()
    @State private var isSaving = false
    @FocusState private var titleFocused: Bool
    @FocusState private var bodyFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private var canSend: Bool {
        !viewModel.textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Title field
                titleField
                    .padding(.horizontal)
                    .padding(.top, 12)

                // Main text editor
                TextEditor(text: Binding(
                    get: { viewModel.textContent },
                    set: { viewModel.textContent = $0 }
                ))
                .focused($bodyFocused)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .disabled(isSaving)

                Spacer(minLength: 0)

                // Bottom send button
                Button {
                    save()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.plain)
                .glassEffect(in: .capsule)
                .disabled(!canSend)
                .opacity(!canSend ? 0.4 : 1)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            if isSaving {
                Color(.systemBackground).opacity(0.7).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                    Text(savingLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = viewModel.errorMessage {
                VStack {
                    Spacer()
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding()
                        .padding(.bottom, 60)
                }
            }
        }
        .navigationTitle("New Text")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.modelContext = modelContext
            bodyFocused = true
        }
    }

    // MARK: - Title Field

    private var titleField: some View {
        HStack(spacing: 8) {
            TextField("Title", text: $viewModel.title)
                .focused($titleFocused)
                .font(.subheadline.weight(.medium))
                .textFieldStyle(.plain)
                .onChange(of: viewModel.title) { _, newValue in
                    if newValue.count > 50 {
                        viewModel.title = String(newValue.prefix(50))
                    }
                    // Once user types in title, disable auto
                    if !newValue.isEmpty {
                        viewModel.autoCreateTitle = false
                    }
                }

            // Auto toggle — shown only when title is empty
            if viewModel.title.isEmpty {
                Button {
                    viewModel.autoCreateTitle.toggle()
                } label: {
                    Text("Auto")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(viewModel.autoCreateTitle ? .white : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            viewModel.autoCreateTitle ? Color.accentColor : Color.clear,
                            in: .capsule
                        )
                }
                .buttonStyle(.plain)
                .glassEffect(in: .capsule)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                .animation(.easeInOut(duration: 0.2), value: viewModel.title.isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(in: .rect(cornerRadius: 10))
    }

    private var savingLabel: String {
        if viewModel.isGeneratingTitle { return "Generating title..." }
        if viewModel.isGeneratingTTS { return "Generating audio..." }
        return "Saving..."
    }

    private func save() {
        isSaving = true
        viewModel.mixType = .text
        Task {
            let success = await viewModel.saveMix()
            if success {
                dismiss()
            } else {
                isSaving = false
            }
        }
    }
}
