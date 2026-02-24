import SwiftUI

struct TagSelectionSheet: View {
    @Bindable var viewModel: CreateMixViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var newTagName = ""
    @State private var isAddingTag = false
    @State private var renameTagId: UUID?
    @State private var renameText = ""
    @State private var showRenameAlert = false

    private var selectedTags: [Tag] {
        viewModel.allTags.filter { viewModel.selectedTagIds.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Selected tags at top
                    if !selectedTags.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Selected")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)

                            FlowLayout(spacing: 8) {
                                ForEach(selectedTags) { tag in
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            viewModel.toggleTag(tag.id)
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text("#\(tag.name)")
                                            Image(systemName: "xmark")
                                                .font(.caption2.weight(.bold))
                                        }
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 9)
                                        .tint(.blue)
                                        .glassEffect(in: .capsule)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    // All tags as flow chips
                    VStack(alignment: .leading, spacing: 8) {
                        Text("All Tags")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)

                        FlowLayout(spacing: 8) {
                            // Add Tag button
                            if isAddingTag {
                                HStack(spacing: 6) {
                                    TextField("#newtag", text: $newTagName)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .frame(width: 100)
                                        .onSubmit { addTag() }

                                    Button {
                                        addTag()
                                    } label: {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                    }
                                    .disabled(sanitized(newTagName).isEmpty)

                                    Button {
                                        isAddingTag = false
                                        newTagName = ""
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .glassEffect(in: .capsule)
                            } else {
                                Button {
                                    isAddingTag = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus")
                                            .font(.caption.weight(.bold))
                                        Text("Create")
                                    }
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                }
                                .buttonStyle(.plain)
                                .tint(.accentColor)
                                .glassEffect(in: .capsule)
                            }

                            // Tag chips — sorted by usage frequency
                            ForEach(viewModel.unselectedTagsByFrequency) { tag in
                                tagChip(tag)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .alert("Rename Tag", isPresented: $showRenameAlert) {
                TextField("Tag name", text: $renameText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    guard let id = renameTagId else { return }
                    Task { await viewModel.renameTag(id: id, newName: renameText) }
                }
            }
        }
    }

    private func tagChip(_ tag: Tag) -> some View {
        let isSelected = viewModel.selectedTagIds.contains(tag.id)

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.toggleTag(tag.id)
            }
        } label: {
            Text("#\(tag.name)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .tint(isSelected ? .blue : nil)
        .glassEffect(in: .capsule)
        .contextMenu {
            Button {
                renameTagId = tag.id
                renameText = tag.name
                showRenameAlert = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button(role: .destructive) {
                Task { await viewModel.deleteTag(id: tag.id) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func sanitized(_ name: String) -> String {
        name.replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private func addTag() {
        let name = newTagName
        newTagName = ""
        isAddingTag = false
        guard !sanitized(name).isEmpty else { return }
        Task { _ = await viewModel.createNewTag(name: name) }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            height += rowHeight
            if i < rows.count - 1 { height += spacing }
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            var x = bounds.minX
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y + (rowHeight - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var currentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentWidth + size.width > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentWidth = 0
            }
            rows[rows.count - 1].append(subview)
            currentWidth += size.width + spacing
        }
        return rows
    }
}
