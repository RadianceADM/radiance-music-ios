import Foundation

/** Library's shelves beside Liked Songs and History (as the computer app's): the liked songs by album, artist or genre. */
public enum ShelfKind: String, CaseIterable, Sendable, Identifiable {
    case albums = "Albums", artists = "Artists", genres = "Genres"
    public var id: String { rawValue }
    public var title: String { rawValue }
}

/** One album, artist or genre, and its liked songs in Liked Songs' order. */
public struct Group: Hashable, Sendable, Identifiable {
    public let name: String
    public let songs: [Track]
    public var id: String { name }
}

/**
 * The liked songs grouped (android#38), as the computer app groups them (core/src/library.rs): every credited artist,
 * a song with no album under Singles, a song whose genres Deezer doesn't know under Other, one not looked up yet under
 * Finding the genre…; A to Z.
 */
public enum Shelf {
    public static let singles = "Singles"
    public static let other = "Other"
    public static let finding = "Finding the genre…"

    public static func groups(_ liked: [Track], _ kind: ShelfKind) -> [Group] {
        var map: [String: (String, [Track])] = [:]
        func put(_ name: String, _ t: Track) {
            let k = fold(name).lowercased()
            var g = map[k] ?? (name, [])
            if !g.1.contains(where: { $0.key == t.key }) { g.1.append(t) }
            map[k] = g
        }
        for t in liked {
            switch kind {
            case .albums: put(t.album.trimmingCharacters(in: .whitespaces).isEmpty ? singles : t.album, t)
            case .artists: t.artists().forEach { put($0, t) }
            case .genres:
                if let g = t.genres {
                    if g.isEmpty { put(other, t) } else { g.forEach { put($0, t) } }
                } else {
                    put(finding, t)
                }
            }
        }
        // a sorted map's order (Android's TreeMap): by the folded, lowercased name
        return map.keys.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }.map { Group(name: map[$0]!.0, songs: map[$0]!.1) }
    }
}
