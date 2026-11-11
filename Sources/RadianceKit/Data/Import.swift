import Foundation

/**
 * Your library from the computer (Radiance Music for Linux), put on the iPhone (Android's data/Import.kt): the songs
 * in Documents/Radiance Music, and in Documents/Library a list of them (library.json) with their parts (drums, bass,
 * other, vocals), lyrics and covers. Read once (again when it's copied anew): each song joins Liked Songs, playing its
 * own file, with its lyrics and cover.
 */
public enum Import {
    static func list(_ p: Paths) -> URL { p.imports.appendingPathComponent("library.json") }
    static func done(_ p: Paths) -> URL { p.support.appendingPathComponent("imported") }

    static func stamp(_ u: URL) -> String? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: u.path), let d = a[.modificationDate] as? Date else { return nil }
        return String(Int64(d.timeIntervalSince1970 * 1000))
    }

    /** A library is waiting to be read (new, or copied again since). */
    public static func waiting(_ p: Paths) -> Bool {
        guard let s = stamp(list(p)) else { return false }
        let d = (try? String(contentsOf: done(p), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return d != s
    }

    /** The song's parts copied from the computer: name ("drums", "bass", "other", "vocals", "music") to its file. */
    public static func parts(_ p: Paths, _ key: String) -> [String: URL] {
        guard let d = try? Data(contentsOf: list(p)), let songs = JSON.parse(d)?["songs"]?.array else { return [:] }
        guard let e = songs.first(where: { $0["key"]?.string == key }), let parts = e["parts"]?.object else { return [:] }
        var out: [String: URL] = [:]
        for (k, v) in parts {
            guard let n = v.string else { continue }
            let f = p.imports.appendingPathComponent(n)
            if Splits.whole(f) { out[k] = f }
        }
        return out
    }

    /** Everything the computer sent along for [key] (its cover, lyrics and parts in Documents/Library), that's here. */
    public static func files(_ p: Paths, _ key: String) -> [URL] {
        guard let d = try? Data(contentsOf: list(p)), let songs = JSON.parse(d)?["songs"]?.array,
              let e = songs.first(where: { $0["key"]?.string == key }) else { return [] }
        var names = ["cover", "lrc", "lyricsfile"].compactMap { e[$0]?.string }
        names += (e["parts"]?.object ?? [:]).values.compactMap { $0.string }
        return names.filter { !$0.isEmpty }.map { p.imports.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /** Reads it into Liked Songs. How many songs came in. */
    @MainActor
    public static func run(_ p: Paths, _ library: Library) throws -> Int {
        let l = list(p)
        let d = try Data(contentsOf: l)
        guard let songs = JSON.parse(d)?["songs"]?.array else { throw Plain("That library.json isn't one Radiance Music made.") }
        let fm = FileManager.default
        var n = 0
        for e in songs {
            guard let base = e["track"].flatMap(Track.from(json:)) else { continue }
            let name = e["song"]?.string ?? ""
            guard !name.isEmpty else { continue }
            let song = p.songs.appendingPathComponent(name)
            guard fm.fileExists(atPath: song.path) else { continue }
            // its music video (if the computer copied one) stays out: phones have none
            var t = base
            t.file = p.name(of: song)
            // its cover and its lyrics where the app keeps them
            if let c = e["cover"]?.string, !c.isEmpty {
                let src = p.imports.appendingPathComponent(c)
                if fm.fileExists(atPath: src.path) {
                    let dst = Saver.coverFile(p, t)
                    try? fm.removeItem(at: dst)
                    try? fm.copyItem(at: src, to: dst)
                    Saver.coverKept(t.key)
                }
            }
            var lyrics: Lyrics?
            if let y = e["lyricsfile"]?.string, !y.isEmpty, let text = try? String(contentsOf: p.imports.appendingPathComponent(y), encoding: .utf8) {
                lyrics = lyricsfile(text)
            }
            if lyrics == nil, let l = e["lrc"]?.string, !l.isEmpty, let text = try? String(contentsOf: p.imports.appendingPathComponent(l), encoding: .utf8) {
                lyrics = LyricsFinder.fromFile(text)
            }
            if let text = lyrics?.file() { try? text.write(to: Saver.lyricsFile(p, t), atomically: true, encoding: .utf8) }
            if library.isLiked(t.key) { library.update(t) } else { library.like(t) }
            n += 1
        }
        if let s = stamp(l) { try? s.write(to: done(p), atomically: true, encoding: .utf8) }
        return n
    }

    /**
     * A Lyricsfile (the desktop app's YAML: lines with their text, start_ms and end_ms, and maybe each word's) as
     * timed lines.
     */
    public static func lyricsfile(_ yaml: String) -> Lyrics? {
        var lines: [Line] = []
        var text: String?
        var start: Int64 = -1
        var end: Int64 = -1
        func flush() {
            guard let t = text else { return }
            if start >= 0 {
                let e = end > start ? end : start + 3000
                lines.append(Line(Double(start) / 1000, Double(e) / 1000, t.trimmingCharacters(in: .whitespaces).isEmpty ? "♪" : t))
            }
            text = nil; start = -1; end = -1
        }
        var inLines = false
        for raw in yaml.components(separatedBy: "\n").map({ $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }) {
            if raw.hasPrefix("lines:") { inLines = true; continue }
            if !inLines { continue }
            if !raw.isEmpty && !raw.hasPrefix(" ") { break } // the next top-level key
            if raw.hasPrefix("  - text: ") { flush(); text = unquote(String(raw.dropFirst("  - text: ".count))) }
            else if raw.hasPrefix("    start_ms: ") { start = Int64(raw.split(separator: ":", maxSplits: 1).last!.trimmingCharacters(in: .whitespaces)) ?? -1 }
            else if raw.hasPrefix("    end_ms: ") { end = Int64(raw.split(separator: ":", maxSplits: 1).last!.trimmingCharacters(in: .whitespaces)) ?? -1 }
        }
        flush()
        if lines.isEmpty { return nil }
        return .timed(lines.enumerated().sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }.map(\.element))
    }

    /** "…" (JSON-style) or '…' (YAML) or bare. */
    static func unquote(_ v: String) -> String {
        let s = v.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("\"") {
            if let a = JSON.parse("[\(s)]")?[0]?.string { return a }
            return s.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        if s.hasPrefix("'") && s.hasSuffix("'") && s.count >= 2 {
            return String(s.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return s
    }
}
