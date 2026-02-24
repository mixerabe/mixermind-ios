import SwiftUI
import MusicKit
import AVFoundation

@Observable @MainActor
final class AppleMusicSearchViewModel {
    var searchText = ""
    var songs: [Song] = []
    var isSearching = false
    var authorizationStatus: MusicAuthorization.Status = .notDetermined
    var errorMessage: String?

    // Preview playback
    var previewingSongId: MusicItemID?

    private var previewPlayer: AVPlayer?
    private var searchTask: Task<Void, Never>?
    private var endObserver: Any?

    // MARK: - Authorization

    func checkAuthorization() {
        authorizationStatus = MusicAuthorization.currentStatus
    }

    func requestAuthorization() async {
        let status = await MusicAuthorization.request()
        authorizationStatus = status
    }

    // MARK: - Search (debounced)

    func searchTextChanged() {
        searchTask?.cancel()

        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else {
            songs = []
            isSearching = false
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await performSearch(term: term)
        }
    }

    private func performSearch(term: String) async {
        isSearching = true
        errorMessage = nil

        do {
            var request = MusicCatalogSearchRequest(term: term, types: [Song.self])
            request.limit = 25
            let response = try await request.response()
            guard !Task.isCancelled else { return }
            songs = Array(response.songs)
            isSearching = false
        } catch {
            guard !Task.isCancelled else { return }
            isSearching = false
            errorMessage = "Search failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Preview Playback

    func togglePreview(for song: Song) {
        if previewingSongId == song.id {
            stopPreview()
            return
        }

        stopPreview()
        previewingSongId = song.id

        guard let url = song.previewAssets?.first?.url else {
            errorMessage = "No preview available for this song"
            previewingSongId = nil
            return
        }

        let player = AVPlayer(url: url)
        player.volume = 1.0
        previewPlayer = player
        player.play()

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.previewingSongId = nil
            }
        }
    }

    func stopPreview() {
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
        previewPlayer?.pause()
        previewPlayer = nil
        previewingSongId = nil
    }

    // MARK: - Download Preview Data

    func downloadPreviewData(for song: Song) async -> Data? {
        guard let url = song.previewAssets?.first?.url else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        } catch {
            return nil
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        stopPreview()
        searchTask?.cancel()
    }
}
