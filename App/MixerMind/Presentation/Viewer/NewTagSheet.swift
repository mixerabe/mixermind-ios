import SwiftUI

struct NewTagSheet: View {
    var onSave: (String) -> Void

    @State private var name = ""
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 12) {
            TextField("Tag name", text: $name)
                .focused($isFocused)
                .textFieldStyle(.plain)
                .font(.body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .onSubmit { save() }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassEffect(in: .capsule)

            Button {
                save()
            } label: {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .glassEffect(in: .circle)
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
        .onAppear { isFocused = true }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
        dismiss()
    }
}
