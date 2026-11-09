import Foundation

/** Where a song comes from: the Internet Archive, YouTube Music, or a Radiance Music Server you joined. */
public enum Source: String, Sendable, Codable {
    case archive, youtube, server
}

/**
 * A song, wherever it comes from (as the desktop app's track.rs and the Android app's model/Track.kt): the same JSON
 * on all three, so a library or a song sent from one is read by the others.
 */
public struct Track: Hashable, Sendable {
    public var source: Source
    /** YouTube: the video id. Archive: the file's download URL. Server: the song's file there (https://HOST/files/NAME, no key in it). */
    public var id: String
    public var title: String
    public var artist: String
    public var album: String
    public var seconds: Int
    public var art: String
    /** "FLAC", "24-bit FLAC", "AAC"… */
    public var format: String
    /**
     * The saved copy, once liked and saved: its place under the app's Documents ("Radiance Music/Artist - Title.m4a"),
     * never a whole path (an iPhone app's folder moves when it's installed again).
     */
    public var file: String?
    /** Its genres, looked up once for a liked song (Deezer, as the computer app); nil: not looked up yet. */
    public var genres: [String]?
    // no music video: phones have none (owner, 2026-11-08: "final na walang music video sa mobile")

    public init(source: Source, id: String, title: String, artist: String, album: String = "", seconds: Int = 0,
                art: String = "", format: String = "", file: String? = nil, genres: [String]? = nil) {
        self.source = source
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.seconds = seconds
        self.art = art
        self.format = format
        self.file = file
        self.genres = genres
    }

    public var key: String {
        switch source {
        case .archive: return "ia:\(id)"
        case .youtube: return "yt:\(id)"
        // a server's file address can be long (its name, escaped): its key is short, and the same on every phone
        case .server: return "rms:" + String(SHA256.hex(id).prefix(16))
        }
    }

    public var lossless: Bool { source == .archive }

    public func byline() -> String {
        [artist, album].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: " · ")
    }

    /**
     * Everyone on the song, one by one, as the computer app has them: the credit split ("A & B, C"), then whoever
     * the title has featured ("Tamaraw (feat. KKRAM)"), each once.
     */
    public func artists() -> [String] {
        var all = splitCredit(artist)
        for tag in ["feat.", "ft.", "featuring "] {
            guard let at = title.range(of: tag, options: .caseInsensitive) else { continue }
            let rest = title[at.upperBound...]
            let end = rest.firstIndex(where: { $0 == ")" || $0 == "]" }) ?? rest.endIndex
            all += splitCredit(String(rest[..<end]))
            break
        }
        var seen = Set<String>()
        return all.filter { seen.insert(plain($0)).inserted }
    }

    public func with(file: String?) -> Track { var t = self; t.file = file; return t }
}

// MARK: - JSON (the computer's and Android's keys; "file" and "genres" written as null when there are none)

extension Track: Codable {
    enum CodingKeys: String, CodingKey { case source, id, title, artist, album, seconds, art, format, file, genres }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value(_ k: CodingKeys) -> JSON? { try? c.decodeIfPresent(JSON.self, forKey: k) }
        func text(_ k: CodingKeys) -> String { value(k)?.string ?? "" }
        guard let source = Source(rawValue: text(.source)) else {
            throw DecodingError.dataCorruptedError(forKey: .source, in: c, debugDescription: "not a song's source")
        }
        let id = text(.id)
        if id.isEmpty { throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "no id") }
        let seconds = value(.seconds)?.int ?? 0
        let file = text(.file)
        let genres = value(.genres)?.array?.compactMap { $0.string }.filter { !$0.isEmpty }
        self.init(source: source, id: id, title: text(.title), artist: text(.artist), album: text(.album), seconds: seconds,
                  art: text(.art), format: text(.format), file: file.isEmpty ? nil : file, genres: genres)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(source.rawValue, forKey: .source)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(artist, forKey: .artist)
        try c.encode(album, forKey: .album)
        try c.encode(seconds, forKey: .seconds)
        try c.encode(art, forKey: .art)
        try c.encode(format, forKey: .format)
        if let file { try c.encode(file, forKey: .file) } else { try c.encodeNil(forKey: .file) }
        if let genres { try c.encode(genres, forKey: .genres) } else { try c.encodeNil(forKey: .genres) }
    }

    /** One song from its JSON, or nil when it isn't one (an unknown source, no id). */
    public static func from(json: JSON) -> Track? {
        try? JSONDecoder().decode(Track.self, from: json.data())
    }

    public var json: JSON {
        (try? JSONEncoder().encode(self)).flatMap { JSON.parse($0) } ?? .null
    }

    /** A list of songs from a JSON array; the ones that aren't songs are left out. */
    public static func list(_ data: Data) -> [Track] {
        guard let a = JSON.parse(data)?.array else { return [] }
        return a.compactMap { from(json: $0) }
    }

    public static func data(_ tracks: [Track]) -> Data {
        (try? JSONEncoder().encode(tracks)) ?? Data("[]".utf8)
    }
}
