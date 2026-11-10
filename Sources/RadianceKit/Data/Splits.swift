import Foundation

/** Songs split on this iPhone: their parts kept in the app's own folder (parts/<song>/vocals.m4a…). */
public enum Splits {
    public static let names = ["drums", "bass", "other", "vocals", "music", "piano", "guitar"]
    static let types = ["m4a", "caf", "wav", "flac"]

    /**
     * A part smaller than this has no sound in it (a header only: 2026-11-10, a song the split couldn't read left two
     * 557-byte parts, and the song went quiet when the Mixer played them). Such a part is as good as none.
     */
    public static let leastBytes: Int64 = 8 * 1024

    /** [f] is there with sound in it. */
    public static func whole(_ f: URL) -> Bool {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: f.path))?[.size] as? NSNumber else { return false }
        return size.int64Value >= leastBytes
    }

    public static func dir(_ p: Paths, _ key: String) -> URL { p.parts.appendingPathComponent(Saver.safe(key), isDirectory: true) }

    /** The parts split here for [key]: name to file (only whole ones: a split writes each beside, then puts it in place). */
    public static func parts(_ p: Paths, _ key: String) -> [String: URL] {
        let d = dir(p, key)
        var out: [String: URL] = [:]
        for n in names {
            for ext in types {
                let f = d.appendingPathComponent("\(n).\(ext)")
                if whole(f) { out[n] = f; break }
            }
        }
        return out
    }

    public static func forget(_ p: Paths, _ key: String) { try? FileManager.default.removeItem(at: dir(p, key)) }
}
