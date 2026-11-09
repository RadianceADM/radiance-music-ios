import Foundation

/**
 * Songs already saved in Documents/Radiance Music back into Liked Songs (Android's data/Found.kt): put there from the
 * Files app, or left by a copy of the app that was there before. Each file is matched to its song on YouTube Music
 * by its name ("Artist - Title", as Saver names it) and its length, so it gets its cover and lyrics again; it keeps
 * playing its own file. It runs by itself each time the app opens: a song already in Liked Songs (by its file or its
 * name) or one you unliked is left alone, and a file with no match is looked up again a day later.
 */
public enum Found {
    /** A saved song file: its name under Documents, its name without the extension, the extension, its length (0: unknown). */
    public struct File: Equatable, Sendable {
        public let uri: String
        public let name: String
        public let ext: String
        public let seconds: Int
        public init(uri: String, name: String, ext: String, seconds: Int) { self.uri = uri; self.name = name; self.ext = ext; self.seconds = seconds }
    }

    public static let songTypes: Set<String> = ["m4a", "flac", "mp3", "aac", "wav", "aiff", "aif", "caf", "opus", "ogg", "alac"]

    /** The song files in Documents/Radiance Music (not the split parts or anything else there). */
    public static func files(_ p: Paths) -> [(URL, File)] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: p.songs.path) else { return [] }
        return names.sorted().compactMap { n in
            let u = p.songs.appendingPathComponent(n)
            let ext = u.pathExtension.lowercased()
            guard songTypes.contains(ext), !n.hasPrefix("."), !n.hasSuffix(".part") else { return nil }
            let base = String(n.dropLast(ext.count + 1))
            // the computer's split parts ("Artist - Title.vocals.ogg") aren't songs of their own
            if ["drums", "bass", "other", "vocals", "music", "piano", "guitar"].contains(where: { base.hasSuffix(".\($0)") }) { return nil }
            return (u, File(uri: p.name(of: u), name: base, ext: ext, seconds: 0))
        }
    }

    /**
     * The saved song files that aren't in Liked Songs: not linked from a liked song (by its name under Documents, or a
     * file:// one from the computer's library by its file name), not named as a liked song is saved ("Artist - Title"),
     * and not unliked ([skip]).
     */
    public static func waiting(_ songs: [File], _ liked: [Track], _ skip: Set<String>) -> [File] {
        let links = Set(liked.compactMap(\.file))
        let fileNames = Set(links.filter { $0.hasPrefix("file://") || $0.contains("/") }.map { $0.split(separator: "/").last.map(String.init) ?? $0 })
        let names = Set(liked.map(Saver.name))
        return songs.filter { f in
            !links.contains(f.uri) && !skip.contains(f.uri) && !fileNames.contains("\(f.name).\(f.ext)") && !names.contains(f.name)
        }
    }

    /** "Artist - Title" (as Saver names a song) as its artist and title; no " - ": the title alone. */
    public static func split(_ name: String) -> (String, String) {
        guard let at = name.range(of: " - "), at.lowerBound > name.startIndex else { return ("", name.trimmingCharacters(in: .whitespaces)) }
        return (String(name[..<at.lowerBound]).trimmingCharacters(in: .whitespaces), String(name[at.upperBound...]).trimmingCharacters(in: .whitespaces))
    }

    /**
     * The search result that is [f]'s song: its name like the file's and its length within a few seconds; else one of
     * the same length whose name shares a word; else none (a wrong cover and lyrics are worse than none).
     */
    public static func pick(_ f: File, _ results: [Track]) -> Track? {
        let want = wordSet(f.name)
        func sameLength(_ t: Track, _ within: Int) -> Bool { f.seconds <= 0 || t.seconds <= 0 || abs(t.seconds - f.seconds) <= within }
        func named(_ t: Track) -> Bool {
            let (artist, title) = split(f.name)
            let a = norm(artist), ti = norm(title), rt = norm(t.title)
            let ra = norm(t.artist)
            return !ti.isEmpty && (rt == ti || rt.contains(ti) || ti.contains(rt)) && (a.isEmpty || ra.contains(a) || a.contains(ra))
        }
        return results.first { named($0) && sameLength($0, 5) }
            ?? results.first { sameLength($0, 3) && f.seconds > 0 && $0.seconds > 0 && !wordSet("\($0.artist) \($0.title)").isDisjoint(with: want) }
    }

    static func norm(_ s: String) -> String {
        var out = ""
        var gap = false
        for u in fold(s).lowercased().unicodeScalars {
            let c = u.properties.generalCategory
            let keep: Bool
            switch c {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber, .letterNumber, .otherNumber: keep = true
            default: keep = false
            }
            if keep { if gap && !out.isEmpty { out += " " }; gap = false; out.unicodeScalars.append(u) } else { gap = true }
        }
        return out
    }

    static func wordSet(_ s: String) -> Set<String> {
        Set(norm(s).split(separator: " ").map(String.init).filter { $0.count > 2 })
    }

    /**
     * The songs saved here that aren't in Liked Songs, matched and liked ([everything]: those that had no match lately
     * too). [length]: a file's length in seconds. How many came back of how many there were.
     */
    @MainActor
    public static func run(_ p: Paths, _ library: Library, everything: Bool = false, length: (URL) async -> Int,
                           say: (Int, Int) -> Void = { _, _ in }) async -> (Int, Int) {
        var songs: [File] = []
        var where_: [String: URL] = [:]
        for (u, f) in files(p) { songs.append(f); where_[f.uri] = u }
        let tried = Tried(p.support.appendingPathComponent("found.json"))
        let missing = waiting(songs, library.liked, library.unlikedFiles()).filter { everything || tried.due($0.name) }
        var back = 0
        for (i, f0) in missing.enumerated() {
            say(i, missing.count)
            var secs = 0
            if let u = where_[f0.uri] { secs = await length(u) }
            let f = File(uri: f0.uri, name: f0.name, ext: f0.ext, seconds: secs)
            let (artist, title) = split(f.name)
            guard let results = try? await YouTube.search([artist, title].filter { !$0.isEmpty }.joined(separator: " ")) else { continue } // offline: next time
            guard var t = pick(f, results) else { tried.missed(f.name); continue }
            t.file = f.uri
            if f.ext == "flac" { t.format = "FLAC" } else if f.ext == "m4a" { t.format = "AAC" }
            if library.isLiked(t.key) { library.update(t) } else { library.like(t) }
            try? await Saver.cover(p, t)
            _ = await Saver.lyrics(p, t)
            back += 1
        }
        say(missing.count, missing.count)
        return (back, missing.count)
    }

    /** Files that had no match: looked up again a day later, not each time the app opens. */
    final class Tried {
        let file: URL
        var missed: Set<String>
        var fresh: Bool
        init(_ file: URL) {
            self.file = file
            let o = (try? Data(contentsOf: file)).flatMap { JSON.parse($0) }
            missed = Set((o?["missed"]?.array ?? []).compactMap { $0.string })
            let at = o?["at"]?.double ?? 0
            fresh = Date().timeIntervalSince1970 - at < 24 * 3600
        }
        func due(_ name: String) -> Bool { !(fresh && missed.contains(name)) }
        func missed(_ name: String) {
            var at = Date().timeIntervalSince1970
            if !fresh { missed.removeAll(); fresh = true } else {
                at = ((try? Data(contentsOf: file)).flatMap { JSON.parse($0) }?["at"]?.double) ?? at
            }
            missed.insert(name)
            let o: JSON = ["missed": .array(missed.sorted().map { .string($0) }), "at": .number(at)]
            try? o.data().write(to: file, options: .atomic)
        }
    }
}
