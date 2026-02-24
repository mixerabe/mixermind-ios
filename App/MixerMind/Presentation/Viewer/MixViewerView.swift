import SwiftUI
import AVFoundation

struct MixViewerView: View {
    @State private var viewModel: MixViewerViewModel
    @Environment(\.dismiss) private var dismiss

    var onDeleted: ((UUID) -> Void)?

    init(mixes: [Mix], startIndex: Int, onDeleted: ((UUID) -> Void)? = nil) {
        _viewModel = State(initialValue: MixViewerViewModel(mixes: mixes, startIndex: startIndex))
        self.onDeleted = onDeleted
    }

    @State private var showDeleteAlert = false

    // Title editing
    @State private var titleDraft = ""
    @State private var isEditingTitle = false
    @State private var wasPausedBeforeTitleEdit = false

    // Tag editing
    @State private var showNewTagSheet = false

    var body: some View {
        VStack(spacing: 0) {
            pagingCanvas
            viewerBottomBar
        }
        .ignoresSafeArea(.keyboard)
        .background(Color(red: 0.08, green: 0.08, blue: 0.08))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .tint(.white)
        .toolbar {
            viewerToolbarItems
        }
        .fullScreenCover(isPresented: $isEditingTitle) {
            TitleEditOverlayView(
                title: $titleDraft,
                onCommit: commitTitle
            )
            .interactiveDismissDisabled()
        }
        .onAppear {
            viewModel.onAppear()
            viewModel.loadAllTags()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .onChange(of: viewModel.scrolledID) { _, _ in
            viewModel.onScrollChanged()
        }
        .alert("Delete this mix?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    let mixId = viewModel.currentMix.id
                    let success = await viewModel.deleteCurrentMix()
                    if success {
                        onDeleted?(mixId)
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Paging Canvas

    private var pagingCanvas: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.mixes.enumerated()), id: \.element.id) { index, mix in
                    canvasForMix(mix)
                        .containerRelativeFrame([.horizontal, .vertical])
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $viewModel.scrolledID, anchor: .top)
        .scrollDisabled(isEditingTitle)
        .ignoresSafeArea(edges: .top)
        .ignoresSafeArea(.keyboard)
        .onScrollPhaseChange { _, newPhase in
            if newPhase == .idle {
                viewModel.onScrollIdle()
            }
        }
    }

    // MARK: - Viewer Bottom Bar

    private var viewerBottomBar: some View {
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
                    }
                    .buttonStyle(.plain)
                    .glassEffect(in: .capsule)
                }

                // New tag button
                Button {
                    showNewTagSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
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
        .padding(.vertical, 8)
    }

    // MARK: - Viewer Toolbar

    @ToolbarContentBuilder
    private var viewerToolbarItems: some ToolbarContent {
        if !viewModel.mixes.isEmpty {
            ToolbarItem(placement: .principal) {
                titleBar
            }
            ToolbarItem(placement: .primaryAction) {
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
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Canvas per Mix

    private func canvasForMix(_ mix: Mix) -> some View {
        let isCurrent = mix.id == viewModel.currentMix.id

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
            appleMusicTitle: mix.appleMusicTitle,
            appleMusicArtist: mix.appleMusicArtist,
            appleMusicArtworkUrl: mix.appleMusicArtworkUrl,
            embedUrl: mix.embedUrl,
            embedOg: mix.embedOg,
            onEmbedTap: {
                if let embedUrl = mix.embedUrl, let url = URL(string: embedUrl) {
                    UIApplication.shared.open(url)
                }
            },
            isPaused: Binding(get: { viewModel.isPaused }, set: { viewModel.isPaused = $0 }),
            isMuted: Binding(get: { viewModel.isMuted }, set: { viewModel.isMuted = $0 }),
            isScrubbing: Binding(get: { viewModel.isScrubbing }, set: { viewModel.isScrubbing = $0 }),
            playbackProgress: Binding(get: { viewModel.playbackProgress }, set: { viewModel.playbackProgress = $0 }),
            hasPlayback: isCurrent ? viewModel.hasPlayback : false,
            playbackDuration: isCurrent ? viewModel.currentDuration : 0,
            onTogglePause: { viewModel.togglePause() },
            onToggleMute: { viewModel.toggleMute() },
            onBeginScrub: { viewModel.beginScrub() },
            onScrub: { viewModel.scrub(to: $0) },
            onEndScrub: { viewModel.endScrub() },
            onCanvasTap: {
                if viewModel.hasPlayback, !viewModel.isPaused {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.togglePause()
                    }
                }
            },
            onPlaceholderTap: nil
        )
    }

    // MARK: - Title Bar (toolbar chip only — never contains a text field)

    private var titleBar: some View {
        Button {
            beginTitleEdit()
        } label: {
            Text(viewModel.currentMix.title ?? "Add title")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(viewModel.currentMix.title != nil ? .white : .white.opacity(0.4))
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .frame(height: 44)
        .glassEffect(in: .capsule)
        .onChange(of: viewModel.scrolledID) { _, _ in
            cancelTitleEdit()
        }
    }

    private func beginTitleEdit() {
        titleDraft = viewModel.currentMix.title ?? ""
        wasPausedBeforeTitleEdit = viewModel.isPaused
        if !viewModel.isPaused { viewModel.togglePause() }
        isEditingTitle = true
    }

    private func commitTitle() {
        let text = titleDraft
        isEditingTitle = false
        if !wasPausedBeforeTitleEdit, viewModel.isPaused { viewModel.togglePause() }
        Task { await viewModel.saveTitle(text) }
    }

    private func cancelTitleEdit() {
        isEditingTitle = false
        if !wasPausedBeforeTitleEdit, viewModel.isPaused { viewModel.togglePause() }
    }
}

private struct TitleEditOverlayView: View {
    @Binding var title: String
    let onCommit: () -> Void

    @FocusState private var titleFieldFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    onCommit()
                }

            TextField("Title", text: $title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .focused($titleFieldFocused)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .onSubmit {
                    onCommit()
                }
                .onChange(of: title) { _, newValue in
                    if newValue.count > 50 {
                        title = String(newValue.prefix(50))
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .glassEffect(in: .capsule)
                .padding(.horizontal, 40)
                .padding(.top, 52)
        }
        .ignoresSafeArea(.keyboard)
        .onAppear {
            titleFieldFocused = true
        }
    }
}
