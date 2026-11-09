import Foundation

/**
 * Where the app keeps things on the iPhone. The lists (liked, history…), covers and lyrics are in Application
 * Support (yours, not shown in Files); the songs themselves in Documents/Radiance Music, which the Files app shows
 * (On My iPhone → Radiance Music), so they can be seen, copied off or added to; a computer's library goes into
 * Documents/Library.
 */
public struct Paths: Sendable {
    /** The app's own lists, covers and lyrics. */
    public let support: URL
    /** What Files shows. */
    public let documents: URL

    public init(support: URL, documents: URL) {
        self.support = support
        self.documents = documents
        for d in [support, songs, covers, lyrics, imports] { try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
    }

    /** The app's folders on this iPhone. */
    public static func app() -> Paths {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Radiance Music", isDirectory: true)
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return Paths(support: support, documents: documents)
    }

    /** The folder of saved songs, as Track.file names them ("Radiance Music/…"). */
    public static let songsFolder = "Radiance Music"
    public var songs: URL { documents.appendingPathComponent(Paths.songsFolder, isDirectory: true) }
    public var covers: URL { support.appendingPathComponent("covers", isDirectory: true) }
    public var lyrics: URL { support.appendingPathComponent("lyrics", isDirectory: true) }
    /** A computer's library put on the iPhone (library.json, its parts, covers and lyrics). */
    public var imports: URL { documents.appendingPathComponent("Library", isDirectory: true) }
    public var parts: URL { support.appendingPathComponent("parts", isDirectory: true) }

    /** A song's saved file, from its Track.file (a name under Documents, or a file:// address). */
    public func file(_ name: String?) -> URL? {
        guard let name, !name.isEmpty else { return nil }
        if name.hasPrefix("file://") { return URL(string: name) }
        if name.hasPrefix("/") { return URL(fileURLWithPath: name) }
        return documents.appendingPathComponent(name)
    }

    /** [url]'s name under Documents, as a Track.file keeps it (it stays right when the app's folder moves). */
    public func name(of url: URL) -> String {
        let docs = documents.standardizedFileURL.path
        let p = url.standardizedFileURL.path
        if p.hasPrefix(docs + "/") { return String(p.dropFirst(docs.count + 1)) }
        return url.absoluteString
    }
}
