import SwiftUI

struct HomeView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @State private var viewModel = HomeViewModel()
    @State private var searchText = ""
    @State private var isSearchMode = false
    @FocusState private var isSearchFocused: Bool
    private let audioCoordinator: AudioPlaybackCoordinator = resolve()

    // Viewer overlay state
    @State private var viewerVM: MixViewModel?
    @State private var isViewerExpanded = false

    // Drag-to-minimize state
    @State private var viewerDragOffset: CGSize = .zero
    @State private var viewerDragScale: CGFloat = 1.0
    @State private var miniPlayerCorner: Corner = .bottomTrailing
    @State private var isExpandingFromMini = false
    @State private var isOpeningFromCreator = false
    @State private var miniDragOffset: CGSize = .zero

    // Hero expand animation state
    @State private var heroMix: Mix?
    @State private var heroSourceFrame: CGRect = .zero
    @State private var heroExpanded = false
    @State private var heroFinished = false


    // Creator parallax reveal: 0 = home visible, 1 = creator fully revealed
    @State private var showCreator = false
    @State private var creatorProgress: CGFloat = 0
    @State private var isCreatorDragging = false
    @State private var creatorDragAxis: DragAxis? = nil
    private enum DragAxis { case horizontal, vertical }
    // Card frame tracking for hero animations
    @State private var cardFrames: [UUID: CGRect] = [:]
    @State private var ignoreCardTaps = false

    // Mini player card dimensions
    private static let miniCardWidth: CGFloat = 136

    /// Mini card height derived from the current mix's crop values.
    private var currentMiniCardHeight: CGFloat {
        guard let vm = viewerVM else { return Self.miniCardWidth * (17.0 / 9.0) }
        let mix = vm.currentMix
        let sy = max(mix.previewCropScale ?? 1.0, 1.2)
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

    private var screenWidth: CGFloat { UIScreen.main.bounds.width }

    var body: some View {
        let homeOffset = -creatorProgress * screenWidth
        let creatorOffset = screenWidth * 0.5 * (1 - creatorProgress)

        ZStack {
            // Layer 0: Creator (behind home) — parallax at half speed
            if showCreator {
                CreatorView(
                    onDismiss: { dismissCreator() },
                    onDone: { mix, creatorMedia in
                        let vm = MixViewModel(editing: mix)
                        vm.modelContext = managedObjectContext
                        switch creatorMedia {
                        case .photo(let data, let thumbnail):
                            vm.editState.mediaData = data
                            vm.editState.mediaThumbnail = thumbnail
                            vm.editState.mediaIsVideo = false
                        case .video(let data, let thumbnail):
                            vm.editState.mediaData = data
                            vm.editState.mediaThumbnail = thumbnail
                            vm.editState.mediaIsVideo = true
                        case .voiceRecording(let data):
                            vm.editState.audioData = data
                        case .file(let data, let fileName):
                            vm.editState.fileData = data
                            vm.editState.fileName = fileName
                        case .importVideo(let data, let thumbnail, _, _):
                            vm.editState.mediaData = data
                            vm.editState.mediaThumbnail = thumbnail
                            vm.editState.mediaIsVideo = mix.mediaIsVideo
                        case nil:
                            break
                        }
                        vm.editState.widgets = mix.widgets
                        isOpeningFromCreator = true
                        viewerVM = vm
                        isViewerExpanded = true
                        dismissCreator()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            isOpeningFromCreator = false
                        }
                    }
                )
                .offset(x: creatorOffset)
                .simultaneousGesture(creatorDismissGesture)
                .ignoresSafeArea()
                .zIndex(1)
            }

            // Layer 1: Home content — slides right at full speed
            NavigationStack(path: $viewModel.navigationPath) {
                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { viewMenu }
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
                        viewModel.saveCurrentAsView(name: name, context: managedObjectContext)
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
                        viewModel.renameActiveView(name: name, context: managedObjectContext)
                    }
                }
                .onChange(of: viewModel.navigationPath) { _, path in
                    if path.isEmpty {
                        viewModel.reloadFromLocal(context: managedObjectContext)
                    }
                }
                .task {
                    await viewModel.loadMixes(context: managedObjectContext)
                    viewModel.loadTags(context: managedObjectContext)
                    viewModel.loadSavedViews(context: managedObjectContext)
                }
                .onReceive(NotificationCenter.default.publisher(for: MixCreationService.didFinishCreation)) { _ in
                    viewModel.reloadFromLocal(context: managedObjectContext)
                }
                .onChange(of: viewerVM?.tagsForCurrentMix) { _, _ in
                    if let vm = viewerVM {
                        viewModel.syncFromViewer(vm.mixes, context: managedObjectContext)
                    }
                }
            }
            .offset(x: homeOffset)
            .simultaneousGesture(creatorOpenGesture)
            .allowsHitTesting(creatorProgress == 0)
            .zIndex(2)

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
                    cropX: heroMix.previewCropX ?? 0.5,
                    cropY: heroMix.previewCropY ?? 0.5,
                    cropScale: heroMix.previewCropScale ?? 1.0
                )
                .transition(.identity)
                .ignoresSafeArea()
                .zIndex(15)
            }

            // Viewer — position-based placement, drag scales from left edge
            if let vm = viewerVM {
                let screen = UIScreen.main.bounds
                let canvasW = screen.width
                let canvasH = screen.height
                let safeTop = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first?.windows.first?.safeAreaInsets.top ?? 0

                MixView(
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
                .clipShape(.rect(cornerRadius: isViewerExpanded ? 0 : 16))
                .scaleEffect(isViewerExpanded ? viewerDragScale : Self.miniTargetScale)
                .offset(isViewerExpanded ? viewerDragOffset : miniDragOffset)
                .position(
                    x: isViewerExpanded ? canvasW / 2 : miniTargetPosition.x,
                    y: isViewerExpanded ? canvasH / 2 : miniTargetPosition.y
                )
                .overlay(alignment: .topLeading) {
                    if isViewerExpanded && vm.mode == .view {
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
                    insertion: (isExpandingFromMini || heroMix != nil || isOpeningFromCreator) ? .identity : .move(edge: .trailing),
                    removal: .identity
                ))
                .animation(.spring(duration: 0.35), value: isViewerExpanded)
                .animation(.spring(duration: 0.35), value: vm.currentMix.id)
                .zIndex(10)

                // Mini drag target — inset from top/bottom to leave buttons exposed (view mode only)
                if !isViewerExpanded && vm.mode == .view {
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
        let vm = MixViewModel(mixes: mixes, startIndex: startIndex)
        vm.modelContext = managedObjectContext
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
        let vm = MixViewModel(mixes: mixes, startIndex: startIndex)
        vm.modelContext = managedObjectContext
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

    private var creatorOpenGesture: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                // Lock axis on first significant movement
                if creatorDragAxis == nil {
                    let absX = abs(value.translation.width)
                    let absY = abs(value.translation.height)
                    if absX > 10 || absY > 10 {
                        creatorDragAxis = absX > absY ? .horizontal : .vertical
                    }
                }
                guard creatorDragAxis == .horizontal else { return }
                let dx = max(0, -value.translation.width)
                if !showCreator { showCreator = true }
                isCreatorDragging = true
                creatorProgress = min(1, dx / screenWidth)
            }
            .onEnded { value in
                defer { creatorDragAxis = nil }
                guard isCreatorDragging else { return }
                isCreatorDragging = false
                let dx = max(0, -value.translation.width)
                if dx > screenWidth * 0.3 || -value.predictedEndTranslation.width > screenWidth * 0.5 {
                    withAnimation(.spring(duration: 0.35)) {
                        creatorProgress = 1
                    }
                } else {
                    dismissCreator()
                }
            }
    }

    private var creatorDismissGesture: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                // Lock axis on first significant movement
                if creatorDragAxis == nil {
                    let absX = abs(value.translation.width)
                    let absY = abs(value.translation.height)
                    if absX > 10 || absY > 10 {
                        creatorDragAxis = absX > absY ? .horizontal : .vertical
                    }
                }
                guard creatorDragAxis == .horizontal else { return }
                let dx = max(0, value.translation.width)
                isCreatorDragging = true
                creatorProgress = max(0, 1 - dx / screenWidth)
            }
            .onEnded { value in
                defer { creatorDragAxis = nil }
                guard isCreatorDragging else { return }
                isCreatorDragging = false
                let dx = max(0, value.translation.width)
                if dx > screenWidth * 0.3 || value.predictedEndTranslation.width > screenWidth * 0.5 {
                    dismissCreator()
                } else {
                    withAnimation(.spring(duration: 0.3)) {
                        creatorProgress = 1
                    }
                }
            }
    }

    private func openCreator() {
        showCreator = true
        withAnimation(.spring(duration: 0.45)) {
            creatorProgress = 1
        }
    }

    private func dismissCreator() {
        withAnimation(.spring(duration: 0.35)) {
            creatorProgress = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            showCreator = false
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
                    MasonryMixCard(mix: mix) {
                        guard !ignoreCardTaps else { return }
                        let mixes = viewModel.displayedMixes
                        guard let index = mixes.firstIndex(where: { $0.id == mix.id }) else { return }
                        if mix.screenshotUrl != nil {
                            openViewerWithHero(mix: mix, frame: cardFrames[mix.id] ?? .zero, mixes: mixes, startIndex: index)
                        } else {
                            openViewer(mixes: mixes, startIndex: index)
                        }
                    }
                        .background {
                            GeometryReader { geo in
                                Color.clear.onChange(of: geo.frame(in: .named("home-root"))) { _, frame in
                                    cardFrames[mix.id] = frame
                                }.onAppear {
                                    cardFrames[mix.id] = geo.frame(in: .named("home-root"))
                                }
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                viewModel.deleteMix(mix, context: managedObjectContext)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(.horizontal, 8)
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
                        MasonryMixCard(mix: mix) {
                            guard !ignoreCardTaps else { return }
                            if let fullIndex = viewModel.mixes.firstIndex(where: { $0.id == mix.id }) {
                                if mix.screenshotUrl != nil {
                                    openViewerWithHero(mix: mix, frame: cardFrames[mix.id] ?? .zero, mixes: viewModel.mixes, startIndex: fullIndex)
                                } else {
                                    openViewer(mixes: viewModel.mixes, startIndex: fullIndex)
                                }
                            }
                        }
                            .background {
                                GeometryReader { geo in
                                    Color.clear.onChange(of: geo.frame(in: .named("home-root"))) { _, frame in
                                        cardFrames[mix.id] = frame
                                    }.onAppear {
                                        cardFrames[mix.id] = geo.frame(in: .named("home-root"))
                                    }
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    viewModel.deleteMix(mix, context: managedObjectContext)
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
            Text("Loading...")
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
                    viewModel.updateActiveView(context: managedObjectContext)
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
                        viewModel.deleteView(view, context: managedObjectContext)
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
                        viewModel.search(query: newValue, context: managedObjectContext)
                    }
                    .onSubmit {
                        viewModel.search(query: searchText, context: managedObjectContext)
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

                Button { openCreator() } label: {
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
