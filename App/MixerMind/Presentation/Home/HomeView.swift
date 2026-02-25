import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = HomeViewModel()
    @State private var searchText = ""
    @State private var isSearchMode = false
    @FocusState private var isSearchFocused: Bool
    private let audioCoordinator: AudioPlaybackCoordinator = resolve()
    var onDisconnect: () -> Void

    // Viewer overlay state
    @State private var viewerVM: MixViewerViewModel?
    @State private var isViewerExpanded = false

    // Drag-to-minimize state
    @State private var viewerDragOffset: CGSize = .zero
    @State private var viewerDragScale: CGFloat = 1.0
    @State private var miniPlayerCorner: Corner = .bottomTrailing
    @State private var isExpandingFromMini = false
    @State private var miniDragOffset: CGSize = .zero

    // Yellow rect test
    @State private var showYellowRect = false
    @State private var yellowDragScale: CGFloat = 1.0
    @State private var yellowDragOffset: CGSize = .zero

    // Mini player card dimensions
    private static let miniCardWidth: CGFloat = 136

    /// Mini card height derived from the current mix's crop values.
    private var currentMiniCardHeight: CGFloat {
        guard let vm = viewerVM else { return Self.miniCardWidth * (17.0 / 9.0) }
        let mix = vm.currentMix
        let sy = max(mix.previewScaleY ?? 1.0, 1.2)
        let aspectRatio = 390.0 / (844.0 / sy)
        return Self.miniCardWidth / aspectRatio
    }

    enum Corner {
        case topLeading, topTrailing, bottomLeading, bottomTrailing

        var alignment: Alignment {
            switch self {
            case .topLeading: .topLeading
            case .topTrailing: .topTrailing
            case .bottomLeading: .bottomLeading
            case .bottomTrailing: .bottomTrailing
            }
        }
    }

    var body: some View {
        ZStack {
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

            // Yellow test rect — 16:9, pinned to screen top, drag to scale
            if showYellowRect {
                let screen = UIScreen.main.bounds
                let w = screen.width
                let h = w * (17.0 / 9.0)

                Color.yellow
                    .frame(width: w, height: h)
                    .scaleEffect(yellowDragScale)
                    .offset(yellowDragOffset)
                    .position(x: screen.width / 2, y: h / 2)
                    .overlay(alignment: .leading) {
                        Color.clear
                            .frame(width: 44)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let dx = max(value.translation.width, 0)
                                        let progress = min(dx / (screen.width * 0.5), 1.0)
                                        yellowDragScale = 1.0 - progress * 0.6
                                        yellowDragOffset = CGSize(width: dx * 0.5, height: value.translation.height)
                                    }
                                    .onEnded { _ in
                                        withAnimation(.spring(duration: 0.3)) {
                                            yellowDragScale = 1.0
                                            yellowDragOffset = .zero
                                        }
                                    }
                            )
                    }
                    .ignoresSafeArea()
                    .zIndex(20)
            }

            // Black backdrop — fully opaque when expanded, transparent when mini
            if viewerVM != nil {
                Color.black
                    .ignoresSafeArea()
                    .opacity(isViewerExpanded ? Double(viewerDragScale) : 0)
                    .animation(.spring(duration: 0.35), value: isViewerExpanded)
                    .zIndex(9)
            }

            // Viewer — position-based placement, drag scales from left edge
            if let vm = viewerVM {
                let screen = UIScreen.main.bounds
                let canvasW = screen.width
                let canvasH = canvasW * (17.0 / 9.0)
                let safeTop = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first?.windows.first?.safeAreaInsets.top ?? 0

                MixViewerView(
                    viewModel: vm,
                    onMinimize: { withAnimation(.spring(duration: 0.35)) { isViewerExpanded = false } },
                    onDismiss: dismissViewer,
                    onDeleted: { mixId in viewModel.removeMix(id: mixId) },
                    dragProgress: isViewerExpanded ? viewerDragProgress : 1.0,
                    isMinimized: !isViewerExpanded,
                    safeAreaTop: safeTop,
                    miniVisibleHeight: currentMiniCardHeight
                )
                .frame(width: canvasW, height: canvasH)
                .frame(height: isViewerExpanded ? nil : currentMiniCardHeight / Self.miniTargetScale)
                .clipped()
                .clipShape(.rect(cornerRadius: 16))
                .scaleEffect(isViewerExpanded ? viewerDragScale : Self.miniTargetScale)
                .offset(isViewerExpanded ? viewerDragOffset : .zero)
                .position(
                    x: isViewerExpanded ? canvasW / 2 : miniTargetPosition.x,
                    y: isViewerExpanded ? canvasH / 2 : miniTargetPosition.y
                )
                .overlay(alignment: .leading) {
                    if isViewerExpanded {
                        Color.clear
                            .frame(width: 44)
                            .contentShape(Rectangle())
                            .gesture(viewerDragGesture)
                    }
                }
                .gesture(!isViewerExpanded ? miniCornerDragGesture : nil)
                .onTapGesture { if !isViewerExpanded { expandFromMini() } }
                .ignoresSafeArea()
                .transition(.asymmetric(
                    insertion: isExpandingFromMini ? .identity : .move(edge: .trailing),
                    removal: .identity
                ))
                .animation(.spring(duration: 0.35), value: isViewerExpanded)
                .animation(.spring(duration: 0.35), value: vm.currentMix.id)
                .zIndex(10)

                // Tag bar — independent floating layer above bottom safe area
                if isViewerExpanded && viewerDragProgress == 0 {
                    let safeBottom = UIApplication.shared.connectedScenes
                        .compactMap { $0 as? UIWindowScene }
                        .first?.windows.first?.safeAreaInsets.bottom ?? 0
                    let tagBarY = screen.height - safeBottom - 22

                    ViewerTagBar(viewModel: vm)
                        .position(x: canvasW / 2, y: tagBarY)
                        .ignoresSafeArea()
                        .zIndex(11)
                }
            }
        }
        .animation(.spring(duration: 0.35), value: isViewerExpanded)
    }

    // MARK: - Viewer Helpers

    /// Progress from 0 (fullscreen) to 1 (minimized), derived from current drag scale.
    private var viewerDragProgress: CGFloat {
        // scale goes from 1.0 → ~0.15 (miniScale), progress goes 0→1
        let miniScale = Self.miniTargetScale
        guard miniScale < 1 else { return 0 }
        return min(max((1 - viewerDragScale) / (1 - miniScale), 0), 1)
    }

    /// The scale that makes the fullscreen viewer match the mini player card width.
    private static var miniTargetScale: CGFloat {
        let screen = UIScreen.main.bounds
        guard screen.width > 0 else { return 0.3 }
        return miniCardWidth / screen.width
    }


    /// Absolute screen position for the mini player center, including drag.
    private var miniTargetPosition: CGPoint {
        let screen = UIScreen.main.bounds
        let padding: CGFloat = 16
        let bottomBarClearance: CGFloat = 100
        let cardW = Self.miniCardWidth
        let cardH = currentMiniCardHeight

        let targetX: CGFloat
        let targetY: CGFloat

        switch miniPlayerCorner {
        case .bottomTrailing:
            targetX = screen.width - padding - cardW / 2
            targetY = screen.height - padding - bottomBarClearance - cardH / 2
        case .bottomLeading:
            targetX = padding + cardW / 2
            targetY = screen.height - padding - bottomBarClearance - cardH / 2
        case .topTrailing:
            targetX = screen.width - padding - cardW / 2
            targetY = padding + cardH / 2
        case .topLeading:
            targetX = padding + cardW / 2
            targetY = padding + cardH / 2
        }

        return CGPoint(
            x: targetX + miniDragOffset.width,
            y: targetY + miniDragOffset.height
        )
    }

    /// Corner-drag gesture for repositioning the mini viewer.
    private var miniCornerDragGesture: some Gesture {
        DragGesture()
            .onChanged { miniDragOffset = $0.translation }
            .onEnded { value in
                let isRight = value.predictedEndTranslation.width > 0
                let isDown = value.predictedEndTranslation.height > 0
                withAnimation(.spring(duration: 0.3)) {
                    switch (isRight, isDown) {
                    case (true, true): miniPlayerCorner = .bottomTrailing
                    case (true, false): miniPlayerCorner = .topTrailing
                    case (false, true): miniPlayerCorner = .bottomLeading
                    case (false, false): miniPlayerCorner = .topLeading
                    }
                    miniDragOffset = .zero
                }
            }
    }

    private var viewerDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                let screen = UIScreen.main.bounds

                // Progress: 0→1 over half the screen width
                let progress = min(max(dx, 0) / (screen.width * 0.5), 1.0)

                // Just scale and move — no frame height changes
                let targetScale = Self.miniCardWidth / screen.width
                viewerDragScale = 1.0 - progress * (1.0 - targetScale)
                viewerDragOffset = CGSize(width: dx * 0.5, height: dy)
            }
            .onEnded { value in
                let dx = value.predictedEndTranslation.width
                if dx > 150 {
                    // Commit to mini state
                    withAnimation(.spring(duration: 0.35)) {
                        isViewerExpanded = false
                        viewerDragOffset = .zero
                        viewerDragScale = 1.0
                    }
                } else {
                    // Snap back to fullscreen
                    withAnimation(.spring(duration: 0.3)) {
                        viewerDragOffset = .zero
                        viewerDragScale = 1.0
                    }
                }
            }
    }

    private func expandFromMini() {
        isExpandingFromMini = true
        withAnimation(.spring(duration: 0.35)) {
            isViewerExpanded = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isExpandingFromMini = false
        }
    }

    private func openViewer(mixes: [Mix], startIndex: Int) {
        // Dismiss any existing viewer first so SwiftUI recreates the view tree
        if viewerVM != nil {
            audioCoordinator.stop()
            viewerVM = nil
        }
        let vm = MixViewerViewModel(mixes: mixes, startIndex: startIndex)
        viewerVM = vm
        withAnimation(.spring(duration: 0.35)) { isViewerExpanded = true }
    }

    private func dismissViewer() {
        audioCoordinator.stop()
        withAnimation(.spring(duration: 0.35)) {
            viewerVM = nil
            isViewerExpanded = false
        }
    }

}

