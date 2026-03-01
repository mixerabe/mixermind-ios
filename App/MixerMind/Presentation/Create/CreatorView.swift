import SwiftUI
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Creator Tab

enum CreatorTab: Int, CaseIterable, Identifiable {
    case media, note, voice, create, `import`

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .media: "Camera"
        case .note: "Note"
        case .voice: "Voice"
        case .create: "Create"
        case .`import`: "Import"
        }
    }

    var icon: String {
        switch self {
        case .media: "camera.fill"
        case .note: "textformat"
        case .voice: "mic"
        case .create: "paintbrush.fill"
        case .`import`: "square.and.arrow.down"
        }
    }
}

enum CreateSubTab: Int, CaseIterable, Identifiable {
    case plain, file, embed
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .plain: "Plain"
        case .file: "File"
        case .embed: "Embed"
        }
    }

    var icon: String {
        switch self {
        case .plain: "paintbrush.fill"
        case .file: "doc.fill"
        case .embed: "link.badge.plus"
        }
    }
}

// MARK: - Creator Media

enum CreatorMedia {
    case photo(data: Data, thumbnail: UIImage?)
    case video(data: Data, thumbnail: UIImage?)
    case voiceRecording(data: Data)
    case file(data: Data, fileName: String)
    case importVideo(data: Data, thumbnail: UIImage?, sourceUrl: String, title: String?)
}

// MARK: - Creator View

struct CreatorView: View {
    var onDismiss: () -> Void
    var onDone: (Mix, CreatorMedia?) -> Void = { _, _ in }
    @State private var activeTab: CreatorTab = .note
    // Note tab state
    @State private var textContent: String = ""
    @State private var isTextEditorFocused: Bool = false

    // Create > Embed sub-tab state
    @State private var embedUrlText: String = ""
    @State private var isFetchingOG = false
    @State private var embedError: String?
    @FocusState private var isEmbedFieldFocused: Bool

    // Media tab state
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isLoadingMedia = false
    @State private var mediaError: String?
    @State private var showPhotoPicker = false
    @State private var cameraManager = InlineCameraManager()

    // Voice tab state
    @State private var recordVM = RecordAudioViewModel()

    // Create tab state
    @State private var activeSubTab: CreateSubTab = .plain
    @State private var showFilePicker = false
    @State private var gradientIndex: Int = 0

    // Import tab state
    @State private var importUrlText: String = ""
    @State private var importPlatform: String?
    @State private var isDownloading = false
    @State private var downloadError: String?
    @FocusState private var isImportFieldFocused: Bool

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [
                    Color(hex: "#1a1a2e"),
                    Color(hex: "#16213e")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Canvas content
            canvasArea

            // Bottom bar
            VStack {
                Spacer()
                bottomBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            .ignoresSafeArea(.keyboard)
        }
        .onChange(of: activeTab) { oldTab, newTab in
            if oldTab == .voice {
                recordVM.stopPlayback()
                recordVM.cleanup()
                recordVM = RecordAudioViewModel()
            }
            if oldTab == .media {
                cameraManager.stopSession()
            }
            if newTab == .media {
                cameraManager.startSession()
            }
        }
    }

    // MARK: - Canvas (tab content, no swiping)

    private var canvasArea: some View {
        tabContent(for: activeTab)
    }

    @ViewBuilder
    private func tabContent(for tab: CreatorTab) -> some View {
        switch tab {
        case .note:
            textTabContent
        case .media:
            mediaTabContent
        case .voice:
            voiceTabContent
        case .create:
            createTabContent
        case .`import`:
            importTabContent
        }
    }

    // MARK: - Text Tab

    private var textTabContent: some View {
        ZStack(alignment: .topLeading) {
            CenteredTextView(
                text: $textContent,
                isFocused: $isTextEditorFocused,
                fontSize: textDynamicFontSize,
                containerWidth: ScreenshotService.TextBucket.current.containerWidth
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

    // MARK: - Media Tab

    private var mediaTabContent: some View {
        ZStack {
            if cameraManager.cameraAvailable {
                // Inline camera preview — fills the canvas
                InlineCameraPreview(session: cameraManager.session)
                    .ignoresSafeArea()
            } else if !cameraManager.permissionDenied {
                // No camera (simulator) — show placeholder with Library option
                VStack(spacing: 16) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.2))
                    Text("No camera available")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.4))
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .frame(height: 48)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(in: .capsule)
                }
            }

