import Foundation

/**
 * Like it, save it (Android's data/Saver.kt): a liked song goes into Documents/Radiance Music (AAC .m4a from YouTube,
 * FLAC from the Internet Archive), its cover and its lyrics into the app's own folders. Never its music video.
 */
public enum Saver {
    /** The name a saved song's file gets ("Artist - Title"; Found reads it back). */
    public static func name(_ t: Track) -> String {
        let bad = Set("/\\:*?\"<>|")
        let s = String("\(t.artist) - \(t.title)".map { bad.contains($0) || $0.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) ? "_" : $0 })
        return String(s.trimmingCharacters(in: .whitespaces).prefix(150))
    }

    public static func safe(_ key: String) -> String {
        String(key.unicodeScalars.map { $0.isLetterOrDigit ? Character($0) : "_" })
    }

    public static func coverFile(_ p: Paths, _ t: Track) -> URL { p.covers.appendingPathComponent("\(safe(t.key)).jpg") }
    public static func lyricsFile(_ p: Paths, _ t: Track) -> URL { p.lyrics.appendingPathComponent("\(safe(t.key)).lrc") }

    /** Whether each song has a cover kept here, looked at once (the lists ask often); forgotten when one is kept anew. */
    private static let kept = Kept()

    /**
     * The song's cover kept on this iPhone (nil: none kept): what the screens show first (android#41: songs that came
     * without a cover's address showed none, though their cover was here).
     */
    public static func keptCover(_ p: Paths, _ t: Track) -> URL? {
        let f = coverFile(p, t)
        return kept.has(t.key) { FileManager.default.fileExists(atPath: f.path) } ? f : nil
    }

    /** A cover was just kept (or replaced) for [key]: looked at again next time. */
    public static func coverKept(_ key: String) { kept.forget(key) }

    /**
     * Saves what the song still lacks: the song, then its cover and lyrics. The song with its file. [progress]: how
     * much of the song is here, 0-1. [songSaved]: the song itself is here (before its cover and lyrics).
     */
    public static func save(_ p: Paths, _ t: Track, progress: @escaping @Sendable (Double) -> Void = { _ in },
                            songSaved: @escaping @Sendable (Track) async -> Void = { _ in }) async throws -> Track {
        var out = t
        if out.file == nil || p.file(out.file).map({ !FileManager.default.fileExists(atPath: $0.path) }) == true {
            let f = try await saveSong(p, t, progress: progress)
            out.file = p.name(of: f)
            if t.source == .youtube { out.format = "AAC" }
            await songSaved(out)
        }
        try? await cover(p, out)
        _ = await lyrics(p, out)
        return out
    }

    /** A new file's place in Documents/Radiance Music: [base].[ext], or "[base] (2).[ext]"… when that's taken. */
    public static func place(_ p: Paths, _ base: String, _ ext: String) -> URL {
        var n = 1
        while true {
            let f = p.songs.appendingPathComponent(n == 1 ? "\(base).\(ext)" : "\(base) (\(n)).\(ext)")
            if !FileManager.default.fileExists(atPath: f.path) { return f }
            n += 1
        }
    }

    static func saveSong(_ p: Paths, _ t: Track, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        switch t.source {
        case .youtube:
            // the AAC sound (the iPhone plays it, Files and other apps open it): a .m4a as YouTube has it
            let s = try await YouTube.audio(t.id)
            let f = place(p, name(t), "m4a")
            try await Http.download(s.url, to: f, size: s.size, headers: s.headers, progress: progress)
            return f
        case .archive:
            let f = place(p, name(t), "flac")
            try await Http.download(t.id, to: f, progress: progress)
            return f
        case .server:
            // its file as it is there (FLAC, AAC or Opus)
            let last = t.id.split(separator: "/").last.map(String.init) ?? ""
            let bare = last.split(separator: "?").first.map(String.init) ?? last
            let dot = bare.lastIndex(of: ".")
            let ext = dot.map { String(bare[bare.index(after: $0)...]).lowercased().lettersAndDigits.prefix(5) }.map(String.init) ?? "m4a"
            let f = place(p, name(t), ext.isEmpty ? "m4a" : ext)
            try await Http.download(t.id, to: f, progress: progress)
            return f
        }
    }

    /**
     * The song's cover kept here, big ([Art.big]), if it isn't yet. One kept small before is fetched again big; if
     * that fails, the small one stays.
     */
    public static func cover(_ p: Paths, _ t: Track) async throws {
        let f = coverFile(p, t)
        if t.art.isEmpty { return }
        let again = FileManager.default.fileExists(atPath: f.path)
        if again && !(Art.grows(t.art) && small(f)) { return }
        do {
            try await Http.download(Art.sized(t.art, Art.big), to: f)
            coverKept(t.key)
        } catch {
            if !again { throw error }
        }
    }

    /** A kept cover too small for Now Playing or a story (under 600 px across). */
    public static func small(_ f: URL) -> Bool {
        guard let d = try? Data(contentsOf: f), let (w, _) = ImageSize.of(d) else { return false }
        return w > 0 && w < 600
    }

    /** The song's lyrics: kept ones first, else looked up (and kept, for a saved song). */
    public static func lyrics(_ p: Paths, _ t: Track) async -> Lyrics {
        let f = lyricsFile(p, t)
        if let text = try? String(contentsOf: f, encoding: .utf8) { return LyricsFinder.fromFile(text) }
        let found = await LyricsFinder.find(t)
        if t.file != nil, let text = found.file() { try? text.write(to: f, atomically: true, encoding: .utf8) }
        return found
    }

    /** The song's files gone (it was unliked and you chose to delete it). */
    public static func delete(_ p: Paths, _ t: Track) {
        let fm = FileManager.default
        if let f = p.file(t.file) { try? fm.removeItem(at: f) }
        try? fm.removeItem(at: coverFile(p, t))
        try? fm.removeItem(at: lyricsFile(p, t))
        coverKept(t.key)
    }
}

/** A thread-safe "is it there?" memo. */
final class Kept: @unchecked Sendable {
    private var known: [String: Bool] = [:]
    private let lock = NSLock()

    func has(_ key: String, _ look: () -> Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let k = known[key] { return k }
        let v = look()
        known[key] = v
        return v
    }

    func forget(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        known[key] = nil
    }
}

/** A picture's size from its first bytes (JPEG or PNG), without opening it. */
public enum ImageSize {
    public static func of(_ d: Data) -> (Int, Int)? {
        let b = [UInt8](d.prefix(256 * 1024))
        if b.count > 24, b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 {
            let w = Int(b[16]) << 24 | Int(b[17]) << 16 | Int(b[18]) << 8 | Int(b[19])
            let h = Int(b[20]) << 24 | Int(b[21]) << 16 | Int(b[22]) << 8 | Int(b[23])
            return (w, h)
        }
        guard b.count > 4, b[0] == 0xFF, b[1] == 0xD8 else { return nil }
        var i = 2
        while i + 9 < b.count {
            guard b[i] == 0xFF else { i += 1; continue }
            let marker = b[i + 1]
            if marker == 0xD8 || marker == 0x01 || (0xD0...0xD7).contains(marker) { i += 2; continue }
            let len = Int(b[i + 2]) << 8 | Int(b[i + 3])
            // a frame's start: its height and width
            if (0xC0...0xCF).contains(marker) && marker != 0xC4 && marker != 0xC8 && marker != 0xCC {
                let h = Int(b[i + 5]) << 8 | Int(b[i + 6])
                let w = Int(b[i + 7]) << 8 | Int(b[i + 8])
                return (w, h)
            }
            i += 2 + len
        }
        return nil
    }
}