// MARK: - Main Content

extension HomeView {
    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            TagBarView(
                selectedTags: viewModel.selectedTags,
                availableTags: viewModel.availableTags,
                selectedTagIds: viewModel.selectedTagIds,
                onToggle: { tagId in viewModel.toggleTag(tagId) }
            )
            if isSearchMode && viewModel.isSearchActive {
                searchResultsGrid
            } else {
                mixGrid
            }
        }
        .overlay {
            if viewModel.isLoading && viewModel.mixes.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    syncStatusText
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            }
        }
    }

    private var mixGrid: some View {
        ScrollView {
            MasonryLayout(columns: 2, spacing: 8) {
                ForEach(viewModel.displayedMixes) { mix in
                    MasonryMixCard(mix: mix)
                        .onTapGesture {
                            let mixes = viewModel.displayedMixes
                            let index = mixes.firstIndex(where: { $0.id == mix.id }) ?? 0
                            openViewer(mixes: mixes, startIndex: index)
                        }
                }
            }
            .padding(.horizontal, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if audioCoordinator.currentTrack != nil, viewerVM == nil {
                    MiniPlayerBar(coordinator: audioCoordinator).animated()
                }
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
                    ForEach(searchMixes) { mix in
                        MasonryMixCard(mix: mix)
                            .onTapGesture {
                                if let fullIndex = viewModel.mixes.firstIndex(where: { $0.id == mix.id }) {
                                    openViewer(mixes: viewModel.mixes, startIndex: fullIndex)
                                }
                            }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if audioCoordinator.currentTrack != nil, viewerVM == nil {
                    MiniPlayerBar(coordinator: audioCoordinator).animated()
                }
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
            // "My Mixes" -- active when no view selected
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
            Button("Show Yellow Rect") {
                withAnimation { showYellowRect.toggle() }
            }
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