            // Camera controls — only when camera is live
            if cameraManager.cameraAvailable {
                VStack {
                    Spacer()

                    HStack(alignment: .center, spacing: 0) {
                        // Library button (leading)
                        Button {
                            showPhotoPicker = true
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.white.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "photo.on.rectangle")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)

                        // Shutter button (center)
                        Button {
                            cameraManager.capturePhoto { data, image in
                                guard let data, let image else { return }
                                let mix = Mix(id: UUID(), type: .media, createdAt: Date(), mediaIsVideo: false)
                                onDone(mix, .photo(data: data, thumbnail: image))
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .strokeBorder(.white.opacity(0.8), lineWidth: 3)
                                    .frame(width: 72, height: 72)
                                Circle()
                                    .fill(.white)
                                    .frame(width: 60, height: 60)
                            }
                        }
                        .buttonStyle(ScaleButtonStyle())

                        // Flip camera button (trailing)
                        Button {
                            cameraManager.switchCamera()
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.white.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "camera.rotate")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 80)
                }
            }

            // Permission denied overlay
            if cameraManager.permissionDenied {
                VStack(spacing: 16) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("Camera access required")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.6))
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Open Settings")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .frame(height: 44)
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
            loadPhotoItem(item)
        }
        .onAppear {
            cameraManager.setupSession()
            cameraManager.startSession()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
    }

    private func loadPhotoItem(_ item: PhotosPickerItem) {
        Task {
            let isVideo = item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) })
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }
            if isVideo {
                let thumbnail = await generateVideoThumbnail(from: data)
                let mix = Mix(id: UUID(), type: .media, createdAt: Date(), mediaIsVideo: true)
                onDone(mix, .video(data: data, thumbnail: thumbnail))
            } else {
                let thumbnail = UIImage(data: data)
                let mix = Mix(id: UUID(), type: .media, createdAt: Date(), mediaIsVideo: false)
                onDone(mix, .photo(data: data, thumbnail: thumbnail))
            }
        }
    }

    private func generateVideoThumbnail(from data: Data) async -> UIImage? {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        try? data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let asset = AVURLAsset(url: tempURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)
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

            let defaultGradient = GradientPreset.allPresets[0]
            let widget = MixWidget(
                id: UUID(),
                type: .embed,
                embedUrl: normalized,
                embedOg: og
            )
            let mix = Mix(
                id: UUID(),
                type: .canvas,
                createdAt: Date(),
                widgets: [widget],
                gradientTop: defaultGradient.top,
                gradientBottom: defaultGradient.bottom
            )

            isFetchingOG = false
            onDone(mix, nil)
        }
    }

    // MARK: - Voice Tab (was Record)

    private var voiceTabContent: some View {
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
            voiceTimeDisplay
                .padding(.bottom, 8)

            Spacer().frame(maxHeight: 24)

            // Control bar
            voiceControlBar
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

    // MARK: - Voice Time Display

    private var voiceTimeDisplay: some View {
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

            voiceStateTag
        }
    }

    private var voiceStateTag: some View {
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

            Text(voiceStateLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(voiceStateLabelColor)
                .textCase(.uppercase)
                .tracking(2)
        }
        .animation(.default, value: recordVM.state)
    }

    private var voiceStateLabel: String {
        switch recordVM.state {
        case .idle:      return "Ready"
        case .recording: return "Recording"
        case .paused:    return "Paused"
        case .stopped:   return "Review"
        }
    }

    private var voiceStateLabelColor: Color {
        switch recordVM.state {
        case .idle:      return .white.opacity(0.4)
        case .recording: return .red.opacity(0.9)
        case .paused:    return .orange.opacity(0.8)
        case .stopped:   return .blue.opacity(0.8)
        }
    }

    // MARK: - Voice Control Bar

    private var voiceControlBar: some View {
        VStack(spacing: 0) {
            if recordVM.state == .stopped {
                voiceReviewControlBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                voiceRecordingControlBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: recordVM.state == .stopped)
    }

    // Recording controls: [Discard] [Record|Pause|Resume] [Stop]
    private var voiceRecordingControlBar: some View {
        HStack(alignment: .center, spacing: 0) {
            Group {
                if recordVM.canDiscard && recordVM.state == .paused {
                    voiceAuxButton("trash", label: "Discard", color: .red.opacity(0.8)) {
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
                    voiceBigRecordButton { recordVM.startRecording() }
                case .recording:
                    voiceBigPauseButton { recordVM.pauseRecording() }
                case .paused:
                    voiceBigResumeButton { recordVM.resumeRecording() }
                case .stopped:
                    EmptyView()
                }
            }

            Group {
                if recordVM.canStop {
                    voiceAuxButton("stop.fill", label: "Stop", color: .white) {
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
    private var voiceReviewControlBar: some View {
        HStack(alignment: .center, spacing: 0) {
            voiceAuxButton("arrow.counterclockwise", label: "Re-record", color: .white.opacity(0.7)) {
                withAnimation { recordVM.discardAndRestart() }
            }
            .frame(maxWidth: .infinity)

            voiceBigPlayButton {
                recordVM.togglePlayback()
            }

            voiceAuxButton("checkmark", label: "Use", color: .green) {
                acceptVoiceRecording()
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Voice Big Buttons

    private func voiceBigRecordButton(action: @escaping () -> Void) -> some View {
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

    private func voiceBigPauseButton(action: @escaping () -> Void) -> some View {
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

    private func voiceBigResumeButton(action: @escaping () -> Void) -> some View {
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

    private func voiceBigPlayButton(action: @escaping () -> Void) -> some View {
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

    private func voiceAuxButton(_ icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
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

    // MARK: - Accept Voice Recording

    private func acceptVoiceRecording() {
        guard let (data, _) = recordVM.getRecordingData() else { return }
        recordVM.stopPlayback()
        recordVM.cleanup()

        let mix = Mix(
            id: UUID(),
            type: .voice,
            createdAt: Date()
        )
        onDone(mix, .voiceRecording(data: data))
    }

    // MARK: - Create Tab (unified: Plain / File / Embed sub-tabs)

    private var createTabContent: some View {
        ZStack {
            // Sub-tab content (behind carousel)
            Group {
                switch activeSubTab {
                case .plain:
                    createPlainContent
                case .file:
                    createFileContent
                case .embed:
                    createEmbedContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Sub-tab carousel (just above the main bottom bar)
            VStack {
                Spacer()
                CreateSubTabCarousel(
                    activeSubTab: $activeSubTab,
                    onCenterTap: { handleSubTabAction() }
                )
                .padding(.bottom, 80)
            }
            .ignoresSafeArea(.keyboard)
        }
    }

    private func handleSubTabAction() {
        switch activeSubTab {
        case .plain:
            let preset = GradientPreset.allPresets[gradientIndex]
            let mix = Mix(
                id: UUID(),
                type: .canvas,
                createdAt: Date(),
                gradientTop: preset.top,
                gradientBottom: preset.bottom
            )
            onDone(mix, nil)
        case .file:
            showFilePicker = true
        case .embed:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isEmbedFieldFocused = true
            }
        }
    }

    // Plain sub-tab: live gradient background with cycle button
    private var createPlainContent: some View {
        let preset = GradientPreset.allPresets[gradientIndex]
        return ZStack {
            // Cycle gradient button — top right
            VStack {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            gradientIndex = (gradientIndex + 1) % GradientPreset.allPresets.count
                        }
                    } label: {
                        Image(systemName: "paintpalette.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(in: .circle)
                }
                .padding(.trailing, 16)
                .padding(.top, 16)
                Spacer()
            }
        }
        .background(
            LinearGradient(
                colors: [Color(hex: preset.top), Color(hex: preset.bottom)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.5), value: gradientIndex)
        )
    }

    // File sub-tab
    private var createFileContent: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "doc.fill")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.25))

            Text("Upload any file")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.5))

            Text("Tap the center button to choose")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.3))

            Spacer()
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    // Embed sub-tab
    private var createEmbedContent: some View {
        embedTabContent
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: url) else { return }
        let name = url.lastPathComponent

        let defaultGradient = GradientPreset.allPresets[0]
        let widget = MixWidget(
            id: UUID(),
            type: .file,
            fileName: name
        )
        let mix = Mix(
            id: UUID(),
            type: .canvas,
            createdAt: Date(),
            widgets: [widget],
            gradientTop: defaultGradient.top,
            gradientBottom: defaultGradient.bottom
        )
        onDone(mix, .file(data: data, fileName: name))
    }

    // MARK: - Import Tab

    private var importTabContent: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                if let platform = importPlatform {
                    Image(systemName: platform == "instagram" ? "camera.circle.fill" : "play.rectangle.fill")
                        .font(.title2)
                        .foregroundStyle(platform == "instagram" ? .pink : .red)
                        .transition(.scale.combined(with: .opacity))
                }

                TextField("Paste Instagram or YouTube link", text: $importUrlText)
                    .focused($isImportFieldFocused)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding()
            .glassEffect(in: .rect(cornerRadius: 12))
            .onChange(of: importUrlText) { _, newValue in
                withAnimation(.spring(duration: 0.2)) {
                    importPlatform = ImportDownloadService.detectPlatform(newValue)
                }
            }

            if isDownloading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("Downloading...")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            if let error = downloadError {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.red.opacity(0.8))
            }

            HStack(spacing: 12) {
                Button { startImport(mode: .video) } label: {
                    Label("Video", systemImage: "video.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.plain)
                .glassEffect(in: .capsule)
                .disabled(importPlatform == nil || isDownloading)
                .opacity(importPlatform == nil || isDownloading ? 0.4 : 1)

                Button { startImport(mode: .audioOnly) } label: {
                    Label("Audio Only", systemImage: "waveform")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.plain)
                .glassEffect(in: .capsule)
                .disabled(importPlatform == nil || isDownloading)
                .opacity(importPlatform == nil || isDownloading ? 0.4 : 1)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { isImportFieldFocused = true }
    }

    private func startImport(mode: ImportMode) {
        let trimmed = importUrlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isDownloading else { return }

        var normalized = trimmed
        if !normalized.hasPrefix("http://") && !normalized.hasPrefix("https://") {
            normalized = "https://\(normalized)"
        }

        downloadError = nil
        isDownloading = true
        isImportFieldFocused = false

        Task {
            do {
                let result = try await ImportDownloadService.download(url: normalized, mode: mode)
                let thumbnail: UIImage? = await ImportDownloadService.generateThumbnail(from: result.videoData)

                let isVideo = mode == .video
                let mix = Mix(
                    id: UUID(),
                    type: .import,
                    createdAt: Date(),
                    title: result.title,
                    mediaIsVideo: isVideo,
                    sourceUrl: normalized
                )

                isDownloading = false
                onDone(mix, .importVideo(data: result.videoData, thumbnail: thumbnail, sourceUrl: normalized, title: result.title))
            } catch {
                downloadError = error.localizedDescription
                isDownloading = false
            }
        }
    }

    // MARK: - Done

    private func handleDone() {
        switch activeTab {
        case .note:
            let mix = Mix(
                id: UUID(),
                type: .note,
                createdAt: Date(),
                textContent: textContent
            )
            onDone(mix, nil)
        default:
            break
        }
    }

    // MARK: - Bottom Bar

    private var canSubmit: Bool {
        switch activeTab {
        case .note: return !textContent.isEmpty
        case .create:
            if activeSubTab == .embed {
                return !embedUrlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return false
        case .media, .voice, .`import`: return false
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            // X — dismiss
            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)

            // Carousel tab labels
            CarouselTabBar(activeTab: $activeTab)

            // → submit
            Button { handleDone() } label: {
                Image(systemName: "arrow.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .opacity(canSubmit ? 1 : 0.25)
            .disabled(!canSubmit)
        }
        .padding(.horizontal, 4)
        .frame(height: 56)
        .glassEffect(in: .capsule)
    }
}

// MARK: - Carousel Tab Bar

private struct CarouselTabBar: View {
    @Binding var activeTab: CreatorTab
    private let tabWidth: CGFloat = 70
    private let tabs = CreatorTab.allCases

    var body: some View {
        GeometryReader { geo in
            let containerCenter = geo.size.width / 2
            let selectedIndex = CGFloat(activeTab.rawValue)
            let stripOffset = containerCenter - (selectedIndex * tabWidth) - (tabWidth / 2)

            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    let distance = abs(CGFloat(tab.rawValue) - selectedIndex)
                    let opacity = max(0.15, 1.0 - distance * 0.35)
                    let scale = max(0.85, 1.0 - distance * 0.06)

                    Button {
                        withAnimation(.spring(duration: 0.25)) {
                            activeTab = tab
                        }
                    } label: {
                        Text(tab.label)
                            .font(.subheadline.weight(activeTab == tab ? .bold : .regular))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .frame(width: tabWidth, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .opacity(opacity)
                    .scaleEffect(scale)
                }
            }
            .offset(x: stripOffset)
            .animation(.spring(duration: 0.3), value: activeTab)
        }
        .frame(height: 44)
        .clipped()
    }
}

// MARK: - Create Sub-Tab Carousel

private struct CreateSubTabCarousel: View {
    @Binding var activeSubTab: CreateSubTab
    var onCenterTap: () -> Void

    private let allTabs = CreateSubTab.allCases
    private let bigSize: CGFloat = 80
    private let smallSize: CGFloat = 52
    // Distance between centers of adjacent circles
    private let step: CGFloat = 110

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        let activeIndex = CGFloat(activeSubTab.rawValue)
        let fractionalShift = -dragOffset / step
        let currentFractional = activeIndex + fractionalShift

        ZStack {
            ForEach(allTabs) { tab in
                let tabIndex = CGFloat(tab.rawValue)
                // Position relative to center: (tabIndex - activeIndex) * step
                let xPos = (tabIndex - activeIndex) * step + dragOffset
                let distance = abs(tabIndex - currentFractional)
                let isCenter = distance < 0.5

                let t = min(distance, 1.0)
                let size = bigSize - (bigSize - smallSize) * t

                Button {
                    if isCenter {
                        onCenterTap()
                    } else {
                        withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                            activeSubTab = tab
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(.white.opacity(0.8 * max(0, 1.0 - t)), lineWidth: 3)
                            .frame(width: size + 6, height: size + 6)

                        Circle()
                            .fill(Color.white.opacity(isCenter ? 0.2 : 0.08))
                            .frame(width: size, height: size)

                        circleIcon(for: tab)
                            .foregroundStyle(.white.opacity(isCenter ? 1.0 : 0.5))
                    }
                }
                .buttonStyle(ScaleButtonStyle())
                .offset(x: xPos)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: bigSize + 6)
        .contentShape(.rect)
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    let threshold: CGFloat = 40
                    var newIndex = activeSubTab.rawValue
                    if value.translation.width < -threshold {
                        newIndex = min(newIndex + 1, allTabs.count - 1)
                    } else if value.translation.width > threshold {
                        newIndex = max(newIndex - 1, 0)
                    }
                    withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                        activeSubTab = allTabs[newIndex]
                        dragOffset = 0
                    }
                }
        )
        .animation(.spring(duration: 0.35, bounce: 0.2), value: activeSubTab)
    }

    @ViewBuilder
    private func circleIcon(for tab: CreateSubTab) -> some View {
        switch tab {
        case .plain:
            Text("Aa")
                .font(.system(size: 20, weight: .bold, design: .rounded))
        case .file:
            Image(systemName: "doc.fill")
                .font(.system(size: 20, weight: .medium))
        case .embed:
            Image(systemName: "link")
                .font(.system(size: 20, weight: .medium))
        }
    }
}

// MARK: - Gradient Presets

struct GradientPreset: Identifiable {
    let id: String
    let name: String
    let top: String
    let bottom: String

    static let allPresets: [GradientPreset] = [
        GradientPreset(id: "dark-blue", name: "Dark Blue", top: "#1a1a2e", bottom: "#16213e"),
        GradientPreset(id: "deep-indigo", name: "Deep Indigo", top: "#0f0c29", bottom: "#302b63"),
        GradientPreset(id: "dark-purple", name: "Dark Purple", top: "#1a0a1e", bottom: "#3d1a4e"),
        GradientPreset(id: "dark-forest", name: "Dark Forest", top: "#0a1a0a", bottom: "#1a3d2e"),
        GradientPreset(id: "dark-crimson", name: "Dark Crimson", top: "#1a0a0a", bottom: "#3d1a1a"),
        GradientPreset(id: "charcoal", name: "Charcoal", top: "#1a1a1a", bottom: "#2d2d2d"),
    ]
}

// MARK: - Inline Camera Manager

@Observable
final class InlineCameraManager: NSObject {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private var isSessionConfigured = false
    private var currentPosition: AVCaptureDevice.Position = .back
    var permissionDenied = false
    var cameraAvailable = false

    private var captureCompletion: ((Data?, UIImage?) -> Void)?

    func setupSession() {
        guard !isSessionConfigured else { return }
        sessionQueue.async { [self] in
            // Check if a camera device exists at all (not available in Simulator)
            guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil else {
                DispatchQueue.main.async { self.cameraAvailable = false }
                return
            }

            let status = AVCaptureDevice.authorizationStatus(for: .video)
            switch status {
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    if granted {
                        self.configureSession()
                    } else {
                        DispatchQueue.main.async { self.permissionDenied = true }
                    }
                }
            case .authorized:
                configureSession()
            default:
                DispatchQueue.main.async { self.permissionDenied = true }
            }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentPosition),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else { return }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else { return }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .speed

        isSessionConfigured = true
        DispatchQueue.main.async { self.cameraAvailable = true }
    }

    func startSession() {
        sessionQueue.async { [self] in
            if isSessionConfigured && !session.isRunning {
                session.startRunning()
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [self] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    func capturePhoto(completion: @escaping (Data?, UIImage?) -> Void) {
        guard isSessionConfigured,
              photoOutput.connection(with: .video) != nil else {
            completion(nil, nil)
            return
        }
        captureCompletion = completion
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .speed
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func switchCamera() {
        sessionQueue.async { [self] in
            guard let currentInput = session.inputs.first as? AVCaptureDeviceInput else { return }
            let newPosition: AVCaptureDevice.Position = currentPosition == .back ? .front : .back
            guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }

            session.beginConfiguration()
            session.removeInput(currentInput)
            if session.canAddInput(newInput) {
                session.addInput(newInput)
                currentPosition = newPosition
            } else {
                session.addInput(currentInput)
            }
            session.commitConfiguration()
        }
    }
}

extension InlineCameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            DispatchQueue.main.async { self.captureCompletion?(nil, nil) }
            return
        }
        let image = UIImage(data: data)
        DispatchQueue.main.async {
            self.captureCompletion?(data, image)
            self.captureCompletion = nil
        }
    }
}

// MARK: - Inline Camera Preview

struct InlineCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - Centered Text View (UITextView subclass wrapper)

import UIKit

private final class NoteStyleUITextView: UITextView {
    var fixedContainerWidth: CGFloat?

    override var contentInset: UIEdgeInsets {
        get { super.contentInset }
        set {
            // Block UIKit's automatic keyboard content inset adjustment.
            var filtered = newValue
            filtered.bottom = 0
            super.contentInset = filtered
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        if let fixedWidth = fixedContainerWidth {
            // Center the text at the fixed bucket width.
            // lineFragmentPadding is 16 on each side, so the text area is
            // textContainerInset.left + lineFragmentPadding ... right.
            // We want: lineFragmentPadding(16) + textWidth = fixedWidth
            // So textWidth = fixedWidth - 2*16 = fixedWidth - 32
            // Total consumed = inset.left + 16 + textWidth + 16 + inset.right = bounds.width
            // inset.left + inset.right = bounds.width - fixedWidth
            let padding = textContainer.lineFragmentPadding // 16
            let totalInset = max(bounds.width - fixedWidth - padding * 2, 0)
            let side = totalInset / 2
            let newInsets = UIEdgeInsets(top: 8, left: side, bottom: 120, right: side)
            if textContainerInset != newInsets {
                textContainerInset = newInsets
            }
        } else {
            let newInsets = UIEdgeInsets(top: 8, left: 8, bottom: 120, right: 8)
            if textContainerInset != newInsets {
                textContainerInset = newInsets
            }
        }
    }
}

private struct CenteredTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var fontSize: CGFloat
    var containerWidth: CGFloat? = nil
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
        tv.fixedContainerWidth = containerWidth

        // Match lineSpacing with viewer and screenshot renderer
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 6
        let font = UIFont.systemFont(ofSize: fontSize, weight: .regular)
        tv.typingAttributes = [
            .font: font,
            .foregroundColor: UIColor.white.withAlphaComponent(0.9),
            .paragraphStyle: paragraphStyle
        ]

        return tv
    }

    func updateUIView(_ tv: NoteStyleUITextView, context: Context) {
        let newFont = UIFont.systemFont(ofSize: fontSize, weight: .regular)
        if tv.font != newFont { tv.font = newFont }
        if tv.text != text { tv.text = text }
        tv.fixedContainerWidth = containerWidth

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
