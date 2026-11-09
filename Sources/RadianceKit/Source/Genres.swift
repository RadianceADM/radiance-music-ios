import Foundation

/**
 * A song's genres, from Deezer's free public catalogue (no account), as the computer app finds them
 * (engine/src/genre.rs) and Android (source/Genres.kt): the genres of the album the song is on. The same answer names
 * the album, for a song that came without one: Albums groups by it.
 */
public enum Genres {
    /** What Deezer said: the genres (empty: it doesn't know the song) and the album's title when it's surely this song's. */
    public struct Found: Equatable, Sendable {
        public let genres: [String]
        public let album: String?
    }

    /** Looks [t] up. Nil: Deezer couldn't be asked (offline): ask again later. */
    public static func lookup(_ t: Track) async -> Found? {
        let artist = t.artists().first ?? ""
        guard let search = await Http.json("https://api.deezer.com/search", ["q": "\(artist) \(t.title)", "limit": "5"]) else { return nil }
        guard let (albumId, title) = pick(search, artist) else { return Found(genres: [], album: nil) }
        guard let album = await Http.json("https://api.deezer.com/album/\(albumId)") else { return nil }
        return Found(genres: genresOf(album), album: title)
    }

    /**
     * The album of the hit by the same artist, with its title; else the first hit's album with no title (its genres
     * are likely right, its album not surely this song's). Nil: no hits.
     */
    static func pick(_ search: JSON, _ artist: String) -> (Int64, String?)? {
        guard let all = search["data"]?.array else { return nil }
        let same = all.first { plain($0["artist"]?["name"]?.string ?? "") == plain(artist) }
        guard let hit = same ?? all.first, let album = hit["album"], let id = album["id"]?.int64, id > 0 else { return nil }
        let title = album["title"]?.string ?? ""
        return (id, same != nil && !title.trimmingCharacters(in: .whitespaces).isEmpty ? title : nil)
    }

    static func genresOf(_ album: JSON) -> [String] {
        (album["genres"]?["data"]?.array ?? []).compactMap { $0["name"]?.string }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}
