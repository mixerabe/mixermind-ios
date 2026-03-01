import SwiftUI
import CoreData

@Observable @MainActor
final class HomeViewModel {
    var mixes: [Mix] = []
    var isLoading = false
    var errorMessage: String?
    var navigationPath = NavigationPath()

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

    // MARK: - Search

    var searchResultIds: [UUID] = []
    var isSearching = false
    var isSearchActive = false
    private var searchTask: Task<Void, Never>?

    func search(query: String, context: NSManagedObjectContext) {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResultIds = []
            isSearching = false
            isSearchActive = false
            return
        }

        isSearchActive = true
        isSearching = true

        let tagFilter = selectedTagIds
        let tagMap = mixTagMap
        searchTask = Task {
            // Debounce: wait 300ms before searching
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            do {
                let results = try await SearchService.search(
                    query: trimmed,
                    tagIds: tagFilter,
                    mixTagMap: tagMap,
                    context: context
                )
                guard !Task.isCancelled else { return }
                self.searchResultIds = results.map(\.id)
            } catch {
                guard !Task.isCancelled else { return }
                self.searchResultIds = []
            }
            self.isSearching = false
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchResultIds = []
        isSearching = false
        isSearchActive = false
    }

    /// Map search results to full Mix objects from the local cache for navigation
    var searchMixes: [Mix] {
        let mixLookup = Dictionary(uniqueKeysWithValues: mixes.map { ($0.id, $0) })
        return searchResultIds.compactMap { mixLookup[$0] }
    }

    private let repo: MixRepository = resolve()
    private let tagRepo: TagRepository = resolve()
    private let savedViewRepo: SavedViewRepository = resolve()
    let syncEngine: SyncEngine = resolve()

    func loadMixes(context: NSManagedObjectContext) async {
        isLoading = true
        errorMessage = nil

        // Run local tasks (generate missing embeddings, populate silence placeholders)
        await syncEngine.sync(context: context)

        do {
            mixes = try repo.listMixesWithTags(context: context)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Sync tag changes from the viewer VM back into home state.
    func syncFromViewer(_ viewerMixes: [Mix], context: NSManagedObjectContext) {
        let updated = Dictionary(uniqueKeysWithValues: viewerMixes.map { ($0.id, $0) })
        for i in mixes.indices {
            if let m = updated[mixes[i].id] {
                mixes[i].tags = m.tags
            }
        }
        loadTags(context: context)
    }

    /// Fast local-only reload. Used when returning from create page.
    func reloadFromLocal(context: NSManagedObjectContext) {
        do {
            mixes = try repo.listMixesWithTags(context: context)
        } catch {}
        loadTags(context: context)
    }

    func loadTags(context: NSManagedObjectContext) {
        do {
            allTags = try tagRepo.listTags(context: context)
            mixTagMap = try tagRepo.tagMap(context: context)

            let validIds = Set(allTags.map(\.id))
            selectedTagIds.formIntersection(validIds)

            let tagLookup = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0) })
            for i in mixes.indices {
                let tagIds = mixTagMap[mixes[i].id] ?? []
                mixes[i].tags = tagIds.compactMap { tagLookup[$0] }
            }
        } catch {}
    }

    func removeMix(id: UUID) {
        mixes.removeAll { $0.id == id }
    }

    func deleteMix(_ mix: Mix, context: NSManagedObjectContext) {
        let mixId = mix.id

        // Remove from local array
        mixes.removeAll { $0.id == mixId }

        // Delete from Core Data + local files
        try? repo.deleteMix(id: mixId, context: context)
    }

    func toggleTag(_ tagId: UUID) {
        if selectedTagIds.contains(tagId) {
            selectedTagIds.remove(tagId)
            selectedTagOrder.removeAll { $0 == tagId }
        } else {
            selectedTagIds.insert(tagId)
            selectedTagOrder.append(tagId)
        }
        // No tags left = back to "My Mixes"
        if selectedTagIds.isEmpty {
            activeViewId = nil
        }
    }

    // MARK: - Saved View Operations

    func loadSavedViews(context: NSManagedObjectContext) {
        do {
            savedViews = try savedViewRepo.listSavedViews(context: context)
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

    func deleteView(_ view: SavedView, context: NSManagedObjectContext) {
        do {
            try savedViewRepo.deleteSavedView(id: view.id, context: context)
            savedViews.removeAll { $0.id == view.id }
            if activeViewId == view.id {
                deselectView()
            }
        } catch {}
    }

    func saveCurrentAsView(name: String, context: NSManagedObjectContext) {
        do {
            let created = try savedViewRepo.createSavedView(
                name: name,
                tagIds: Array(selectedTagIds),
                context: context
            )
            loadSavedViews(context: context)
            activeViewId = created.id
        } catch {}
    }

    func updateActiveView(context: NSManagedObjectContext) {
        guard let viewId = activeViewId else { return }
        do {
            _ = try savedViewRepo.updateTagIds(
                id: viewId,
                tagIds: Array(selectedTagIds),
                context: context
            )
            loadSavedViews(context: context)
        } catch {}
    }

    func renameActiveView(name: String, context: NSManagedObjectContext) {
        guard let viewId = activeViewId else { return }
        do {
            _ = try savedViewRepo.updateName(id: viewId, name: name, context: context)
            loadSavedViews(context: context)
        } catch {}
    }
}
