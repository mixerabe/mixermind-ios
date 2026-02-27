import SwiftUI
import AVFoundation
import PhotosUI

// MARK: - Creator Tab

enum CreatorTab: Int, CaseIterable, Identifiable {
    case text, gallery, `import`, embed, record

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .text: "Text"
        case .gallery: "Gallery"
        case .import: "Import"
        case .embed: "Embed"
        case .record: "Record"
        }
    }

    var icon: String {
        switch self {
        case .text: "textformat"
        case .gallery: "photo.on.rectangle"
        case .import: "play.rectangle"
        case .embed: "link.badge.plus"
        case .record: "mic"
        }
    }
}

// MARK: - Creator Media

enum CreatorMedia {
    case photo(data: Data, thumbnail: UIImage?)
    case video(data: Data, thumbnail: UIImage?)
    case audio(data: Data, fileName: String)
}

// MARK: - Creator View

struct CreatorView: View {
    var onDismiss: () -> Void
    var onDone: (Mix, CreatorMedia?) -> Void = { _, _ in }
    @State private var activeTab: CreatorTab = .text
    // Text tab state
    @State private var textContent: String = ""
    @State private var isTextEditorFocused: Bool = false

    // Embed tab state
    @State private var embedUrlText: String = ""
    @State private var isFetchingOG = false
    @State private var embedError: String?
    @FocusState private var isEmbedFieldFocused: Bool

    // Gallery tab state
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isLoadingGallery = false
    @State private var galleryError: String?
    @State private var showPhotoPicker = false

    // Import tab state
    @State private var importUrlText: String = ""
    @State private var isImporting = false
    @State private var importProgress: String?
    @State private var importError: String?
    @FocusState private var isImportFieldFocused: Bool

    // Record tab state
    @State private var recordVM = RecordAudioViewModel()

    private var canvasSize: CGSize {
        let w = UIScreen.main.bounds.width
        return CGSize(width: w, height: w * (17.0 / 9.0))
    }

    var body: some View {
        ScrollView {
            ZStack {
                // Top bar — X (leading) + Done (trailing, when text entered)
                VStack {
                    HStack {
                        Button { onDismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .contentShape(.circle)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(in: .circle)

                        Spacer()

                        if !textContent.isEmpty && activeTab == .text {
                            Button { handleDone() } label: {
                                Text("Done")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .frame(height: 44)
                                    .contentShape(.capsule)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(in: .capsule)
                        }
                    }
                    .padding(.horizontal, 16)
                    Spacer()
                }

                // Canvas content — below chrome
                canvasArea

                // Tab bar at bottom
                VStack {
                    Spacer()
                    tabBar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
            .containerRelativeFrame(.vertical)
        }
        .scrollDisabled(true)
        .background {
            LinearGradient(
                colors: [
                    Color(hex: "#1a1a2e"),
                    Color(hex: "#16213e")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .interactiveDismissDisabled()
        .onChange(of: activeTab) { oldTab, _ in
            if oldTab == .record {
                recordVM.stopPlayback()
                recordVM.cleanup()
                recordVM = RecordAudioViewModel()
            }
        }
    }

    // MARK: - Canvas

    private var canvasArea: some View {
        tabContent
            .padding(.top, 60)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .text:
            textTabContent
        case .gallery:
            galleryTabContent
        case .import:
            importTabContent
        case .embed:
            embedTabContent
        case .record:
            recordTabContent
        }
    }

    // MARK: - Text Tab

    private var textTabContent: some View {
        ZStack(alignment: .topLeading) {
            CenteredTextView(
                text: $textContent,
                isFocused: $isTextEditorFocused,
                fontSize: textDynamicFontSize
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if textContent.isEmpty && !isTextEditorFocused {
                Text("Type something...")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.white.opacity(0.25))
                    .padding(.leading, 24)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .onTapGesture { isTextEditorFocused = true }
    }

    private var textDynamicFontSize: CGFloat { 17 }

    // MARK: - Gallery Tab

    private var galleryTabContent: some View {
        ZStack {
            if isLoadingGallery {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                    Text("Loading...")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }
            } else if let error = galleryError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("Choose a photo or video")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Text("Open Library")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 160, height: 48)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(in: .capsule)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .any(of: [.images, .videos]))
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            loadGalleryItem(item)
        }
    }

    private func loadGalleryItem(_ item: PhotosPickerItem) {
        isLoadingGallery = true
        galleryError = nil

        Task {
            do {
                let isVideo = item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) })

                if isVideo {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        galleryError = "Could not load video"
                        isLoadingGallery = false
                        return
                    }
                    let thumbnail = await generateVideoThumbnail(from: data)
                    let mix = Mix(
                        id: UUID(),
                        type: .video,
                        createdAt: Date()
                    )
                    isLoadingGallery = false
                    onDone(mix, .video(data: data, thumbnail: thumbnail))
                } else {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        galleryError = "Could not load photo"
                        isLoadingGallery = false
                        return
                    }
                    let thumbnail = UIImage(data: data)
                    let mix = Mix(
                        id: UUID(),
                        type: .photo,
                        createdAt: Date()
                    )
                    isLoadingGallery = false
                    onDone(mix, .photo(data: data, thumbnail: thumbnail))
                }
            } catch {
                galleryError = error.localizedDescription
                isLoadingGallery = false
            }
        }
    }

