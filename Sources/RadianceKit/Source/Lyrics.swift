import Foundation

/** A line of lyrics and when it's sung (seconds). */
public struct Line: Hashable, Sendable {
    public var start: Double
    public var end: Double
    public var text: String
    public init(_ start: Double, _ end: Double, _ text: String) { self.start = start; self.end = end; self.text = text }
}

public enum Lyrics: Equatable, Sendable {
    case timed([Line])
    case plain(String)
    case none

    /** As a file: LRC when timed, else the text. */
    public func file() -> String? {
        switch self {
        case .timed(let lines):
            return lines.map { String(format: "[%02d:%05.2f]", Int($0.start / 60), $0.start.truncatingRemainder(dividingBy: 60)) + $0.text }.joined(separator: "\n")
        case .plain(let text): return text
        case .none: return nil
        }
    }
}

/**
 * Lyrics from LRCLIB (free, open, no account), else the text YouTube Music shows (Android's source/Lyrics.kt). As the
 * desktop app: an LRCLIB entry must be filed under the song's artist, and lyrics whose own "[ar: …]" tag names another
 * artist are turned away (someone once filed Young Greatness's "Moolah" under SCOOP DOGG's).
 */
public enum LyricsFinder {
    public static func find(_ t: Track) async -> Lyrics {
        if let l = await lrclib(t) { return l }
        if t.source == .youtube, let text = await YouTube.lyrics(t.id) { return .plain(text) }
        return .none
    }

    /** Lyrics kept as a file (LRC or text). */
    public static func fromFile(_ text: String) -> Lyrics {
        let lines = parseLrc(text)
        if !lines.isEmpty { return .timed(lines) }
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .plain(text) }
        return .none
    }

    static func byThem(_ t: Track, _ v: JSON) -> Bool {
        let names = splitCredit(t.artist).map(plain).filter { $0.count >= 2 }
        func ours(_ name: String) -> Bool {
            let theirs = plain(name)
            return !theirs.isEmpty && names.contains { theirs.contains($0) || $0.contains(theirs) }
        }
        var tag: String?
        for k in ["syncedLyrics", "plainLyrics"] {
            guard let s = v[k]?.string, !s.isEmpty else { continue }
            if let r = s.range(of: #"\[ar:\s*([^\]]+)\]"#, options: .regularExpression) {
                let inside = s[r].dropFirst(4).dropLast()
                tag = inside.trimmingCharacters(in: .whitespaces)
                break
            }
        }
        return ours(v["artistName"]?.string ?? "") && (tag == nil || ours(tag!))
    }

    static func lrclib(_ t: Track) async -> Lyrics? {
        var q = ["track_name": t.title, "artist_name": t.artist]
        if !t.album.isEmpty { q["album_name"] = t.album }
        if t.seconds > 0 { q["duration"] = "\(t.seconds)" }
        if let v = await Http.json("https://lrclib.net/api/get", q), byThem(t, v), let l = from(v) { return l }
        // not that exact recording: the best match by title and artist
        guard let list = await Http.json("https://lrclib.net/api/search", ["track_name": t.title, "artist_name": t.artist])?.array else { return nil }
        let close = list.filter { byThem(t, $0) && (t.seconds == 0 || abs(($0["duration"]?.double ?? -99) - Double(t.seconds)) < 8) }
        let synced = close.first { !($0["syncedLyrics"]?.isNull ?? true) && !($0["syncedLyrics"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return (synced ?? close.first).flatMap(from)
    }

    static func from(_ v: JSON) -> Lyrics? {
        if let s = v["syncedLyrics"]?.string {
            let lines = parseLrc(s)
            if !lines.isEmpty { return .timed(lines) }
        }
        if let p = v["plainLyrics"]?.string, !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .plain(p) }
        return nil
    }

    /** "[01:02.50]words" lines; each ends where the next starts. Tags like "[ar: …]" are skipped. */
    public static func parseLrc(_ text: String) -> [Line] {
        let stamp = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:[.:]\d+)?)\]"#)
        var found: [(Double, String)] = []
        for raw in text.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let stamps = stamp.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = stamps.last else { continue }
            let words = ns.substring(from: last.range.location + last.range.length).trimmingCharacters(in: .whitespaces)
            for m in stamps {
                let min = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let sec = Double(ns.substring(with: m.range(at: 2)).replacingOccurrences(of: ":", with: ".")) ?? 0
                found.append((min * 60 + sec, words))
            }
        }
        let sorted = found.enumerated().sorted { ($0.element.0, $0.offset) < ($1.element.0, $1.offset) }.map(\.element)
        return sorted.enumerated().map { i, f in
            let end = i + 1 < sorted.count ? sorted[i + 1].0 : f.0 + 5
            return Line(f.0, max(end, f.0 + 0.3), f.1.isEmpty ? "♪" : f.1)
        }
    }
}
