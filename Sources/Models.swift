import Foundation

struct Track: Identifiable, Equatable {
    let id: String
    let name: String
    let artist: String
    let sourceURL: URL
    let imageURL: URL?
    let isrc: String?
    let spotifyURI: String?

    func with(isrc: String? = nil, spotifyURI: String? = nil) -> Track {
        Track(
            id: id,
            name: name,
            artist: artist,
            sourceURL: sourceURL,
            imageURL: imageURL,
            isrc: isrc ?? self.isrc,
            spotifyURI: spotifyURI ?? self.spotifyURI
        )
    }
}

struct SongPage {
    let tracks: [Track]
    let nextOffset: Int
    let mightHaveMore: Bool
}

struct PlayerSnapshot: Equatable {
    var isRunning: Bool
    var isPlaying: Bool
    var title: String
    var artist: String
    var artworkURL: URL?

    static let idle = PlayerSnapshot(
        isRunning: false,
        isPlaying: false,
        title: "",
        artist: "",
        artworkURL: nil
    )
}

enum StorageKeys {
    static let lastURI = "spotifybar.lastURI"
}
