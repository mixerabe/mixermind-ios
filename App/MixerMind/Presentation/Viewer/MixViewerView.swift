import SwiftUI
import SwiftData
import AVFoundation

struct MixViewerView: View {
    @Bindable var viewModel: MixViewerViewModel
    var onMinimize: () -> Void
    var onDismiss: () -> Void
    var onDeleted: ((UUID) -> Void)?
    var dragProgress: CGFloat = 0 // 0 = fullscreen, 1 = fully minimized
    var isMinimized: Bool = false
    var safeAreaTop: CGFloat = 0
    var miniVisibleHeight: CGFloat = 0

    @Environment(\.modelContext) private var modelContext

    private let coordinator: AudioPlaybackCoordinator = resolve()

    @State private var showDeleteAlert = false

    // Title editing
    @State private var titleDraft = ""
    @State private var isEditingTitle = false



    private var chromeOpacity: Double {
        max(1 - dragProgress * 3, 0) // Fades out quickly in first third of drag
    }

    /// Canvas dimensions: full width, 16:9 aspect
    private var canvasSize: CGSize {
        let w = UIScreen.main.bounds.width
        let h = w * (17.0 / 9.0)
        return CGSize(width: w, height: h)
    }

    var body: some View {
        ZStack {
            pagingCanvas
                .frame(width: canvasSize.width, height: canvasSize.height)
                .background(Color.clear)
                .allowsHitTesting(!isMinimized)

            // Top chrome — positioned below safe area
            topChrome
                .position(x: canvasSize.width / 2, y: safeAreaTop + 36)
                .opacity(chromeOpacity)
                .allowsHitTesting(!isMinimized)

            // Mini controls — big buttons that scale down naturally with the viewer
            miniControls
                .opacity(isMinimized ? 1 : 0)
                .allowsHitTesting(isMinimized)
        }
        .sheet(isPresented: $isEditingTitle) {
            TitleEditSheet(
                title: $titleDraft,
                onDone: commitTitle,
                onCancel: cancelTitleEdit
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled()
        }
        .onAppear {
            viewModel.modelContext = modelContext
            if !viewModel.hasAppeared {
                viewModel.onAppear()
                viewModel.loadAllTags()
            } else {
                viewModel.loadCurrentMix()
            }
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .onChange(of: viewModel.scrolledID) { _, _ in
            viewModel.onScrollChanged()
        }
        .onChange(of: coordinator.currentTrackIndex) { _, _ in
            viewModel.syncFromCoordinator()
        }
        .onChange(of: viewModel.isAutoScroll) { _, newValue in
            coordinator.isLooping = !newValue
        }
        .alert("Delete this mix?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    let mixId = viewModel.currentMix.id
                    let hasMore = await viewModel.deleteCurrentMix()
                    onDeleted?(mixId)
                    if !hasMore {
                        onDismiss()
                    }
                }
            }
        }
    }

    // MARK: - Paging Canvas

