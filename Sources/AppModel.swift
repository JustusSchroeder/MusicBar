import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var query: String = ""
    @Published var results: [Track] = []
    @Published var player = PlayerSnapshot.idle
    @Published var status: String = ""
    @Published var isSearching = false
    @Published var canLoadMore = false
    @Published var listTitle: String = ""

    private var lastSearch = ""
    private var catalogOffset = 0
    private var searchGeneration = 0
    private var playGeneration = 0
    private var playTask: Task<Void, Never>?
    private var pollTimer: Timer?

    private init() {}

    func start() {
        MediaKeys.shared.start()
        SpotifyPlayer.watchSystemEvents()
        Task {
            await refreshFromSpotify()
            await loadFeatured()
        }
    }

    func playerMenuAppeared() {
        Task { await refreshFromSpotify() }
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshFromSpotify()
            }
        }
        if results.isEmpty, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Task { await loadFeatured() }
        }
    }

    func playerMenuDisappeared() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func refreshPlayer() {
        Task { await refreshFromSpotify() }
    }

    func togglePlay() {
        Task {
            if player.isPlaying {
                await SpotifyPlayer.pause()
            } else {
                await SpotifyPlayer.play()
            }
            await refreshFromSpotify()
        }
    }

    func startFromHeadset() async {
        await SpotifyPlayer.play()
        await refreshFromSpotify()
    }

    private func refreshFromSpotify() async {
        guard SpotifyPlayer.isRunning else {
            player.isRunning = false
            player.isPlaying = false
            player.artworkURL = nil
            return
        }
        guard let snap = await SpotifyPlayer.snapshot() else { return }
        if !snap.title.isEmpty {
            player = snap
            return
        }
        player.isRunning = true
        player.isPlaying = snap.isPlaying
        if snap.isPlaying {
            player.title = "Advertisement"
            player.artist = ""
            player.artworkURL = nil
        }
    }

    func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            Task { await loadFeatured() }
            return
        }
        isSearching = true
        status = ""
        lastSearch = text
        catalogOffset = 0
        searchGeneration += 1
        let generation = searchGeneration
        Task {
            do {
                let page = try await CatalogSearch.songs(matching: text, offset: 0)
                guard generation == searchGeneration else { return }
                results = page.tracks
                catalogOffset = page.nextOffset
                canLoadMore = page.mightHaveMore
                listTitle = ""
                status = page.tracks.isEmpty ? "No songs found." : ""
            } catch {
                guard generation == searchGeneration else { return }
                if results.isEmpty { status = error.localizedDescription }
            }
            if generation == searchGeneration {
                isSearching = false
            }
        }
    }

    func loadMore() {
        let text = lastSearch
        guard !text.isEmpty, canLoadMore, !isSearching else { return }
        isSearching = true
        let generation = searchGeneration
        Task {
            do {
                let page = try await CatalogSearch.songs(matching: text, offset: catalogOffset)
                guard generation == searchGeneration else { return }
                catalogOffset = page.nextOffset
                let existing = Set(results.map(\.id))
                let fresh = page.tracks.filter { !existing.contains($0.id) }
                results.append(contentsOf: fresh)
                canLoadMore = page.mightHaveMore
                status = fresh.isEmpty ? "No more results." : ""
            } catch {
                guard generation == searchGeneration else { return }
                canLoadMore = true
            }
            if generation == searchGeneration {
                isSearching = false
            }
        }
    }

    func playTrack(_ track: Track) {
        playTask?.cancel()
        playGeneration += 1
        let generation = playGeneration
        status = "Starting…"
        player = PlayerSnapshot(
            isRunning: true,
            isPlaying: true,
            title: track.name,
            artist: track.artist,
            artworkURL: track.imageURL
        )
        playTask = Task {
            let uri: String?
            if let ready = track.spotifyURI {
                uri = ready
            } else {
                uri = await CatalogSearch.spotifyURI(for: track)
            }
            guard generation == playGeneration else { return }
            guard let uri else {
                status = "Couldn’t play that on Spotify."
                await refreshFromSpotify()
                return
            }
            if let art = await CatalogSearch.artworkURL(for: uri) {
                guard generation == playGeneration else { return }
                player.artworkURL = art
            }
            await SpotifyPlayer.playURI(uri)
            guard generation == playGeneration else { return }
            status = ""
            await refreshFromSpotify()
        }
    }

    private func loadFeatured() async {
        searchGeneration += 1
        let generation = searchGeneration
        isSearching = true
        status = ""
        let tracks = await CatalogSearch.featured()
        guard generation == searchGeneration else { return }
        results = tracks
        canLoadMore = false
        lastSearch = ""
        listTitle = tracks.isEmpty ? "" : "Popular"
        isSearching = false
    }
}
