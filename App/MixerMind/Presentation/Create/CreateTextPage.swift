import SwiftUI

struct CreateTextPage: View {
    @State private var viewModel = CreateMixViewModel()
    @State private var isSaving = false
    @State private var isEditingTitle = false
    @State private var titleDraft = ""
    @FocusState private var bodyFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private var canSend: Bool {
        !viewModel.textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Live text canvas — tap to start editing, shrinks font as text grows
                textCanvas
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .onTapGesture { bodyFocused = true }

                Spacer(minLength: 0)

                // Bottom send button
                Button { save() } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.plain)
                .glassEffect(in: .capsule)
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.4)
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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                titleChipButton
            }
        }
        .sheet(isPresented: $isEditingTitle) {
            RecordTitleEditSheet(
                title: $titleDraft,
                onDone: {
                    viewModel.title = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    isEditingTitle = false
                },
                onCancel: {
                    titleDraft = viewModel.title
                    isEditingTitle = false
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled()
        }
        .onAppear {
            viewModel.modelContext = modelContext
            bodyFocused = true
        }
    }

    // MARK: - Navbar Title Chip

    private var titleChipButton: some View {
        Button {
            titleDraft = viewModel.title
            isEditingTitle = true
        } label: {
            Text(viewModel.title.isEmpty ? "Add title" : viewModel.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(viewModel.title.isEmpty ? .white.opacity(0.4) : .white)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(in: .capsule)
    }

    // MARK: - Text Canvas

    private var textCanvas: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Invisible TextEditor for input (full size, transparent)
                TextEditor(text: Binding(
                    get: { viewModel.textContent },
                    set: { viewModel.textContent = $0 }
                ))
                .focused($bodyFocused)
                .scrollContentBackground(.hidden)
                .font(.system(size: dynamicFontSize, weight: .medium))
                .foregroundStyle(.clear)   // text invisible — overlay renders it
                .tint(.accentColor)
                .disabled(isSaving)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Visible text overlay (no scroll, just scales font)
                if viewModel.textContent.isEmpty {
                    Text("Start typing…")
                        .font(.system(size: dynamicFontSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.2))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                } else {
                    Text(viewModel.textContent)
                        .font(.system(size: dynamicFontSize, weight: .medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                        .animation(.easeOut(duration: 0.15), value: dynamicFontSize)
                        .allowsHitTesting(false)
                }
            }
        }
        // Reserve space from below the navbar down to the send button (~80pt)
        .frame(maxHeight: .infinity)
    }

    // MARK: - Dynamic Font Size

    private var dynamicFontSize: CGFloat {
        let len = viewModel.textContent.count
        switch len {
        case 0..<30:    return 32
        case 30..<80:   return 26
        case 80..<160:  return 22
        case 160..<300: return 18
        case 300..<500: return 15
        default:        return 13
        }
    }

    private var savingLabel: String {
        if viewModel.isGeneratingTTS { return "Generating audio..." }
        return "Saving..."
    }

    private func save() {
        isSaving = true
        viewModel.mixType = .text
        Task {
            let success = await viewModel.saveMix()
            if success { dismiss() } else { isSaving = false }
        }
    }
}
