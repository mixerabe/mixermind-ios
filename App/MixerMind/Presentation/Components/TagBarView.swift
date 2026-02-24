import SwiftUI

struct TagBarView: View {
    let selectedTags: [TagWithFrequency]
    let availableTags: [TagWithFrequency]
    let selectedTagIds: Set<UUID>
    var onToggle: (UUID) -> Void

    /// Selected tags first, then available sorted by frequency then name
    private var allTags: [TagWithFrequency] {
        selectedTags + availableTags.sorted {
            $0.frequency != $1.frequency ? $0.frequency > $1.frequency : $0.name < $1.name
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(allTags) { tagItem in
                    chip(label: "#\(tagItem.name)", isSelected: selectedTagIds.contains(tagItem.id)) {
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
                .foregroundStyle(isSelected ? Color.black : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.white : Color.clear, in: .capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(in: .capsule)
    }
}
