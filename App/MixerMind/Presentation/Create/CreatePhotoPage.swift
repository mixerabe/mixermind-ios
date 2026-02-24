import SwiftUI
import PhotosUI

struct CreatePhotoPage: View {
    @State private var viewModel = CreateMixViewModel()
    @State private var showPicker = true
    @State private var isSaving = false
    @State private var pickerDismissedOnce = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            if isSaving {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Saving...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
            }
        }
        .navigationTitle("New Photo")
        .navigationBarTitleDisplayMode(.inline)
        .photosPicker(
            isPresented: $showPicker,
            selection: Binding(
                get: { viewModel.selectedPhotoItem },
                set: { viewModel.selectedPhotoItem = $0 }
            ),
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: showPicker) { _, isPresented in
            if !isPresented && !pickerDismissedOnce {
                pickerDismissedOnce = true
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    if !viewModel.hasUnsavedContent {
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: viewModel.hasUnsavedContent) { _, hasContent in
            if hasContent {
                autoSave()
            }
        }
        .onAppear { viewModel.modelContext = modelContext }
    }

    private func autoSave() {
        guard !isSaving else { return }
        isSaving = true
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
