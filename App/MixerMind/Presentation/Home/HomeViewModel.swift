import SwiftUI
import SwiftData

enum HomeDestination: Hashable {
    case createPhoto, createURLImport, createEmbed
    case createRecordAudio, createText
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

    // MARK: - Search

    var searchResultIds: [UUID] = []
    var isSearching = false
    var isSearchActive = false
    private var searchTask: Task<Void, Never>?

    func search(query: String, modelContext: ModelContext) {
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
                    modelContext: modelContext
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

    func loadMixes(modelContext: ModelContext) async {
        isLoading = true
        errorMessage = nil

        // Sync with Supabase (downloads new media, removes deleted)
        await syncEngine.sync(modelContext: modelContext)

        // Read from SwiftData (propagate creationStatus)
        do {
            let descriptor = FetchDescriptor<LocalMix>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            let localMixes = try modelContext.fetch(descriptor)
            mixes = localMixes.map { local in
                var mix = local.toMix()
                mix.creationStatus = local.creationStatus
                return mix
            }
        } catch {
            // Fallback: try direct from Supabase
            do {
                mixes = try await repo.listMixes()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    /// Fast local-only reload — no network. Used when returning from create page
    /// and when background creation status changes.
    func reloadFromLocal(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<LocalMix>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let localMixes = try? modelContext.fetch(descriptor) else { return }
        mixes = localMixes.map { local in
            var mix = local.toMix()
            mix.creationStatus = local.creationStatus
            return mix
        }
        loadTags(modelContext: modelContext)
    }

    func loadTags(modelContext: ModelContext) {
        do {
            let localTags = try modelContext.fetch(FetchDescriptor<LocalTag>())
            allTags = localTags.map { $0.toTag() }

            let localMixTags = try modelContext.fetch(FetchDescriptor<LocalMixTag>())
            var map: [UUID: Set<UUID>] = [:]
            for row in localMixTags {
                map[row.mixId, default: []].insert(row.tagId)
            }
            mixTagMap = map

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

    func deleteMix(_ mix: Mix, modelContext: ModelContext) async {
        let mixId = mix.id

        // Remove from local array
        mixes.removeAll { $0.id == mixId }

        // Delete from SwiftData + local files
        if let local = try? modelContext.fetch(FetchDescriptor<LocalMix>()).first(where: { $0.mixId == mixId }) {
            let fileManager = LocalFileManager.shared
            let paths = [
                local.localTtsAudioPath, local.localPhotoPath, local.localPhotoThumbnailPath,
                local.localVideoPath, local.localVideoThumbnailPath, local.localImportMediaPath,
                local.localImportThumbnailPath, local.localImportAudioPath, local.localEmbedOgImagePath,
                local.localAudioPath, local.localScreenshotPath,
            ]
            for path in paths {
                if let path { fileManager.deleteFile(at: path) }
            }
            modelContext.delete(local)
        }
        if let rows = try? modelContext.fetch(FetchDescriptor<LocalMixTag>()) {
            for row in rows where row.mixId == mixId {
                modelContext.delete(row)
            }
        }
        try? modelContext.save()

        // Fire-and-forget Supabase
        let repo: MixRepository = resolve()
        Task { try? await repo.deleteMix(id: mixId) }
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
