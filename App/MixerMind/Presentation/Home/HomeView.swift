import SwiftUI

struct HomeView: View {
    @State private var viewModel = HomeViewModel()
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
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
                            Task { await viewModel.loadMixes() }
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
                case .createAppleMusic:
                    CreateAppleMusicPage()
                case .createText:
                    CreateTextPage()
                }
            }
            .onChange(of: viewModel.navigationPath) { _, path in
                if path.isEmpty {
                    Task {
                        await viewModel.loadMixes()
                        await viewModel.loadTags()
                    }
                }
            }
            .task {
                await viewModel.loadMixes()
                await viewModel.loadTags()
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
            ProgressView()
        } else {
            VStack(spacing: 0) {
                TagBarView(
                    selectedTags: viewModel.selectedTags,
                    availableTags: viewModel.availableTags,
                    selectedTagIds: viewModel.selectedTagIds,
                    onToggle: { tagId in viewModel.toggleTag(tagId) },
                    onClearAll: { viewModel.clearTagFilter() }
                )
                mixGrid
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
            bottomBar
        }
        .refreshable {
            await viewModel.loadMixes()
            await viewModel.loadTags()
            await viewModel.loadSavedViews()
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

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        isSearchFocused = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(in: .capsule)

            if isSearchFocused {
                Button {
                    isSearchFocused = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .glassEffect(in: .circle)
            } else {
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
                    Button { viewModel.navigationPath.append(.createAppleMusic) } label: {
                        Label("Music", systemImage: "music.note")
                    }
                    Button { viewModel.navigationPath.append(.createText) } label: {
                        Label("Text", systemImage: "textformat")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .glassEffect(in: .circle)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}
