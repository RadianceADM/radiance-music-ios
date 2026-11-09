import Foundation

/**
 * Internet Archive: free, lossless (FLAC) recordings, searched first (Android's source/Archive.kt). The search finds
 * items with FLAC files; each item's file list gives the songs, kept only when every word searched for is in the song's
 * title, artist or album. The iPhone plays FLAC itself.
 */
public enum Archive {
    static let items = 8
    static let most = 10

    public static func search(_ query: String) async throws -> [Track] {
        let want = words(query.lowercased())
        if want.isEmpty { return [] }
        let escaped = String(String.UnicodeScalarView(query.unicodeScalars.filter { $0.isLetterOrDigit || $0.isWhitespaceLike || $0 == "'" }))
        let q = "(\(escaped)) AND mediatype:(audio) AND format:(\"Flac\" OR \"24bit Flac\")"
        let found = try await Http.jsonOrThrow("https://archive.org/advancedsearch.php",
            ["q": q, "fl[]": "identifier", "rows": "\(items)", "sort[]": "downloads desc", "output": "json"])
        let ids = (found["response"]?["docs"]?.array ?? []).compactMap { $0["identifier"]?.string }.filter { !$0.isEmpty }
        // the items' file lists, all at once
        let metas: [(Int, String, JSON)] = await withTaskGroup(of: (Int, String, JSON?).self) { g in
            for (i, id) in ids.enumerated() {
                g.addTask { (i, id, await Http.json("https://archive.org/metadata/\(id)")) }
            }
            var all: [(Int, String, JSON)] = []
            for await (i, id, m) in g { if let m { all.append((i, id, m)) } }
            return all.sorted { $0.0 < $1.0 }
        }
        var out: [Track] = []
        for (_, id, meta) in metas {
            for t in tracks(id, meta) {
                let hay = "\(t.title) \(t.artist) \(t.album)".lowercased()
                if want.allSatisfy({ hay.contains($0) }) && !out.contains(where: { $0.id == t.id }) { out.append(t) }
            }
        }
        // the song's own title matching first, then hi-res
        let phrase = query.lowercased()
        let ranked = out.enumerated().sorted { a, b in
            let ka = (a.element.title.lowercased().contains(phrase) ? 0 : 1, a.element.format == "24-bit FLAC" ? 0 : 1, a.offset)
            let kb = (b.element.title.lowercased().contains(phrase) ? 0 : 1, b.element.format == "24-bit FLAC" ? 0 : 1, b.offset)
            return ka < kb
        }
        return ranked.prefix(most).map(\.element)
    }

    static func text(_ v: JSON?) -> String {
        switch v {
        case .string(let s)?: return s
        case .array(let a)?: return a.compactMap { if case .string(let s) = $0 { return s }; return nil }.joined(separator: ", ")
        default: return ""
        }
    }

    static func tracks(_ id: String, _ meta: JSON) -> [Track] {
        let m = meta["metadata"]
        let itemTitle = text(m?["title"])
        let itemArtist = text(m?["creator"])
        return (meta["files"]?.array ?? []).compactMap { f -> Track? in
            let format: String
            switch f["format"]?.string {
            case "Flac": format = "FLAC"
            case "24bit Flac": format = "24-bit FLAC"
            default: return nil
            }
            guard let name = f["name"]?.string, !name.isEmpty else { return nil }
            var title = text(f["title"])
            if title.isEmpty {
                var last = name.split(separator: "/").last.map(String.init) ?? name
                if last.hasSuffix(".flac") { last.removeLast(5) }
                title = last.replacingOccurrences(of: "_", with: " ")
            }
            let artist = [text(f["artist"]), text(f["creator"]), itemArtist].first { !$0.isEmpty } ?? ""
            let album = text(f["album"]).isEmpty ? itemTitle : text(f["album"])
            return Track(source: .archive, id: "https://archive.org/download/\(id)/\(encodePath(name))", title: title, artist: artist,
                         album: album, seconds: parseClock(f["length"]?.string ?? ""), art: "https://archive.org/services/img/\(id)", format: format)
        }
    }

    static func encodePath(_ path: String) -> String {
        var out = ""
        for b in path.utf8 {
            switch b {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "-"), UInt8(ascii: "_"), UInt8(ascii: "."), UInt8(ascii: "~"), UInt8(ascii: "/"):
                out.append(Character(Unicode.Scalar(b)))
            default:
                out += String(format: "%%%02X", b)
            }
        }
        return out
    }
}
