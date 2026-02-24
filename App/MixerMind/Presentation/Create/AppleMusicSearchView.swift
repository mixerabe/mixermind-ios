import SwiftUI
import MusicKit

struct AppleMusicSearchView: View {
    var onSongSelected: (String, String, String, String?, Data?) -> Void
    @State private var viewModel = AppleMusicSearchViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingSong: Song?

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.authorizationStatus {
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
            .navigationTitle("Apple Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        viewModel.cleanup()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .task {
            viewModel.checkAuthorization()
            if viewModel.authorizationStatus == .notDetermined {
                await viewModel.requestAuthorization()
            }
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }

    // MARK: - Search Content

    private var searchContent: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search songs...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                        viewModel.songs = []
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
            .onChange(of: viewModel.searchText) {
                viewModel.searchTextChanged()
            }

            if viewModel.isSearching && viewModel.songs.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else if viewModel.songs.isEmpty && !viewModel.searchText.isEmpty {
                Spacer()
                ContentUnavailableView.search(text: viewModel.searchText)
                Spacer()
            } else if viewModel.songs.isEmpty {
                Spacer()
                Text("Search for a song")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(viewModel.songs, id: \.id) { song in
                    songRow(song)
                }
                .listStyle(.plain)
            }

            if let error = viewModel.errorMessage {
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
                    viewModel.togglePreview(for: song)
                } label: {
                    Image(systemName: viewModel.previewingSongId == song.id
                          ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(viewModel.previewingSongId == song.id
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

    // MARK: - Select Song

    private func selectSong(_ song: Song) {
        viewModel.stopPreview()

        let songId = song.id.rawValue
        let title = song.title
        let artist = song.artistName
        let artworkUrl = song.artwork?.url(width: 300, height: 300)?.absoluteString

        Task {
            let previewData = await viewModel.downloadPreviewData(for: song)
            viewModel.cleanup()
            onSongSelected(songId, title, artist, artworkUrl, previewData)
            dismiss()
        }
    }
}
