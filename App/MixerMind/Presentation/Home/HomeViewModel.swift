import SwiftUI

enum HomeDestination: Hashable {
    case viewer(startIndex: Int)
    case createPhoto, createURLImport, createEmbed
    case createRecordAudio, createAppleMusic, createText
}

@Observable @MainActor
final class HomeViewModel {
    var mixes: [Mix] = []
    var isLoading = false
    var errorMessage: String?
    var navigationPath: [HomeDestination] = []
    var showDisconnectAlert = false

    // MARK: - Tags (local progressive narrowing)

    var allTags: [Tag] = []
    var selectedTagIds: Set<UUID> = []
    private var selectedTagOrder: [UUID] = []   // insertion-ordered IDs

    /// mix_id -> set of tag_ids — loaded once, used for all local filtering
    private var mixTagMap: [UUID: Set<UUID>] = [:]

    /// Mixes that match ALL selected tags (intersection)
    var displayedMixes: [Mix] {
        guard !selectedTagIds.isEmpty else { return mixes }
        return mixes.filter { mix in
            let mixTags = mixTagMap[mix.id] ?? []
            return selectedTagIds.isSubset(of: mixTags)
        }
    }

    /// Tags that still appear on the current filtered mixes — progressive narrowing.
    var availableTags: [TagWithFrequency] {
        let currentMixes = displayedMixes
        let currentMixIds = Set(currentMixes.map(\.id))

        var counts: [UUID: Int] = [:]
        for mixId in currentMixIds {
            if let tagIds = mixTagMap[mixId] {
                for tagId in tagIds {
                    if !selectedTagIds.contains(tagId) {
                        counts[tagId, default: 0] += 1
                    }
                }
            }
        }

        let tagLookup = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0) })

        return counts.compactMap { tagId, count in
            guard let tag = tagLookup[tagId] else { return nil }
            return TagWithFrequency(tag: tag, frequency: count)
        }.sorted {
            $0.frequency != $1.frequency ? $0.frequency > $1.frequency : $0.name < $1.name
        }
    }

    /// Currently selected tags as TagWithFrequency (for display in the bar)
    var selectedTags: [TagWithFrequency] {
        let tagLookup = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0) })
        return selectedTagOrder.compactMap { tagId in
            guard let tag = tagLookup[tagId] else { return nil }
            return TagWithFrequency(tag: tag, frequency: 0)
        }
    }

    // MARK: - Saved Views

    var savedViews: [SavedView] = []
    var activeViewId: UUID?

    // Alert state
    var showSaveViewAlert = false
    var showRenameViewAlert = false
    var newViewName = ""
    var renameViewName = ""

    var activeView: SavedView? { savedViews.first { $0.id == activeViewId } }

    /// True when a view is active but the user has changed tags since selecting it
    var hasViewDrifted: Bool {
        guard let view = activeView else { return false }
        return Set(view.tagIds) != selectedTagIds
    }

    private let repo: MixRepository = resolve()
    private let tagRepo: TagRepository = resolve()
    private let savedViewRepo: SavedViewRepository = resolve()

    func loadMixes() async {
        isLoading = true
        errorMessage = nil
        do {
            mixes = try await repo.listMixes()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadTags() async {
        do {
            let tags = try await tagRepo.listTags()
            allTags = tags

            let allRows: [MixTagRow] = try await tagRepo.allMixTagRows()
            var map: [UUID: Set<UUID>] = [:]
            for row in allRows {
                map[row.mixId, default: []].insert(row.tagId)
            }
            mixTagMap = map

            let validIds = Set(tags.map(\.id))
            selectedTagIds.formIntersection(validIds)

            let tagLookup = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
            for i in mixes.indices {
                let tagIds = mixTagMap[mixes[i].id] ?? []
                mixes[i].tags = tagIds.compactMap { tagLookup[$0] }
            }
        } catch {}
    }

    func toggleTag(_ tagId: UUID) {
        // Don't clear activeViewId — let it drift so "Update View" appears
        if selectedTagIds.contains(tagId) {
            selectedTagIds.remove(tagId)
            selectedTagOrder.removeAll { $0 == tagId }
        } else {
            selectedTagIds.insert(tagId)
            selectedTagOrder.append(tagId)
        }
    }

    func clearTagFilter() {
        selectedTagIds.removeAll()
        selectedTagOrder.removeAll()
    }

    // MARK: - Saved View Operations

    func loadSavedViews() async {
        do {
            savedViews = try await savedViewRepo.listSavedViews()
        } catch {}
    }

    func selectView(_ view: SavedView) {
        activeViewId = view.id
        selectedTagIds = Set(view.tagIds)
        selectedTagOrder = view.tagIds
    }

    func deselectView() {
        activeViewId = nil
        selectedTagIds.removeAll()
        selectedTagOrder.removeAll()
    }

    func deleteView(_ view: SavedView) async {
        do {
            try await savedViewRepo.deleteSavedView(id: view.id)
            savedViews.removeAll { $0.id == view.id }
            if activeViewId == view.id {
                deselectView()
            }
        } catch {}
    }

    func saveCurrentAsView(name: String) async {
        do {
            let created = try await savedViewRepo.createSavedView(
                name: name,
                tagIds: Array(selectedTagIds)
            )
            await loadSavedViews()
            activeViewId = created.id
        } catch {}
    }

    func updateActiveView() async {
        guard let viewId = activeViewId else { return }
        do {
            _ = try await savedViewRepo.updateTagIds(
                id: viewId,
                tagIds: Array(selectedTagIds)
            )
            await loadSavedViews()
        } catch {}
    }

    func renameActiveView(name: String) async {
        guard let viewId = activeViewId else { return }
        do {
            _ = try await savedViewRepo.updateName(id: viewId, name: name)
            await loadSavedViews()
        } catch {}
    }
}
