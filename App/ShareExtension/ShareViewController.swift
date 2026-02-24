import UIKit
import SwiftUI
import UniformTypeIdentifiers

@objc(ShareViewController)
class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let shareView = ShareExtensionView(
            extensionContext: extensionContext
        )
        let hostingController = UIHostingController(rootView: shareView)
        hostingController.view.backgroundColor = .clear

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hostingController.didMove(toParent: self)
    }
}

// MARK: - SwiftUI View

struct ShareExtensionView: View {
    let extensionContext: NSExtensionContext?

    @State private var allTags: [Tag] = []
    @State private var selectedTagIds: Set<UUID> = []
    @State private var sharedURL: URL?
    @State private var sharedText: String?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var saveResult: SaveResult?
    @State private var progressMessage = ""
    @State private var newTagName = ""
    @State private var isAddingTag = false
    @State private var selectedMode: ShareMode = .embed

    enum SaveResult {
        case success
        case failure(String)
    }

    /// Whether the shared URL looks like a scrapeable platform
    private var isScrapeable: Bool {
        guard let host = sharedURL?.host?.lowercased() else { return false }
        let scraperHosts = [
            "instagram.com", "www.instagram.com",
            "youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be",
            "tiktok.com", "www.tiktok.com", "vm.tiktok.com",
        ]
        return scraperHosts.contains(where: { host.contains($0) })
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                // Header
                header

                Divider().overlay(Color.white.opacity(0.1))

                if let result = saveResult {
                    resultView(result)
                } else if isLoading {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            previewSection

                            // Mode picker — only for scrapeable URLs
                            if sharedURL != nil && isScrapeable {
                                modePicker
                            }

                            Divider().overlay(Color.white.opacity(0.1))

                            tagSection
                        }
                        .padding(16)
                    }
                }
            }
            .background(Color(uiColor: .systemGray6).opacity(0.97))
            .clipShape(.rect(cornerRadius: 20))
            .padding(.horizontal, 16)
            .frame(maxHeight: 500)

            // Saving overlay
            if isSaving {
                Color.black.opacity(0.5)
                    .clipShape(.rect(cornerRadius: 20))
                    .padding(.horizontal, 16)
                    .frame(maxHeight: 500)
                    .overlay {
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(1.2)
                            Text(progressMessage)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    }
            }
        }
        .task {
            await loadContent()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .foregroundStyle(.white.opacity(0.7))

            Spacer()

            Text("Save to Remindr")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            Spacer()

            Button { save() } label: {
                Text("Save")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Color.accentColor)
                    .clipShape(.capsule)
            }
            .disabled(isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Preview

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let url = sharedURL {
                HStack(spacing: 10) {
                    Image(systemName: "link")
                        .font(.title3)
                        .foregroundStyle(.blue)
                        .frame(width: 32, height: 32)
                        .background(Color.blue.opacity(0.15))
                        .clipShape(.rect(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.host ?? url.absoluteString)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(url.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
            } else if let text = sharedText {
                HStack(spacing: 10) {
                    Image(systemName: "text.quote")
                        .font(.title3)
                        .foregroundStyle(.orange)
                        .frame(width: 32, height: 32)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(.rect(cornerRadius: 8))

                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .lineLimit(3)
                }
            }
        }
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Save as")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))

            HStack(spacing: 8) {
                modeButton(
                    title: "Embed Link",
                    icon: "link.badge.plus",
                    mode: .embed,
                    subtitle: "Save as bookmark"
                )
                modeButton(
                    title: "Import Video",
                    icon: "arrow.down.circle",
                    mode: .importVideo,
                    subtitle: "Download media"
                )
                modeButton(
                    title: "Import Audio",
                    icon: "waveform",
                    mode: .importAudio,
                    subtitle: "Extract audio"
                )
            }
        }
    }

    private func modeButton(title: String, icon: String, mode: ShareMode, subtitle: String) -> some View {
        let isSelected = selectedMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedMode = mode
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption2.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white.opacity(0.7) : .white.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
            .background(isSelected ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.08))
            .clipShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tags

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tags")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))

            ShareFlowLayout(spacing: 8) {
                // Add tag button / field
                if isAddingTag {
                    HStack(spacing: 6) {
                        TextField("#newtag", text: $newTagName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .frame(width: 100)
                            .onSubmit { addTag() }

                        Button { addTag() } label: {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                        }
                        .disabled(sanitized(newTagName).isEmpty)

                        Button {
                            isAddingTag = false
                            newTagName = ""
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.1))
                    .clipShape(.capsule)
                } else {
                    Button {
                        isAddingTag = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.caption.weight(.bold))
                            Text("Add Tag")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.accentColor)
                        .clipShape(.capsule)
                    }
                    .buttonStyle(.plain)
                }

                ForEach(allTags) { tag in
                    let isSelected = selectedTagIds.contains(tag.id)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isSelected {
                                selectedTagIds.remove(tag.id)
                            } else {
                                selectedTagIds.insert(tag.id)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("# \(tag.name)")
                            if isSelected {
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.bold))
                            }
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.8))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(isSelected ? Color.blue : Color.white.opacity(0.1))
                        .clipShape(.capsule)
                    }
                    .buttonStyle(.plain)
                }
            }

            if selectedTagIds.isEmpty {
                Text("No tags selected — will auto-tag as #inbox")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    // MARK: - Result View

    private func resultView(_ result: SaveResult) -> some View {
        VStack(spacing: 12) {
            switch result {
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
                Text("Saved!")
                    .font(.headline)
                    .foregroundStyle(.white)
            case .failure(let message):
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.red)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - Actions

    private func loadContent() async {
        if let items = extensionContext?.inputItems as? [NSExtensionItem] {
            outer: for item in items {
                guard let attachments = item.attachments else { continue }

                for provider in attachments {
                    if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                        if let result = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier),
                           let url = result as? URL {
                            sharedURL = url
                            break outer
                        }
                    }
                }

                for provider in attachments {
                    if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                        if let result = try? await provider.loadItem(forTypeIdentifier: UTType.text.identifier),
                           let text = result as? String {
                            if let url = URL(string: text), url.scheme?.hasPrefix("http") == true {
                                sharedURL = url
                            } else {
                                sharedText = text
                            }
                            break outer
                        }
                    }
                }
            }
        }

        // Default mode: if scrapeable URL, default to importVideo
        if isScrapeable {
            selectedMode = .importVideo
        }

        do {
            allTags = try await ShareService.loadTags()
        } catch {}

        isLoading = false
    }

    private func save() {
        isSaving = true
        progressMessage = "Saving..."
        Task {
            do {
                try await ShareService.save(
                    url: sharedURL,
                    text: sharedText,
                    tagIds: selectedTagIds,
                    mode: selectedMode,
                    onProgress: { msg in
                        Task { @MainActor in
                            progressMessage = msg
                        }
                    }
                )
                saveResult = .success
                try? await Task.sleep(for: .seconds(1.0))
                dismiss()
            } catch {
                isSaving = false
                saveResult = .failure(error.localizedDescription)
                try? await Task.sleep(for: .seconds(2.5))
                dismiss()
            }
        }
    }

    private func addTag() {
        let name = newTagName
        newTagName = ""
        isAddingTag = false
        let cleaned = sanitized(name)
        guard !cleaned.isEmpty else { return }
        if let existing = allTags.first(where: { $0.name.lowercased() == cleaned.lowercased() }) {
            selectedTagIds.insert(existing.id)
            return
        }
        Task {
            if let tag = try? await ShareService.createTag(name: cleaned) {
                allTags.append(tag)
                selectedTagIds.insert(tag.id)
            }
        }
    }

    private func sanitized(_ name: String) -> String {
        name.replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    private func dismiss() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
