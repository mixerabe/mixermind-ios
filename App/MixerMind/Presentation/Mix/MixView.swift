import SwiftUI
import CoreData
import AVFoundation

struct MixView: View {
    @Bindable var viewModel: MixViewModel
    var onMinimize: () -> Void
    var onDismiss: () -> Void
    var onDeleted: ((UUID) -> Void)?
    var dragProgress: CGFloat = 0 // 0 = fullscreen, 1 = fully minimized
    var isMinimized: Bool = false
    var safeAreaTop: CGFloat = 0
    var miniVisibleHeight: CGFloat = 0

    @Environment(\.managedObjectContext) private var managedObjectContext

    private let coordinator: AudioPlaybackCoordinator = resolve()

    @State private var showDeleteAlert = false
    @State private var showBottomSheet = true
    @State private var sheetDetent: PresentationDetent = .height(MixBottomSheetParams.smallDetentHeight)



    private var chromeOpacity: Double {
        max(1 - dragProgress * 3, 0) // Fades out quickly in first third of drag
    }

    private var safeAreaBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 0
    }

    /// Canvas dimensions: 9:21 aspect ratio, width = screen width
    private var canvasSize: CGSize {
        let w = UIScreen.main.bounds.width
        return CGSize(width: w, height: w / ScreenshotService.canvasAspect)
    }

    var body: some View {
        ZStack {
            // Full-bleed background matching current mix
            Group {
                if viewModel.currentMix.type == .media || viewModel.currentMix.type == .import {
                    Color.black
                } else {
                    LinearGradient(
                        colors: [
                            Color(hex: viewModel.currentMix.gradientTop ?? "#1a1a2e"),
                            Color(hex: viewModel.currentMix.gradientBottom ?? "#16213e")
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .ignoresSafeArea()

            pagingCanvas
                .frame(width: canvasSize.width, height: canvasSize.height)
                .allowsHitTesting(!isMinimized)

            // Mini controls — big buttons that scale down naturally with the viewer (view mode only)
            if viewModel.mode == .view {
                miniControls
                    .opacity(isMinimized ? 1 : 0)
                    .allowsHitTesting(isMinimized)
            }

            // Audio chip — bottom left (edit & view)
            if showAudioChip {
                VStack {
                    Spacer()
                    HStack {
                        audioChipView
                            .padding(.leading, 24)
                            .padding(.bottom, 80)
                        Spacer()
                    }
                }
                .frame(width: canvasSize.width, height: UIScreen.main.bounds.height)
                .opacity(chromeOpacity)
                .allowsHitTesting(!isMinimized)
            }

            // Source link bar for .import type
            if viewModel.currentMix.type == .import,
               let sourceUrl = viewModel.currentMix.sourceUrl,
               let url = URL(string: sourceUrl),
               !isMinimized {
                VStack {
                    Spacer()
                    sourceLinkBar(url: url)
                        .padding(.horizontal, 16)
                        .padding(.bottom, safeAreaBottom + 72)
                }
                .frame(width: canvasSize.width, height: UIScreen.main.bounds.height)
                .opacity(chromeOpacity)
                .allowsHitTesting(!isMinimized)
            }

        }
        .sheet(isPresented: $showBottomSheet) {
            MixBottomSheet(
                viewModel: viewModel,
                sheetDetent: $sheetDetent,
                onDismiss: onDismiss,
                onDelete: { showDeleteAlert = true }
            )
            .presentationDetents(MixBottomSheetParams.allDetents, selection: $sheetDetent)
            .presentationDragIndicator(.visible)
            .presentationCompactAdaptation(.none)
            .interactiveDismissDisabled()
            .presentationBackgroundInteraction(.enabled)
        }
        .onAppear {
            viewModel.modelContext = managedObjectContext
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
        .scrollDisabled(isMinimized || viewModel.mode == .edit)
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


    // MARK: - Audio Chip

    private var showAudioChip: Bool {
        if viewModel.mode == .edit { return viewModel.editChipLabel != "Add audio" }
        return viewModel.viewerChipLabel != nil
    }

    @ViewBuilder
    private var audioChipView: some View {
        if viewModel.mode == .edit {
            editAudioChip
        } else {
            viewerAudioChip
        }
    }

    private var editAudioChip: some View {
        Group {
            if viewModel.chipHasGenerateAction {
                // Tappable: generates TTS or AI Summary
                Button {
                    if viewModel.currentMix.type == .note {
                        viewModel.generateTTS()
                    } else {
                        viewModel.generateAISummary()
                    }
                } label: {
                    audioChipLabel
                }
                .buttonStyle(.plain)
                .disabled(viewModel.chipIsLoading)
            } else if viewModel.canRemoveAudio {
                // Menu: shows "Remove audio"
                Menu {
                    Button(role: .destructive) {
                        viewModel.removeAudio()
                    } label: {
                        Label("Remove audio", systemImage: "speaker.slash")
                    }
                } label: {
                    audioChipLabel
                }
                .buttonStyle(.plain)
            } else {
                // Informational only (e.g. "Original audio", "No audio" for video)
                audioChipLabel
            }
        }
    }

    private var viewerAudioChip: some View {
        HStack(spacing: 6) {
            if let icon = viewModel.viewerChipIcon {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
            }
            if let label = viewModel.viewerChipLabel {
                Text(label)
                    .font(.caption.weight(.medium))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .glassEffect(in: .capsule)
    }

    private var audioChipLabel: some View {
        HStack(spacing: 6) {
            if viewModel.chipIsLoading {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.8)
            } else {
                Image(systemName: viewModel.editChipIcon)
                    .font(.caption.weight(.semibold))
            }
            Text(viewModel.editChipLabel)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .contentShape(.capsule)
        .glassEffect(in: .capsule)
    }



    // MARK: - Canvas per Mix

    private func canvasForMix(_ mix: Mix) -> some View {
        let isCurrent = mix.id == viewModel.currentMix.id
        let hasVideo = viewModel.videoPlayer != nil

        let mediaUrl: String? = {
            switch mix.type {
            case .media, .`import`: return mix.mediaUrl
            default: return nil
            }
        }()

        let thumbnailUrl: String? = {
            switch mix.type {
            case .media, .`import`: return mix.mediaThumbnailUrl ?? mix.mediaUrl
            default: return nil
            }
        }()

        let editThumbnail: UIImage? = (viewModel.mode == .edit && isCurrent) ? viewModel.editState.mediaThumbnail : nil

        // Compute fixed note container width from stored bucket (or legacy fallback)
        let noteContainerWidth: CGFloat? = {
            guard mix.type == .note else { return nil }
            let screenWidth = UIScreen.main.bounds.width
            if let bucket = mix.textBucket {
                return min(bucket.containerWidth, screenWidth - 48)
            }
            // Legacy mixes (no bucket stored) — use 342pt (matches old 390pt screenshots)
            return min(342, screenWidth - 48)
        }()

        return MixCanvasView(
            mixType: mix.type,
            textContent: mix.textContent ?? "",
            mediaThumbnail: editThumbnail,
            mediaUrl: mediaUrl,
            thumbnailUrl: thumbnailUrl,
            videoPlayer: isCurrent ? viewModel.videoPlayer : nil,
            widgets: mix.widgets,
            gradientTop: mix.gradientTop,
            gradientBottom: mix.gradientBottom,
            noteContainerWidth: noteContainerWidth,
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
            isEditing: viewModel.mode == .edit,
            isMinimized: isMinimized,
            dragProgress: dragProgress
        )
    }

    private func sourceLinkBar(url: URL) -> some View {
        Button {
            UIApplication.shared.open(url)
        } label: {
            HStack(spacing: 8) {
                let host = url.host ?? ""
                let isInstagram = host.contains("instagram")
                Image(systemName: isInstagram ? "camera.circle.fill" : "play.rectangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(isInstagram ? .pink : .red)
                Text(host)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .glassEffect(in: .capsule)
        }
        .buttonStyle(.plain)
    }

}

// MARK: - Bottom Sheet Params

private struct MixBottomSheetParams {
    static let smallDetentHeight: CGFloat = 65
    static let allDetents: Set<PresentationDetent> = [.height(smallDetentHeight), .large]
}

// MARK: - Expandable Bottom Sheet

private struct MixBottomSheet: View {
    @Bindable var viewModel: MixViewModel
    @Binding var sheetDetent: PresentationDetent
    var onDismiss: () -> Void
    var onDelete: () -> Void

    @State private var showNewTagSheet = false
    @State private var isTitleFocused = false

    private var isExpanded: Bool {
        sheetDetent == .large
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Collapsed
            if !isExpanded {
                collapsedContent
                    .padding(.horizontal, 12.5)
                    .transition(.opacity)
            }

            // Expanded
            if isExpanded {
                VStack(spacing: 0) {
                    expandedTitleRow
                    ScrollView {
                        VStack(spacing: 16) {
                            tagGrid
                        }
                        .padding(.horizontal, 16)
                    }
                    .scrollIndicators(.hidden)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .sheet(isPresented: $showNewTagSheet) {
            NewTagSheet { name in
                viewModel.createAndAddTag(name: name)
            }
            .presentationDetents([.height(140)])
            .presentationDragIndicator(.hidden)
        }
        .onChange(of: sheetDetent) { _, newDetent in
            if newDetent == .height(MixBottomSheetParams.smallDetentHeight) {
                isTitleFocused = false
                viewModel.commitTitle()
            } else if newDetent == .large {
                viewModel.beginTitleEdit()
            }
        }
    }

    // MARK: - Collapsed Content (small detent)

    private var collapsedContent: some View {
        HStack {
            // Left button
            Button { onDismiss() } label: {
                Image(systemName: viewModel.mode == .edit ? "arrow.left" : "xmark")
                    .foregroundStyle(.white)
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive())

            Spacer()

            // Center — title + tag preview
            VStack(spacing: 1) {
                Text(viewModel.currentMix.title ?? "Untitled Mix")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(viewModel.currentMix.title != nil ? .white : .white.opacity(0.5))
                    .lineLimit(1)

                tagPreviewLine
            }
            .frame(height: 40)

            Spacer()

            // Right button
            if viewModel.mode == .edit {
                Button {
                    if viewModel.saveMix() { onDismiss() }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(Color.accentColor).interactive())
            } else {
                viewModeMenu
            }
        }
    }

    // MARK: - Tag Preview Line

    private var tagPreviewLine: some View {
        let activeTags = viewModel.tagsForCurrentMix
        let maxVisible = 3

        return Group {
            if activeTags.isEmpty {
                Text(viewModel.mode == .edit ? "Add tags" : "Add tags")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.35))
            } else {
                let visible = activeTags.prefix(maxVisible)
                let overflow = activeTags.count - maxVisible
                HStack(spacing: 4) {
                    Text(visible.map { "#\($0.name)" }.joined(separator: ", "))
                        .lineLimit(1)
                    if overflow > 0 {
                        Text("+\(overflow)")
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    // MARK: - Expanded Title Row (large detent)

    private var expandedTitleRow: some View {
        VStack(spacing: 12) {
            // Header buttons
            HStack {
                Button { onDismiss() } label: {
                    Image(systemName: viewModel.mode == .edit ? "arrow.left" : "xmark")
                        .foregroundStyle(.white)
                        .font(.body.weight(.semibold))
                        .frame(width: 40, height: 40)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive())

                Spacer()

                if viewModel.mode == .edit {
                    Button {
                        if viewModel.saveMix() { onDismiss() }
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(Color.accentColor).interactive())
                } else {
                    viewModeMenu
                }
            }
            .padding(.horizontal, 12)

            // Editable title in glass field
            HStack {
                TextField("Untitled Mix", text: $viewModel.titleDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .submitLabel(.done)
                    .onSubmit {
                        viewModel.commitTitle()
                        sheetDetent = .height(MixBottomSheetParams.smallDetentHeight)
                    }
                    .onChange(of: viewModel.titleDraft) { _, newValue in
                        if newValue.count > 50 {
                            viewModel.titleDraft = String(newValue.prefix(50))
                        }
                    }
            }
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .glassEffect(.regular.interactive())
            .padding(.horizontal, 16)
        }
        .padding(.top, 16)
    }

    // MARK: - Tag Grid

    private var tagGrid: some View {
        FlowLayout(spacing: 8) {
            ForEach(viewModel.sortedTags) { tag in
                let isOn = viewModel.tagsForCurrentMix.contains { $0.id == tag.id }
                Button {
                    viewModel.toggleTag(tag)
                } label: {
                    Text("#\(tag.name)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isOn ? .black : .white)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
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
                    .frame(width: 40, height: 40)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .glassEffect(in: .capsule)
        }
    }

    // MARK: - View Mode Menu

    private var viewModeMenu: some View {
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
                onDelete()
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(.white)
                .font(.body.weight(.semibold))
                .frame(width: 40, height: 40)
                .contentShape(.circle)
        }
        .glassEffect(.regular.interactive())
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}
