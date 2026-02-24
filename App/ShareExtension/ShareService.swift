import Foundation
import AVFoundation

enum ShareMode {
    case embed
    case importVideo
    case importAudio
}

enum ShareService {

    // MARK: - Tags

    static func loadTags() async throws -> [Tag] {
        configureSupabase()
        return try await TagRepository().listTags()
    }

    static func createTag(name: String) async throws -> Tag {
        configureSupabase()
        return try await TagRepository().createTag(name: name)
    }

    // MARK: - Save

    static func save(
        url: URL?,
        text: String?,
        tagIds: Set<UUID>,
        mode: ShareMode,
        onProgress: @escaping (String) -> Void
    ) async throws {
        configureSupabase()

        let mixRepo = MixRepository()
        let tagRepo = TagRepository()

        let payload: CreateMixPayload

        if let url, mode == .importVideo || mode == .importAudio {
            payload = try await buildMediaPayload(
                url: url,
                mode: mode,
                mixRepo: mixRepo,
                onProgress: onProgress
            )
        } else if let url {
            // Embed path
            onProgress("Fetching link info...")
            let og = try? await OpenGraphService.fetch(url.absoluteString)
            payload = CreateMixPayload(
                type: .embed,
                embedUrl: url.absoluteString,
                embedOg: og
            )
        } else {
            // Text content
            payload = CreateMixPayload(
                type: .text,
                textContent: text
            )
        }

        onProgress("Saving...")
        let mix = try await mixRepo.createMix(payload)

        var finalTagIds = tagIds
        if finalTagIds.isEmpty {
            let allTags = try await tagRepo.listTags()
            if let inbox = allTags.first(where: { $0.name.lowercased() == "inbox" }) {
                finalTagIds = [inbox.id]
            } else {
                let inbox = try await tagRepo.createTag(name: "inbox")
                finalTagIds = [inbox.id]
            }
        }

        try await tagRepo.setTagsForMix(mixId: mix.id, tagIds: finalTagIds)
    }

    // MARK: - Media Import

    private static func buildMediaPayload(
        url: URL,
        mode: ShareMode,
        mixRepo: MixRepository,
        onProgress: @escaping (String) -> Void
    ) async throws -> CreateMixPayload {
        onProgress("Resolving media...")
        let result = try await MediaURLService.resolve(url.absoluteString)

        switch mode {
        case .importVideo:
            guard let videoURL = result.videoURL else {
                throw MediaURLService.MediaError.noMediaFound
            }
            onProgress("Downloading video...")
            let (videoData, _) = try await URLSession.shared.data(from: videoURL)

            onProgress("Uploading video...")
            let uploadedURL = try await mixRepo.uploadMedia(
                data: videoData,
                fileName: "\(result.platform.rawValue)_video.mp4",
                contentType: "video/mp4"
            )

            return CreateMixPayload(
                type: .import,
                importSourceUrl: url.absoluteString,
                importMediaUrl: uploadedURL
            )

        case .importAudio:
            let audioData: Data
            if let audioURL = result.audioURL {
                onProgress("Downloading audio...")
                (audioData, _) = try await URLSession.shared.data(from: audioURL)
            } else if let videoURL = result.videoURL {
                onProgress("Downloading...")
                let (videoData, _) = try await URLSession.shared.data(from: videoURL)
                onProgress("Extracting audio...")
                audioData = try await extractAudio(from: videoData)
            } else {
                throw MediaURLService.MediaError.noMediaFound
            }

            onProgress("Uploading audio...")
            let uploadedURL = try await mixRepo.uploadMedia(
                data: audioData,
                fileName: "\(result.platform.rawValue)_audio.m4a",
                contentType: "audio/aac"
            )

            return CreateMixPayload(
                type: .import,
                importSourceUrl: url.absoluteString,
                importAudioUrl: uploadedURL
            )

        case .embed:
            fatalError("embed mode should not reach buildMediaPayload")
        }
    }

    // MARK: - Audio Extraction

    private static func extractAudio(from videoData: Data) async throws -> Data {
        let fm = FileManager.default
        let inputURL = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        let outputURL = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_audio.m4a")
        try videoData.write(to: inputURL)
        defer {
            try? fm.removeItem(at: inputURL)
            try? fm.removeItem(at: outputURL)
        }

        let asset = AVURLAsset(url: inputURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw MediaURLService.MediaError.serverError("Failed to create audio export session")
        }
        session.outputURL = outputURL
        session.outputFileType = .m4a

        await session.export()

        guard session.status == .completed else {
            let msg = session.error?.localizedDescription ?? "unknown"
            throw MediaURLService.MediaError.serverError("Audio extraction failed: \(msg)")
        }

        return try Data(contentsOf: outputURL)
    }

    // MARK: - Supabase Config

    static func configureSupabase() {
        guard !SupabaseManager.shared.isConfigured else { return }

        let defaults = UserDefaults(suiteName: Constants.appGroupId) ?? .standard
        if let url = defaults.string(forKey: Constants.supabaseURLKey),
           let key = defaults.string(forKey: Constants.supabaseKeyKey) {
            SupabaseManager.shared.configure(url: url, key: key)
            return
        }

        SupabaseManager.shared.configure(
            url: Constants.publicSupabaseURL,
            key: Constants.publicSupabaseKey
        )
    }
}