    private func generateVideoThumbnail(from data: Data) async -> UIImage? {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")
        try? data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let asset = AVURLAsset(url: tempURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 800, height: 800)
        guard let cgImage = try? await generator.image(at: .zero).image else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Embed Tab

    private var embedTabContent: some View {
        VStack(spacing: 16) {
            TextField("apple.com", text: $embedUrlText)
                .focused($isEmbedFieldFocused)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding()
                .glassEffect(in: .rect(cornerRadius: 12))
                .onSubmit { embedLink() }

            if isFetchingOG {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("Fetching preview...")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            if let error = embedError {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.red.opacity(0.8))
            }

            Button { embedLink() } label: {
                Text("Embed")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.plain)
            .glassEffect(in: .capsule)
            .disabled(embedUrlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isFetchingOG)
            .opacity(embedUrlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isFetchingOG ? 0.4 : 1)

            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { isEmbedFieldFocused = true }
    }

    private func embedLink() {
        let trimmed = embedUrlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isFetchingOG else { return }

        var normalized = trimmed
        if !normalized.hasPrefix("http://") && !normalized.hasPrefix("https://") {
            normalized = "https://\(normalized)"
        }

        embedError = nil
        isFetchingOG = true
        isEmbedFieldFocused = false

        Task {
            var og: OGMetadata
            do {
                og = try await OpenGraphService.fetch(normalized)
            } catch {
                og = OGMetadata(
                    title: nil,
                    description: nil,
                    imageUrl: nil,
                    host: URL(string: normalized)?.host ?? normalized
                )
            }

            let mix = Mix(
                id: UUID(),
                type: .embed,
                createdAt: Date(),
                embedUrl: normalized,
                embedOg: og
            )

            isFetchingOG = false
            onDone(mix, nil)
        }
    }

    // MARK: - Import Tab

    private var importTabContent: some View {
        VStack(spacing: 16) {
            TextField("Paste a link (YouTube, Instagram, TikTok, Spotify)", text: $importUrlText)
                .focused($isImportFieldFocused)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding()
                .glassEffect(in: .rect(cornerRadius: 12))
                .onSubmit { importLink() }
            if let progress = importProgress {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(.white)
                    Text(progress).font(.subheadline).foregroundStyle(.white.opacity(0.5))
                }
            }
            if let error = importError {
                Text(error).font(.subheadline).foregroundStyle(.red.opacity(0.8))
            }
            Button { importLink() } label: {
                Text("Import")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.plain)
            .glassEffect(in: .capsule)
            .disabled(importUrlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)
            .opacity(importUrlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting ? 0.4 : 1)

            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { isImportFieldFocused = true }
    }

    private func importLink() {
        let trimmed = importUrlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isImporting else { return }
        var normalized = trimmed
        if !normalized.hasPrefix("http://") && !normalized.hasPrefix("https://") {
            normalized = "https://\(normalized)"
        }
        importError = nil
        isImporting = true
        isImportFieldFocused = false
        Task {
            do {
                let mixId = UUID()
                let localFiles = LocalFileManager.shared
                let mixDir = mixId.uuidString
                try FileManager.default.createDirectory(at: localFiles.fileURL(for: mixDir), withIntermediateDirectories: true)
                if MediaURLService.isSpotifyQuery(normalized) {
                    importProgress = "Downloading from Spotify..."
                    let result = try await MediaURLService.downloadSpotify(normalized)
                    let audioFileURL = localFiles.fileURL(for: "\(mixDir)/import_audio.mp3")
                    try result.audioData.write(to: audioFileURL)
                    let mix = Mix(id: mixId, type: .import, createdAt: Date(), importSourceUrl: normalized, importAudioUrl: audioFileURL.absoluteString)
                    isImporting = false
                    importProgress = nil
                    onDone(mix, nil)
                } else {
                    importProgress = "Fetching media info..."
                    let resolved = try await MediaURLService.resolve(normalized)
                    importProgress = "Downloading video..."
                    let videoData = try await MediaURLService.downloadMerged(resolved.originalURL)
                    let tempCheck = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
                    try videoData.write(to: tempCheck)
                    let asset = AVURLAsset(url: tempCheck)
                    let duration = try await asset.load(.duration).seconds
                    try? FileManager.default.removeItem(at: tempCheck)
                    if duration > 600 { throw MediaURLService.MediaError.serverError("Video is too long (max 10 minutes)") }
                    let thumbnail = await generateVideoThumbnail(from: videoData)
                    let videoFileURL = localFiles.fileURL(for: "\(mixDir)/import_video.mp4")
                    try videoData.write(to: videoFileURL)
                    let mix = Mix(id: mixId, type: .import, createdAt: Date(), importSourceUrl: normalized, importMediaUrl: videoFileURL.absoluteString)
                    isImporting = false
                    importProgress = nil
                    onDone(mix, .video(data: videoData, thumbnail: thumbnail))
                }
            } catch {
                isImporting = false
                importProgress = nil
                importError = error.localizedDescription
            }
        }
    }

    // MARK: - Record Tab

    private var recordTabContent: some View {
        VStack(spacing: 0) {
            Spacer()

            // Central visualizer — transitions between live and review
            ZStack {
                if recordVM.state == .stopped {
                    ReviewWaveformView(vm: recordVM)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    LiveRecordingVisual(vm: recordVM)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .animation(.spring(duration: 0.45), value: recordVM.state == .stopped)
            .frame(height: 280)

            Spacer().frame(height: 16)

            // Time display
            recordTimeDisplay
                .padding(.bottom, 8)

            Spacer().frame(maxHeight: 24)

            // Control bar
            recordControlBar
                .padding(.bottom, 80)
        }
        .animation(.spring(duration: 0.35), value: recordVM.state)
        .task { await recordVM.requestPermission() }
        .alert("Microphone Access Required", isPresented: $recordVM.permissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow microphone access in Settings to record audio.")
        }
    }

    // MARK: - Record Time Display

    private var recordTimeDisplay: some View {
        VStack(spacing: 6) {
            if recordVM.state == .stopped {
                HStack(spacing: 4) {
                    Text(recordVM.formattedPlaybackTime)
                        .font(.system(size: 42, weight: .thin, design: .monospaced))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.linear(duration: 0.05), value: recordVM.playbackTime)
                    Text("/")
                        .font(.system(size: 28, weight: .thin, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                    Text(recordVM.formattedDuration)
                        .font(.system(size: 28, weight: .thin, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .contentTransition(.numericText())
                }
            } else {
                Text(recordVM.formattedTime)
                    .font(.system(size: 56, weight: .thin, design: .monospaced))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.linear(duration: 0.1), value: recordVM.elapsedTime)
            }

            recordStateTag
        }
    }

    private var recordStateTag: some View {
        HStack(spacing: 6) {
            if recordVM.state == .recording {
                Circle()
                    .fill(.red)
                    .frame(width: 7, height: 7)
                    .modifier(BlinkingModifier())
            } else if recordVM.state == .paused {
                Image(systemName: "pause.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
            } else if recordVM.state == .stopped {
                Image(systemName: "waveform")
                    .font(.system(size: 9))
                    .foregroundStyle(.blue.opacity(0.8))
            }

            Text(recordStateLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(recordStateLabelColor)
                .textCase(.uppercase)
                .tracking(2)
        }
        .animation(.default, value: recordVM.state)
    }

    private var recordStateLabel: String {
        switch recordVM.state {
        case .idle:      return "Ready"
        case .recording: return "Recording"
        case .paused:    return "Paused"
        case .stopped:   return "Review"
        }
    }

    private var recordStateLabelColor: Color {
        switch recordVM.state {
        case .idle:      return .white.opacity(0.4)
        case .recording: return .red.opacity(0.9)
        case .paused:    return .orange.opacity(0.8)
        case .stopped:   return .blue.opacity(0.8)
        }
    }

    // MARK: - Record Control Bar

    private var recordControlBar: some View {
        VStack(spacing: 0) {
            if recordVM.state == .stopped {
                recordReviewControlBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                recordingControlBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: recordVM.state == .stopped)
    }

    // Recording controls: [Discard] [Record|Pause|Resume] [Stop]
    private var recordingControlBar: some View {
        HStack(alignment: .center, spacing: 0) {
            Group {
                if recordVM.canDiscard && recordVM.state == .paused {
                    recordAuxButton("trash", label: "Discard", color: .red.opacity(0.8)) {
                        withAnimation { recordVM.discardAndRestart() }
                    }
                } else {
                    Color.clear.frame(width: 64, height: 64)
                }
            }
            .frame(maxWidth: .infinity)

            Group {
                switch recordVM.state {
                case .idle:
                    recordBigRecordButton { recordVM.startRecording() }
                case .recording:
                    recordBigPauseButton { recordVM.pauseRecording() }
                case .paused:
                    recordBigResumeButton { recordVM.resumeRecording() }
                case .stopped:
                    EmptyView()
                }
            }

            Group {
                if recordVM.canStop {
                    recordAuxButton("stop.fill", label: "Stop", color: .white) {
                        recordVM.stopRecording()
                    }
                } else {
                    Color.clear.frame(width: 64, height: 64)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
    }

    // Review controls: [Re-record] [Play/Pause] [Use]
    private var recordReviewControlBar: some View {
        HStack(alignment: .center, spacing: 0) {
            recordAuxButton("arrow.counterclockwise", label: "Re-record", color: .white.opacity(0.7)) {
                withAnimation { recordVM.discardAndRestart() }
            }
            .frame(maxWidth: .infinity)

            recordBigPlayButton {
                recordVM.togglePlayback()
            }

            recordAuxButton("checkmark", label: "Use", color: .green) {
                acceptRecording()
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Record Big Buttons

    private func recordBigRecordButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(0.6), lineWidth: 3)
                    .frame(width: 80, height: 80)
                Circle()
                    .fill(.red)
                    .frame(width: 66, height: 66)
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private func recordBigPauseButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 80, height: 80)
                Circle()
                    .strokeBorder(.white.opacity(0.5), lineWidth: 2)
                    .frame(width: 80, height: 80)
                Image(systemName: "pause.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private func recordBigResumeButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(.orange.opacity(0.7), lineWidth: 3)
                    .frame(width: 80, height: 80)
                Circle()
                    .fill(.red.opacity(0.7))
                    .frame(width: 66, height: 66)
                Image(systemName: "mic.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private func recordBigPlayButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 80, height: 80)
                Circle()
                    .strokeBorder(.white.opacity(0.5), lineWidth: 2)
                    .frame(width: 80, height: 80)
                Image(systemName: recordVM.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.default, value: recordVM.isPlaying)
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private func recordAuxButton(_ icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 48, height: 48)
                    .background(color.opacity(0.1), in: Circle())
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(color.opacity(0.75))
                    .tracking(0.5)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Accept Recording

    private func acceptRecording() {
        guard let (data, fileName) = recordVM.getRecordingData() else { return }
        recordVM.stopPlayback()
        recordVM.cleanup()

        let mix = Mix(
            id: UUID(),
            type: .audio,
            createdAt: Date()
        )
        onDone(mix, .audio(data: data, fileName: fileName))
    }

    // MARK: - Done

    private var isDoneVisible: Bool {
        switch activeTab {
        case .text: !textContent.isEmpty
        default: false
        }
    }

    private func handleDone() {
        switch activeTab {
        case .text:
            let mix = Mix(
                id: UUID(),
                type: .text,
                createdAt: Date(),
                textContent: textContent
            )
            onDone(mix, nil)
        default:
            break
        }
    }

    // MARK: - Placeholders

    private func placeholderContent(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.3))
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.25))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(CreatorTab.allCases) { tab in
                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        activeTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: .medium))
                        Text(tab.label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(activeTab == tab ? .white : .white.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .glassEffect(in: .capsule)
    }
}

// MARK: - Centered Text View (UITextView subclass wrapper)

import UIKit

private final class NoteStyleUITextView: UITextView {
    override var contentInset: UIEdgeInsets {
        get { super.contentInset }
        set {
            // Block UIKit's automatic keyboard content inset adjustment.
            // Only allow our own inset (all zeros) — ignore any bottom inset
            // that UIKit tries to apply when the keyboard appears.
            var filtered = newValue
            filtered.bottom = 0
            super.contentInset = filtered
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let newInsets = UIEdgeInsets(top: 8, left: 8, bottom: 120, right: 8)
        if textContainerInset != newInsets {
            textContainerInset = newInsets
        }
    }
}

private struct CenteredTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var fontSize: CGFloat
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> NoteStyleUITextView {
        let tv = NoteStyleUITextView()
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear
        tv.textColor = UIColor.white.withAlphaComponent(0.9)
        tv.tintColor = .white
        tv.textAlignment = .natural
        tv.isScrollEnabled = true
        tv.showsVerticalScrollIndicator = false
        tv.isEditable = true
        tv.isSelectable = true
        tv.textContainer.lineFragmentPadding = 16
        tv.contentInsetAdjustmentBehavior = .never
        return tv
    }

    func updateUIView(_ tv: NoteStyleUITextView, context: Context) {
        let newFont = UIFont.systemFont(ofSize: fontSize, weight: .regular)
        if tv.font != newFont { tv.font = newFont }
        if tv.text != text { tv.text = text }

        if isFocused && !tv.isFirstResponder { tv.becomeFirstResponder() }
        else if !isFocused && tv.isFirstResponder { tv.resignFirstResponder() }
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: CenteredTextView
        init(_ parent: CenteredTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
        func textViewDidBeginEditing(_ textView: UITextView) { parent.isFocused = true }
        func textViewDidEndEditing(_ textView: UITextView) { parent.isFocused = false }
    }
}
