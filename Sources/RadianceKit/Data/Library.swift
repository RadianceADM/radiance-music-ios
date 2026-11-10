import Foundation
import Observation

/**
 * What's yours on this iPhone (Android's data/Library.kt): Liked Songs (always A to Z), the songs played (newest
 * first) and where you left off. Kept as small JSON files, the same as Android's; the songs themselves are in
 * Documents/Radiance Music.
 */
@MainActor
@Observable
public final class Library {
    @ObservationIgnored let dir: URL

    public private(set) var liked: [Track]
    public private(set) var history: [Track]
    /**
     * Saved songs you unliked (their files, which stay in Documents/Radiance Music): the songs saved on the phone
     * come back by themselves (Found), but not these.
     */
    @ObservationIgnored private var unliked: Set<String>

    public init(dir: URL) {
        self.dir = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        liked = Library.sortedByTitle(Library.load(dir, "liked.json"))
        history = Library.load(dir, "history.json")
        let u = (try? Data(contentsOf: dir.appendingPathComponent("unliked.json"))).flatMap { JSON.parse($0)?.array } ?? []
        unliked = Set(u.compactMap { $0.string })
    }

    public func isLiked(_ key: String) -> Bool { liked.contains { $0.key == key } }

    public func unlikedFiles() -> Set<String> { unliked }

    public func like(_ t: Track) {
        if isLiked(t.key) { return }
        liked = Library.sortedByTitle(liked + [t])
        save("liked.json", liked)
        if let f = t.file, unliked.contains(f) { keepUnliked(unliked.subtracting([f])) }
    }

    public func unlike(_ t: Track) {
        let had = liked.first { $0.key == t.key }
        liked = liked.filter { $0.key != t.key }
        save("liked.json", liked)
        if let f = had?.file { keepUnliked(unliked.union([f])) }
    }

    private func keepUnliked(_ files: Set<String>) {
        unliked = files
        write("unliked.json", JSON.array(files.sorted().map { .string($0) }).data())
    }

    /**
     * A liked song again, now with its saved copy, or its genres and album (Genres): what one side found isn't lost to
     * the other, and a copy that came without a cover's address keeps the one it had (android#41: an import from the
     * computer blanked them).
     */
    public func update(_ t: Track) {
        guard isLiked(t.key) else { return }
        liked = liked.map { old in
            guard old.key == t.key else { return old }
            var n = t
            n.genres = t.genres ?? old.genres
            n.album = t.album.isEmpty ? old.album : t.album
            n.art = t.art.isEmpty ? old.art : t.art
            n.file = t.file ?? old.file
            return n
        }
        save("liked.json", liked)
    }

    /** The liked copy of a song when there is one (it has the saved file). */
    public func best(_ t: Track) -> Track { liked.first { $0.key == t.key } ?? t }

    public func played(_ t: Track) {
        if history.first?.key == t.key { return }
        history = Array(([t] + history).prefix(300))
        save("history.json", history)
    }

    /** The queue, the song playing and where in it: kept when the app closes. */
    public func saveSession(queue: [Track], index: Int, positionMs: Int64) {
        let o: JSON = ["queue": .array(queue.map(\.json)), "index": .number(Double(index)), "position": .number(Double(positionMs))]
        write("session.json", o.data())
    }

    public func session() -> (queue: [Track], index: Int, positionMs: Int64)? {
        guard let d = try? Data(contentsOf: dir.appendingPathComponent("session.json")), let o = JSON.parse(d) else { return nil }
        let q = (o["queue"]?.array ?? []).compactMap(Track.from(json:)).map(best)
        if q.isEmpty { return nil }
        return (q, o["index"]?.int ?? 0, o["position"]?.int64 ?? 0)
    }

    static func load(_ dir: URL, _ name: String) -> [Track] {
        guard let d = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return [] }
        return Track.list(d)
    }

    private func save(_ name: String, _ tracks: [Track]) {
        write(name, Track.data(tracks))
    }

    /** Written whole, then put in place (a stop halfway never leaves half a list). */
    private func write(_ name: String, _ data: Data) {
        try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
    }

    // MARK: - A to Z

    /** A to Z as filed: accents, case and leading quotes or symbols aside; letters first. */
    public static func sortedByTitle(_ tracks: [Track]) -> [Track] {
        tracks.enumerated().sorted { a, b in
            let ka = fileKey(a.element.title), kb = fileKey(b.element.title)
            if ka.0 != kb.0 { return ka.0 < kb.0 }
            if ka.1 != kb.1 { return ka.1.utf16.lexicographicallyPrecedes(kb.1.utf16) } // Kotlin compares UTF-16 units
            return a.offset < b.offset // the same title: as they were (a stable sort, as Kotlin's)
        }.map(\.element)
    }

    /** The A to Z rail's letters, in the order songs are filed (as the computer's). */
    public static let rail: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ#")

    /** A song's letter on the rail: its title's first letter as filed, or # for anything else. */
    public static func letter(_ t: Track) -> Character {
        guard let c = fileKey(t.title).1.unicodeScalars.first, ("a"..."z").contains(c) else { return "#" }
        return Character(String(c).uppercased())
    }

    /** Where each letter's songs start in a list filed A to Z (letters with no songs are left out). */
    public static func firsts(_ tracks: [Track]) -> [Character: Int] {
        var m: [Character: Int] = [:]
        for (i, t) in tracks.enumerated() where m[letter(t)] == nil { m[letter(t)] = i }
        return m
    }

    /** The song to jump to for the rail's letter at `i`: that letter's first song, or the next letter's with songs. */
    public static func jump(_ firsts: [Character: Int], _ i: Int) -> Int? {
        guard rail.indices.contains(i) else { return nil }
        return rail[i...].lazy.compactMap { firsts[$0] }.first
    }

    public static func fileKey(_ title: String) -> (Int, String) {
        let low = fold(title).lowercased()
        let key = String(String.UnicodeScalarView(low.unicodeScalars.drop { !$0.isLetterOrDigit }))
        let first = key.unicodeScalars.first
        let letter = first.map { ("a"..."z").contains($0) } ?? false
        return (letter ? 0 : 1, key)
    }
}