    private var pagingCanvas: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.mixes) { mix in
                    canvasForMix(mix)
                        .frame(width: canvasSize.width, height: canvasSize.height)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollDisabled(isMinimized)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $viewModel.scrolledID, anchor: .top)
        .ignoresSafeArea(.keyboard)
        .onScrollPhaseChange { _, newPhase in
            if newPhase == .idle {
                viewModel.onScrollIdle()
            }
        }
    }


    // MARK: - Mini Controls (inside viewer, scale down naturally)

    /// The height in canvas coordinates that will be visible after clip.
    private var miniVisibleCanvasHeight: CGFloat {
        guard miniVisibleHeight > 0 else { return canvasSize.height }
        let scale = Self.miniTargetScale
        guard scale > 0 else { return canvasSize.height }
        return miniVisibleHeight / scale
    }

    private static var miniTargetScale: CGFloat {
        let screen = UIScreen.main.bounds
        guard screen.width > 0 else { return 0.3 }
        return 136.0 / screen.width
    }

    private var miniControls: some View {
        ZStack {
            // Dismiss — top trailing
            VStack {
                HStack {
                    Spacer()
                    Button { onDismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 70, height: 70)
                            .background(.ultraThinMaterial, in: .circle)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                Spacer()
            }

            // Playback controls — at the bottom of the visible clip area
            VStack {
                Spacer()
                HStack(spacing: 48) {
                    Button { coordinator.previous() } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 22))
                            .frame(width: 70, height: 70)
                            .contentShape(Rectangle())
                    }

                    Button { coordinator.togglePlayPause() } label: {
                        Image(systemName: coordinator.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 28))
                            .frame(width: 80, height: 80)
                            .contentShape(Rectangle())
                    }

                    Button { coordinator.next() } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 22))
                            .frame(width: 70, height: 70)
                            .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.bottom, miniVisibleCanvasHeight * 0.05)
            }
        }
        .frame(width: canvasSize.width, height: miniVisibleCanvasHeight)
        .contentShape(.rect)
    }

    // MARK: - Top Chrome (replaces toolbar)

    private var topChrome: some View {
        HStack {
            // Left: menu
            if !viewModel.mixes.isEmpty {
                Menu {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.isAutoScroll.toggle()
                        }
                    } label: {
                        Label(
                            viewModel.isAutoScroll ? "Stop Auto-scroll" : "Auto-scroll",
                            systemImage: viewModel.isAutoScroll ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle"
                        )
                    }
                    Button("Delete", role: .destructive) {
                        showDeleteAlert = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glassEffect(in: .circle)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }

            Spacer()

            // Center: title chip
            if !viewModel.mixes.isEmpty {
                titleBar
            }

            Spacer()

            // Right: close button
            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .glassEffect(in: .circle)
        }
        .padding(.horizontal, 16)
        .frame(width: canvasSize.width)
    }


    // MARK: - Canvas per Mix

    private func canvasForMix(_ mix: Mix) -> some View {
        let isCurrent = mix.id == viewModel.currentMix.id
        let hasVideo = viewModel.videoPlayer != nil

        let mediaUrl: String? = {
            switch mix.type {
            case .photo: return mix.photoUrl
            case .video: return mix.videoUrl
            case .import: return mix.importMediaUrl
            default: return nil
            }
        }()

        let thumbnailUrl: String? = {
            switch mix.type {
            case .photo: return mix.photoThumbnailUrl ?? mix.photoUrl
            case .video: return mix.videoThumbnailUrl
            case .import: return mix.importThumbnailUrl
            default: return nil
            }
        }()

        return MixCanvasView(
            mixType: mix.type,
            textContent: mix.textContent ?? "",
            mediaThumbnail: nil,
            mediaUrl: mediaUrl,
            thumbnailUrl: thumbnailUrl,
            videoPlayer: isCurrent ? viewModel.videoPlayer : nil,
            embedUrl: mix.embedUrl,
            embedOg: mix.embedOg,
            gradientTop: mix.gradientTop,
            gradientBottom: mix.gradientBottom,
            onEmbedTap: {
                if let embedUrl = mix.embedUrl, let url = URL(string: embedUrl) {
                    UIApplication.shared.open(url)
                }
            },
            isPaused: Binding(
                get: { isCurrent ? !coordinator.isPlaying : true },
                set: { _ in }
            ),
            isMuted: Binding(
                get: { isCurrent ? coordinator.isMuted : false },
                set: { _ in }
            ),
            isScrubbing: Binding(
                get: { viewModel.isScrubbing },
                set: { viewModel.isScrubbing = $0 }
            ),
            playbackProgress: Binding(
                get: {
                    guard isCurrent else { return 0 }
                    if hasVideo { return viewModel.videoProgress }
                    return coordinator.progress
                },
                set: { viewModel.scrub(to: $0) }
            ),
            hasPlayback: isCurrent ? viewModel.hasPlayback : false,
            playbackDuration: isCurrent ? (hasVideo
                ? (viewModel.videoPlayer?.currentItem?.duration.seconds ?? 0)
                : coordinator.duration) : 0,
            onTogglePause: { viewModel.togglePause() },
            onToggleMute: { viewModel.toggleMute() },
            onBeginScrub: { viewModel.beginScrub() },
            onScrub: { viewModel.scrub(to: $0) },
            onEndScrub: { viewModel.endScrub() },
            onCanvasTap: {
                if viewModel.hasPlayback, coordinator.isPlaying {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.togglePause()
                    }
                }
            },
            onPlaceholderTap: nil,
            isMinimized: isMinimized,
            dragProgress: dragProgress
        )
    }

    // MARK: - Title Bar (toolbar chip only -- never contains a text field)

    private var titleBar: some View {
        Button {
            beginTitleEdit()
        } label: {
            Text(viewModel.currentMix.title ?? "Add title")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(viewModel.currentMix.title != nil ? .white : .white.opacity(0.4))
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(in: .capsule)
    }

    private func beginTitleEdit() {
        titleDraft = viewModel.currentMix.title ?? ""
        isEditingTitle = true
    }

    private func commitTitle() {
        let text = titleDraft
        isEditingTitle = false
        Task { await viewModel.saveTitle(text) }
    }

    private func cancelTitleEdit() {
        isEditingTitle = false
    }
}

private struct TitleEditSheet: View {
    @Binding var title: String
    var onDone: () -> Void
    var onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                TextField("Add title", text: $title)
                    .focused($isFocused)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.medium))
                    .multilineTextAlignment(.center)
                    .submitLabel(.done)
                    .onSubmit { onDone() }
                    .onChange(of: title) { _, newValue in
                        if newValue.count > 50 {
                            title = String(newValue.prefix(50))
                        }
                    }
                    .padding(.horizontal, 32)
                Spacer()
            }
            .navigationTitle("Title")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { onCancel() } label: {
                            Image(systemName: "xmark")
                                .fontWeight(.semibold)
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button { onDone() } label: {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                        }
                    }
                }
        }
        .onAppear {
            isFocused = true
        }
    }
}

struct ViewerTagBar: View {
    @Bindable var viewModel: MixViewerViewModel
    @State private var showNewTagSheet = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.sortedTags) { tag in
                    let isOn = viewModel.tagsForCurrentMix.contains { $0.id == tag.id }
                    Button {
                        viewModel.toggleTag(tag)
                    } label: {
                        Text("#\(tag.name)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(isOn ? .black : .white)
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .background(isOn ? Color.white : Color.clear, in: .capsule)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(in: .capsule)
                }

                Button {
                    showNewTagSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .glassEffect(in: .capsule)
                .sheet(isPresented: $showNewTagSheet) {
                    NewTagSheet { name in
                        viewModel.createAndAddTag(name: name)
                    }
                    .presentationDetents([.height(140)])
                    .presentationDragIndicator(.hidden)
                }
            }
            .padding(.horizontal)
        }
    }
}
