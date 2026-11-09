import Foundation

/** Songs split on this iPhone: their parts kept in the app's own folder (parts/<song>/vocals.m4a…). */
public enum Splits {
    public static let names = ["drums", "bass", "other", "vocals", "music", "piano", "guitar"]
    static let types = ["m4a", "caf", "wav", "flac"]

    public static func dir(_ p: Paths, _ key: String) -> URL { p.parts.appendingPathComponent(Saver.safe(key), isDirectory: true) }

    /** The parts split here for [key]: name to file (only whole ones: a split writes each beside, then puts it in place). */
    public static func parts(_ p: Paths, _ key: String) -> [String: URL] {
        let d = dir(p, key)
        var out: [String: URL] = [:]
        for n in names {
            for ext in types {
                let f = d.appendingPathComponent("\(n).\(ext)")
                if FileManager.default.fileExists(atPath: f.path) { out[n] = f; break }
            }
        }
        return out
    }

    public static func forget(_ p: Paths, _ key: String) { try? FileManager.default.removeItem(at: dir(p, key)) }
}
