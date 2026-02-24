import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = HomeViewModel()
    @State private var searchText = ""
    @State private var isSearchMode = false
    @FocusState private var isSearchFocused: Bool
    private let audioCoordinator: AudioPlaybackCoordinator = resolve()
    var onDisconnect: () -> Void

    var body: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { viewMenu }
                ToolbarItem(placement: .primaryAction) { settingsMenu }
            }
            .alert("Disconnect?", isPresented: $viewModel.showDisconnectAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Disconnect", role: .destructive) {
                    onDisconnect()
                }
            } message: {
                Text("Your Supabase project will be disconnected and all local data cleared. You can reconnect anytime.")
            }
            .alert("Save as View", isPresented: $viewModel.showSaveViewAlert) {
                TextField("View name", text: $viewModel.newViewName)
                Button("Cancel", role: .cancel) {
                    viewModel.newViewName = ""
                }
                Button("Save") {
                    let name = viewModel.newViewName.trimmingCharacters(in: .whitespaces)
                    viewModel.newViewName = ""
                    guard !name.isEmpty else { return }
                    Task { await viewModel.saveCurrentAsView(name: name) }
                }
            }
            .alert("Rename View", isPresented: $viewModel.showRenameViewAlert) {
                TextField("View name", text: $viewModel.renameViewName)
                Button("Cancel", role: .cancel) {
                    viewModel.renameViewName = ""
                }
                Button("Save") {
                    let name = viewModel.renameViewName.trimmingCharacters(in: .whitespaces)
                    viewModel.renameViewName = ""
                    guard !name.isEmpty else { return }
                    Task { await viewModel.renameActiveView(name: name) }
                }
            }
            .navigationDestination(for: HomeDestination.self) { dest in
                switch dest {
                case .viewer(let startIndex):
                    MixViewerView(
                        mixes: viewModel.displayedMixes,
                        startIndex: startIndex,
                        onDeleted: { _ in
                            Task { await viewModel.loadMixes(modelContext: modelContext) }
                        }
                    )
                case .createPhoto:
                    CreatePhotoPage()
                case .createURLImport:
                    CreateURLImportPage()
                case .createEmbed:
                    CreateEmbedPage()
                case .createRecordAudio:
                    CreateRecordAudioPage()
                case .createText:
                    CreateTextPage()
                }
            }
            .onChange(of: viewModel.navigationPath) { _, path in
                if path.isEmpty {
                    Task {
                        await viewModel.loadMixes(modelContext: modelContext)
                        viewModel.loadTags(modelContext: modelContext)
                    }
                }
            }
            .task {
                await viewModel.loadMixes(modelContext: modelContext)
                viewModel.loadTags(modelContext: modelContext)
                await viewModel.loadSavedViews()
            }
        }
    }
}

// MARK: - Main Content

extension HomeView {
    @ViewBuilder
    private var mainContent: some View {
        if viewModel.isLoading && viewModel.mixes.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                syncStatusText
            }
        } else {
            VStack(spacing: 0) {
                if !isSearchMode {
                    TagBarView(
                        selectedTags: viewModel.selectedTags,
                        availableTags: viewModel.availableTags,
                        selectedTagIds: viewModel.selectedTagIds,
                        onToggle: { tagId in viewModel.toggleTag(tagId) }
                    )
                }
                if isSearchMode && viewModel.isSearchActive {
                    searchResultsGrid
                } else {
                    mixGrid
                }
            }
        }
    }

    private var mixGrid: some View {
        ScrollView {
            MasonryLayout(columns: 2, spacing: 8) {
                ForEach(Array(viewModel.displayedMixes.enumerated()), id: \.element.id) { index, mix in
                    MasonryMixCard(mix: mix)
                        .onTapGesture {
                            viewModel.navigationPath.append(.viewer(startIndex: index))
                        }
                }
            }
            .padding(.horizontal, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                MiniPlayerBar(coordinator: audioCoordinator).animated()
                bottomBar
            }
        }
        .refreshable {
            await viewModel.loadMixes(modelContext: modelContext)
            viewModel.loadTags(modelContext: modelContext)
            await viewModel.loadSavedViews()
        }
    }

    private var searchResultsGrid: some View {
        ScrollView {
            if viewModel.isSearching {
                ProgressView()
                    .padding(.top, 40)
            } else if viewModel.searchResults.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .padding(.top, 40)
            } else {
                let searchMixes = viewModel.searchMixes
                MasonryLayout(columns: 2, spacing: 8) {
                    ForEach(Array(searchMixes.enumerated()), id: \.element.id) { index, mix in
                        MasonryMixCard(mix: mix)
                            .onTapGesture {
                                // Find the index in the full mixes list for the viewer
                                if let fullIndex = viewModel.mixes.firstIndex(where: { $0.id == mix.id }) {
                                    viewModel.navigationPath.append(.viewer(startIndex: fullIndex))
                                }
                            }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                MiniPlayerBar(coordinator: audioCoordinator).animated()
                bottomBar
            }
        }
    }
}

