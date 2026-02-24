import SwiftUI

struct TagBarView: View {
    let selectedTags: [TagWithFrequency]
    let availableTags: [TagWithFrequency]
    let selectedTagIds: Set<UUID>
    var onToggle: (UUID) -> Void
    var onClearAll: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" chip — selected when no tags active
                chip(label: "All", isSelected: selectedTagIds.isEmpty) {
                    onClearAll()
                }

                // Selected tags first (so user sees what's active)
                ForEach(selectedTags) { tagItem in
                    chip(label: "#\(tagItem.name)", isSelected: true) {
                        onToggle(tagItem.id)
                    }
                }

                // Then available (unselected) tags that still produce results
                ForEach(availableTags) { tagItem in
                    chip(label: "#\(tagItem.name)", isSelected: false) {
                        onToggle(tagItem.id)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func chip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.accentColor : Color.clear, in: .capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(in: .capsule)
    }
}
