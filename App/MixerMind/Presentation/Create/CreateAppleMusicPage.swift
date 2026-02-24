import SwiftUI
import MusicKit

struct CreateAppleMusicPage: View {
    @State private var createViewModel = CreateMixViewModel()
    @State private var searchViewModel = AppleMusicSearchViewModel()
    @State private var isSaving = false
    @State private var confirmingSong: Song?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Group {
                switch searchViewModel.authorizationStatus {
                case .authorized:
                    searchContent
                case .denied, .restricted:
                    deniedContent
                case .notDetermined:
                    ProgressView("Requesting access...")
                @unknown default:
                    deniedContent
                }
            }

            if isSaving {
                Color(.systemBackground).opacity(0.7).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Saving...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Apple Music")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            searchViewModel.checkAuthorization()
            if searchViewModel.authorizationStatus == .notDetermined {
                await searchViewModel.requestAuthorization()
            }
        }
        .onDisappear {
            searchViewModel.cleanup()
        }
        .alert("Microphone Access Required", isPresented: .constant(false)) {}
    }

    // MARK: - Search Content

    private var searchContent: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search songs...", text: $searchViewModel.searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                if !searchViewModel.searchText.isEmpty {
                    Button {
                        searchViewModel.searchText = ""
                        searchViewModel.songs = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .glassEffect(in: .rect(cornerRadius: 10))
            .padding(.horizontal)
            .padding(.vertical, 8)
            .onChange(of: searchViewModel.searchText) {
                searchViewModel.searchTextChanged()
            }

            if searchViewModel.isSearching && searchViewModel.songs.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else if searchViewModel.songs.isEmpty && !searchViewModel.searchText.isEmpty {
                Spacer()
                ContentUnavailableView.search(text: searchViewModel.searchText)
                Spacer()
            } else if searchViewModel.songs.isEmpty {
                Spacer()
                Text("Search for a song")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(searchViewModel.songs, id: \.id) { song in
                    songRow(song)
                }
                .listStyle(.plain)
            }

            if let error = searchViewModel.errorMessage ?? createViewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }
        }
        .alert("Add this song?", isPresented: Binding(
            get: { confirmingSong != nil },
            set: { if !$0 { confirmingSong = nil } }
        )) {
            Button("Cancel", role: .cancel) { confirmingSong = nil }
            Button("Add") {
                if let song = confirmingSong { selectSong(song) }
            }
        } message: {
            if let song = confirmingSong {
                Text("\(song.title) by \(song.artistName)")
            }
        }
    }

    // MARK: - Song Row

    private func songRow(_ song: Song) -> some View {
        HStack(spacing: 12) {
            if let artwork = song.artwork {
                ArtworkImage(artwork, width: 50, height: 50)
                    .clipShape(.rect(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray5))
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.body)
                    .lineLimit(1)
                Text(song.artistName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if song.previewAssets?.first?.url != nil {
                Button {
                    searchViewModel.togglePreview(for: song)
                } label: {
                    Image(systemName: searchViewModel.previewingSongId == song.id
                          ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(searchViewModel.previewingSongId == song.id
                                         ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            confirmingSong = song
        }
    }

    // MARK: - Denied Content

    private var deniedContent: some View {
        ContentUnavailableView {
            Label("Apple Music Access Denied", systemImage: "music.note.list")
        } description: {
            Text("Allow access to Apple Music in Settings to search for songs.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Select & Save

    private func selectSong(_ song: Song) {
        searchViewModel.stopPreview()

        let songId = song.id.rawValue
        let title = song.title
        let artist = song.artistName
        let artworkUrl = song.artwork?.url(width: 300, height: 300)?.absoluteString

        isSaving = true
        Task {
            let previewData = await searchViewModel.downloadPreviewData(for: song)
            searchViewModel.cleanup()

            createViewModel.setAppleMusicSong(
                id: songId,
                title: title,
                artist: artist,
                artworkUrl: artworkUrl,
                previewData: previewData
            )

            let success = await createViewModel.saveMix()
            if success {
                dismiss()
            } else {
                isSaving = false
            }
        }
    }
}