// MARK: - Sync Status

extension HomeView {
    @ViewBuilder
    private var syncStatusText: some View {
        switch viewModel.syncEngine.syncStatus {
        case .syncing:
            Text("Syncing...")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .downloading(let current, let total):
            Text("Downloading \(current)/\(total)")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        default:
            EmptyView()
        }
    }
}

// MARK: - Toolbar Menus

extension HomeView {
    private var viewMenu: some View {
        Menu {
            // "My Mixes" — active when no view selected
            Button {
                viewModel.deselectView()
            } label: {
                Label("My Mixes", systemImage: viewModel.activeViewId == nil ? "checkmark" : "rectangle.stack")
            }

            // List all saved views
            if !viewModel.savedViews.isEmpty {
                Divider()
                ForEach(viewModel.savedViews) { savedView in
                    Button {
                        viewModel.selectView(savedView)
                    } label: {
                        Label(savedView.name, systemImage: viewModel.activeViewId == savedView.id ? "checkmark" : "line.3.horizontal.decrease")
                    }
                }
            }

            Divider()

            // Contextual actions
            if !viewModel.selectedTagIds.isEmpty && viewModel.activeViewId == nil {
                Button {
                    viewModel.newViewName = ""
                    viewModel.showSaveViewAlert = true
                } label: {
                    Label("Save as View", systemImage: "plus.square")
                }
            }

            if viewModel.hasViewDrifted {
                Button {
                    Task { await viewModel.updateActiveView() }
                } label: {
                    Label("Update View", systemImage: "arrow.triangle.2.circlepath")
                }
            }

            if viewModel.activeView != nil {
                Button {
                    viewModel.renameViewName = viewModel.activeView?.name ?? ""
                    viewModel.showRenameViewAlert = true
                } label: {
                    Label("Rename View", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    if let view = viewModel.activeView {
                        Task { await viewModel.deleteView(view) }
                    }
                } label: {
                    Label("Delete View", systemImage: "trash")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(viewModel.activeView?.name ?? "My Mixes")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 4)
        }
    }

    private var settingsMenu: some View {
        Menu {
            Button {
                audioCoordinator.playMixes(viewModel.displayedMixes)
            } label: {
                Label("Play All", systemImage: "play.fill")
            }
            Divider()
            Button("Disconnect", role: .destructive) {
                viewModel.showDisconnectAlert = true
            }
        } label: {
            Image(systemName: "ellipsis")
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Bottom Bar

extension HomeView {
    private var bottomBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)

                TextField("Search", text: $searchText)
                    .focused($isSearchFocused)
                    .textFieldStyle(.plain)
                    .submitLabel(.search)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                    .onTapGesture {
                        isSearchMode = true
                    }
                    .onChange(of: isSearchFocused) { _, focused in
                        if focused {
                            isSearchMode = true
                        }
                    }
                    .onChange(of: searchText) { _, newValue in
                        if !newValue.isEmpty {
                            isSearchMode = true
                        }
                        viewModel.search(query: newValue)
                    }
                    .onSubmit {
                        viewModel.search(query: searchText)
                    }

                Button(action: clearSearchText) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(searchText.isEmpty ? 0 : 1)
                .allowsHitTesting(!searchText.isEmpty)
            }
            .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52, alignment: .leading)
            .padding(.horizontal, 16)
            .glassEffect(in: .capsule)

            ZStack {
                Button(action: closeSearchMode) {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 52, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glassEffect(in: .circle)
                .opacity(isSearchMode ? 1 : 0)
                .allowsHitTesting(isSearchMode)

                Menu {
                    Button { viewModel.navigationPath.append(.createPhoto) } label: {
                        Label("Gallery", systemImage: "photo.on.rectangle")
                    }
                    Button { viewModel.navigationPath.append(.createURLImport) } label: {
                        Label("Import", systemImage: "play.rectangle")
                    }
                    Button { viewModel.navigationPath.append(.createEmbed) } label: {
                        Label("Embed", systemImage: "link.badge.plus")
                    }
                    Button { viewModel.navigationPath.append(.createRecordAudio) } label: {
                        Label("Record", systemImage: "mic")
                    }
                    Button { viewModel.navigationPath.append(.createText) } label: {
                        Label("Text", systemImage: "textformat")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 52, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glassEffect(in: .circle)
                .opacity(isSearchMode ? 0 : 1)
                .allowsHitTesting(!isSearchMode)
            }
            .frame(width: 52, height: 52)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func clearSearchText() {
        searchText = ""
    }

    private func closeSearchMode() {
        searchText = ""
        isSearchFocused = false
        isSearchMode = false
        viewModel.clearSearch()
    }
}
