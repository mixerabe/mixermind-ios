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

    // Hero expand animation state
    @State private var heroMix: Mix?
    @State private var heroSourceFrame: CGRect = .zero
    @State private var heroExpanded = false
    @State private var heroFinished = false


    // Card frame tracking for hero animations
    @State private var cardFrames: [UUID: CGRect] = [:]
    @State private var ignoreCardTaps = false

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
                        viewModel.reloadFromLocal(modelContext: modelContext)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .mixCreationStatusChanged)) { _ in
                    viewModel.reloadFromLocal(modelContext: modelContext)
                }
                .task {
                    await viewModel.loadMixes(modelContext: modelContext)
                    viewModel.loadTags(modelContext: modelContext)
                    await viewModel.loadSavedViews()
                }
            }

            // Black backdrop — fully opaque when expanded, transparent when mini
            // Hidden during hero animation, shown instantly when hero finishes
            if viewerVM != nil, (heroMix == nil || heroFinished) {
                Color.black
                    .ignoresSafeArea()
                    .opacity(isViewerExpanded ? Double(viewerDragScale) : 0)
                    .animation(.spring(duration: 0.35), value: isViewerExpanded)
                    .zIndex(9)
            }

            // Hero expand overlay — card screenshot expanding to fullscreen
            // Appears instantly at card position, animates to canvas position
            // while the Y crop reduces from card crop to zero (full 9:17 image).
            if let heroMix, !heroFinished, let url = heroMix.screenshotUrl {
                HeroExpandOverlay(
                    screenshotURL: URL(string: url)!,
                    expanded: heroExpanded,
                    sourceFrame: heroSourceFrame,
                    previewScaleY: heroMix.previewScaleY ?? 1.0
                )
                .transition(.identity)
                .ignoresSafeArea()
                .zIndex(15)
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
                .offset(isViewerExpanded ? viewerDragOffset : miniDragOffset)
                .position(
                    x: isViewerExpanded ? canvasW / 2 : miniTargetPosition.x,
                    y: isViewerExpanded ? canvasH / 2 : miniTargetPosition.y
                )
                .overlay(alignment: .topLeading) {
                    if isViewerExpanded {
                        Color.clear
                            .frame(width: 44, height: canvasH - 44)
                            .contentShape(Rectangle())
                            .gesture(viewerDragGesture)
                    }
                }
                .allowsHitTesting(heroMix == nil || heroFinished)
                .opacity(heroMix != nil && !heroFinished ? 0 : 1)
                .ignoresSafeArea()
                .transition(.asymmetric(
                    insertion: (isExpandingFromMini || heroMix != nil) ? .identity : .move(edge: .trailing),
                    removal: .identity
                ))
                .animation(.spring(duration: 0.35), value: isViewerExpanded)
                .animation(.spring(duration: 0.35), value: vm.currentMix.id)
                .zIndex(10)

                // Mini drag target — inset from top/bottom to leave buttons exposed
                if !isViewerExpanded {
                    let inset: CGFloat = 38
                    Color.clear
                        .frame(width: Self.miniCardWidth, height: max(currentMiniCardHeight - inset * 2, 20))
                        .contentShape(.rect)
                        .offset(miniDragOffset)
                        .position(x: miniTargetPosition.x, y: miniTargetPosition.y)
                        .gesture(miniCornerDragGesture)
                        .onTapGesture { expandFromMini() }
                        .ignoresSafeArea()
                        .zIndex(12)
                }

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
        .coordinateSpace(name: "home-root")
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
        let safeTop = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 0
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
            targetY = safeTop - 8 + cardH / 2
        case .topLeading:
            targetX = padding + cardW / 2
            targetY = safeTop - 8 + cardH / 2
        }

        return CGPoint(x: targetX, y: targetY)
    }

    /// Drag gesture for the mini viewer — snap to closest corner on release.
    private var miniCornerDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                miniDragOffset = value.translation
            }
            .onEnded { value in
                // Where the card center ends up
                let landing = CGPoint(
                    x: miniTargetPosition.x + value.predictedEndTranslation.width,
                    y: miniTargetPosition.y + value.predictedEndTranslation.height
                )
                // Snap to closest corner
                let screen = UIScreen.main.bounds
                let midX = screen.width / 2
                let midY = screen.height / 2
                let isRight = landing.x > midX
                let isDown = landing.y > midY
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
        miniPlayerCorner = .bottomTrailing
        withAnimation(.spring(duration: 0.35)) {
            isViewerExpanded = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isExpandingFromMini = false
        }
    }

    private func openViewer(mixes: [Mix], startIndex: Int) {
        if viewerVM != nil {
            killViewer()
            DispatchQueue.main.async {
                performOpenViewer(mixes: mixes, startIndex: startIndex)
            }
        } else {
            performOpenViewer(mixes: mixes, startIndex: startIndex)
        }
    }

    private func performOpenViewer(mixes: [Mix], startIndex: Int) {
        miniPlayerCorner = .bottomTrailing
        let vm = MixViewerViewModel(mixes: mixes, startIndex: startIndex)
        viewerVM = vm
        withAnimation(.spring(duration: 0.35)) { isViewerExpanded = true }
    }

    private func openViewerWithHero(mix: Mix, frame: CGRect, mixes: [Mix], startIndex: Int) {
        if viewerVM != nil {
            killViewer()
            DispatchQueue.main.async {
                performOpenViewerWithHero(mix: mix, frame: frame, mixes: mixes, startIndex: startIndex)
            }
        } else {
            performOpenViewerWithHero(mix: mix, frame: frame, mixes: mixes, startIndex: startIndex)
        }
    }

    private func performOpenViewerWithHero(mix: Mix, frame: CGRect, mixes: [Mix], startIndex: Int) {
        // 1. Set hero state — appears instantly at card position
        heroMix = mix
        heroSourceFrame = frame
        heroExpanded = false
        heroFinished = false

        // 2. Create viewer VM now so it has time to render while hero animates.
        //    It's hidden behind the hero (zIndex 15 > 10).
        let vm = MixViewerViewModel(mixes: mixes, startIndex: startIndex)
        viewerVM = vm
        isViewerExpanded = true

        // 3. Next runloop: animate hero from card position → canvas position
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            withAnimation(.spring(duration: 0.25, bounce: 0.05)) {
                heroExpanded = true
            }
        }

        // 4. After animation completes: remove hero, viewer is already there
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            heroFinished = true
            heroMix = nil
        }
    }

    /// Instantly kill the current viewer with no animation.
    private func killViewer() {
        audioCoordinator.stop()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            viewerVM = nil
            isViewerExpanded = false
        }
    }

    private func dismissViewer() {
        ignoreCardTaps = true
        audioCoordinator.stop()
        withAnimation(.spring(duration: 0.35)) {
            viewerVM = nil
            isViewerExpanded = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            ignoreCardTaps = false
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if audioCoordinator.currentTrack != nil, viewerVM == nil {
                    MiniPlayerBar(coordinator: audioCoordinator).animated()
                }
                bottomBar
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
                        .background {
                            GeometryReader { geo in
                                Color.clear.onChange(of: geo.frame(in: .named("home-root"))) { _, frame in
                                    cardFrames[mix.id] = frame
                                }.onAppear {
                                    cardFrames[mix.id] = geo.frame(in: .named("home-root"))
                                }
                            }
                        }
                        .contentShape(.rect)
                        .onTapGesture {
                            guard !ignoreCardTaps else { return }
                            if mix.creationStatus == "creating" { return }
                            if mix.creationStatus == "failed" { return }
                            let mixes = viewModel.displayedMixes.filter { $0.creationStatus == nil }
                            guard let index = mixes.firstIndex(where: { $0.id == mix.id }) else { return }
                            if mix.screenshotUrl != nil {
                                openViewerWithHero(mix: mix, frame: cardFrames[mix.id] ?? .zero, mixes: mixes, startIndex: index)
                            } else {
                                openViewer(mixes: mixes, startIndex: index)
                            }
                        }
                        .contextMenu {
                            if mix.creationStatus == "failed" {
                                Button {
                                    let service: MixCreationService = resolve()
                                    service.retry(mixId: mix.id, modelContext: modelContext)
                                } label: {
                                    Label("Retry", systemImage: "arrow.clockwise")
                                }
                            }
                            Button(role: .destructive) {
                                if mix.creationStatus != nil {
                                    let service: MixCreationService = resolve()
                                    service.discard(mixId: mix.id, modelContext: modelContext)
                                } else {
                                    Task { await viewModel.deleteMix(mix, modelContext: modelContext) }
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(.horizontal, 8)
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
            } else if viewModel.searchResultIds.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .padding(.top, 40)
            } else {
                let searchMixes = viewModel.searchMixes
                MasonryLayout(columns: 2, spacing: 8) {
                    ForEach(searchMixes) { mix in
                        MasonryMixCard(mix: mix)
                            .background {
                                GeometryReader { geo in
                                    Color.clear.onChange(of: geo.frame(in: .named("home-root"))) { _, frame in
                                        cardFrames[mix.id] = frame
                                    }.onAppear {
                                        cardFrames[mix.id] = geo.frame(in: .named("home-root"))
                                    }
                                }
                            }
                            .contentShape(.rect)
                            .onTapGesture {
                                guard !ignoreCardTaps else { return }
                                if let fullIndex = viewModel.mixes.firstIndex(where: { $0.id == mix.id }) {
                                    if mix.screenshotUrl != nil {
                                        openViewerWithHero(mix: mix, frame: cardFrames[mix.id] ?? .zero, mixes: viewModel.mixes, startIndex: fullIndex)
                                    } else {
                                        openViewer(mixes: viewModel.mixes, startIndex: fullIndex)
                                    }
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task { await viewModel.deleteMix(mix, modelContext: modelContext) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.horizontal, 8)
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
                        viewModel.search(query: newValue, modelContext: modelContext)
                    }
                    .onSubmit {
                        viewModel.search(query: searchText, modelContext: modelContext)
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
                        .glassEffect(in: .circle)
                }
                .buttonStyle(.plain)
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
