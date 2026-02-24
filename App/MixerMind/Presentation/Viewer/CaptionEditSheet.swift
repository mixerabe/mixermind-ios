import SwiftUI

struct CaptionEditSheet: View {
    @Binding var text: String
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack {
                TextField("Add a caption...", text: $text, axis: .vertical)
                    .focused($isFocused)
                    .lineLimit(1...6)
                    .padding()

                Spacer()
            }
            .navigationTitle("Caption")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                }
            }
            .onAppear {
                isFocused = true
            }
        }
    }
}
