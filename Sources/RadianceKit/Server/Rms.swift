import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/** What a Radiance Music Server answered "no" with: its HTTP [code] and its own plain words ({"error": "…"}). */
public struct Refused: Error, CustomStringConvertible {
    public let code: Int
    public let words: String
    /** This phone isn't joined any more (removed, or its owner removed it): its key doesn't work. */
    public var removed: Bool { code == 401 }
    public var description: String { "\(words) (HTTP \(code))" }
}

/**
 * One Radiance Music Server's API (rms/README.md, "For app developers"), as this iPhone (Android's server/Rms.kt):
 * every call carries its key (`Authorization: Bearer …`); file addresses and the party's WebSocket take `?t=…`.
 *
 * What's asked goes to [base], where the server is now; the songs' own addresses (their ids, so their keys) keep
 * [first], where it was first joined, as the computer app does.
 */
public struct Rms: Sendable {
    /** "https://music.example.com" (its scheme, host and port; nothing after). */
    public let base: String
    /** Where it was first joined (its songs' addresses keep it). */
    public let first: String
    public let token: String?

    public init(_ base: String, token: String? = nil, first: String? = nil) {
        self.base = Rms.origin(base) ?? base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.first = first.map { Rms.origin($0) ?? $0 } ?? self.base
        self.token = token
    }

    // MARK: people

    /** The server's name and state (no key needed). */
    public func status() async throws -> Status { Status.from(try await get("/api/status", auth: false)) }

    /** Joins with an invite's one-time [code], as [deviceName]: this iPhone's key. */
    public func join(_ code: String, deviceName: String) async throws -> Joined {
        try Joined.from(try await post("/api/join", ["code": .string(code), "device_name": .string(deviceName)], auth: false))
    }

    /** Who this iPhone is there, and what the owner lets it do. */
    public func me() async throws -> Me { Me.from(try await get("/api/me")) }

    /** This iPhone leaves: its key stops working. */
    public func leave(_ device: Int64) async throws { _ = try await post("/api/devices/\(device)/revoke", [:]) }

    // MARK: the library

    /** Some of the songs: the ones matching [q] (nil: all), from [offset], at most [limit] (nil: all of them). */
    public func page(_ q: String? = nil, offset: Int = 0, limit: Int? = nil) async throws -> Page {
        var query: [String: String] = [:]
        if let q = q?.trimmingCharacters(in: .whitespaces), !q.isEmpty { query["q"] = q }
        if offset > 0 { query["offset"] = "\(offset)" }
        if let limit { query["limit"] = "\(limit)" }
        let o = try await get(Http.url(file("/api/library"), query)!.absoluteString)
        let songs = (o["songs"]?.array ?? []).compactMap { ServerSong.from($0, id) }
        return Page(songs: songs, total: o["total"]?.int ?? songs.count, offset: o["offset"]?.int ?? offset)
    }

    /** Every song on the server, A to Z by artist. */
    public func library() async throws -> [ServerSong] { try await page().songs }

    /** One song, by its id (as it is now: split meanwhile, its lyrics timed…). */
    public func song(_ id: Int64) async throws -> ServerSong {
        guard let s = ServerSong.from(try await get("/api/songs/\(id)"), self.id) else { throw Refused(code: 500, words: "The server's answer about that song didn't make sense.") }
        return s
    }

    // MARK: splitting

    /** Asks the server to split [song]: its place in the queue, or that it's split already. */
    public func split(_ song: Int64) async throws -> SplitAnswer { SplitAnswer.from(try await post("/api/split", ["song": .number(Double(song))])) }

    /** The split queue: the song at work, the waiting ones in their turns, the last day's finished. */
    public func queue() async throws -> SplitQueue { SplitQueue.from(try await get("/api/queue")) }

    public func unqueue(_ job: Int64) async throws { _ = try await call(request("/api/queue/\(job)", method: "DELETE")) }

    /** The server's clock (ms since 1970), for clock-offset pings (no key needed). */
    public func time() async throws -> Int64 { try await get("/api/time", auth: false)["now_ms"]?.int64 ?? 0 }

    // MARK: addresses

    /** A song's or its file's address as the app keeps it ("/files/…" at the address first joined): its id. */
    public func id(_ path: String) -> String {
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return path }
        return first + (path.hasPrefix("/") ? path : "/\(path)")
    }

    /** An address on the server where it is now ("/api/…" made whole). */
    public func file(_ path: String) -> String {
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return path }
        return base + (path.hasPrefix("/") ? path : "/\(path)")
    }

    /** [url] with this iPhone's key in it (`?t=`), for what can't send a header (the player, a picture). */
    public func withKey(_ url: String) -> String {
        guard let token, var c = URLComponents(string: url) else { return url }
        var items = (c.percentEncodedQueryItems ?? []).filter { $0.name != "t" }
        items.append(URLQueryItem(name: "t", value: Http.escape(token)))
        c.percentEncodedQueryItems = items
        return c.url?.absoluteString ?? url
    }

    // MARK: underneath

    func request(_ path: String, method: String = "GET", auth: Bool = true, body: JSON? = nil) throws -> URLRequest {
        guard let u = URL(string: file(path)) else { throw Plain("That isn't a server's address.", path) }
        var r = URLRequest(url: u)
        r.httpMethod = method
        r.setValue(Http.userAgent, forHTTPHeaderField: "User-Agent")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        if auth, let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            r.httpBody = body.data()
            r.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        return r
    }

    func get(_ path: String, auth: Bool = true) async throws -> JSON { try await call(request(path, auth: auth)) }

    func post(_ path: String, _ body: [String: JSON], auth: Bool = true) async throws -> JSON {
        try await call(request(path, method: "POST", auth: auth, body: .object(body)))
    }

    func call(_ r: URLRequest) async throws -> JSON {
        let (data, response) = try await Http.send(r)
        return try Rms.answer(response.statusCode, data)
    }

    /** "https://Music.Example.com:443/join/X" → "https://music.example.com" (scheme, host and port only); nil: not an address. */
    public static func origin(_ url: String) -> String? {
        guard let c = URLComponents(string: url.trimmingCharacters(in: .whitespacesAndNewlines)), let scheme = c.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = c.host?.lowercased(), !host.isEmpty else { return nil }
        let standard = scheme == "https" ? 443 : 80
        let port = c.port.map { $0 == standard ? "" : ":\($0)" } ?? ""
        let h = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        return "\(scheme)://\(h)\(port)"
    }

    /** The server's answer as JSON, or what it said no with (its own words; else what its HTTP code means). */
    public static func answer(_ code: Int, _ data: Data) throws -> JSON {
        let json = JSON.parse(data)
        if (200..<300).contains(code) {
            guard let json else { throw Refused(code: code, words: "The server's answer didn't make sense. Is this a Radiance Music Server?") }
            return json
        }
        if let own = json?["error"]?.string, !own.trimmingCharacters(in: .whitespaces).isEmpty { throw Refused(code: code, words: own) }
        let words: String
        switch code {
        case 401: words = "This iPhone isn't joined to the server any more. Ask its owner for a new invite."
        case 403: words = "The server's owner doesn't let you do that."
        case 404: words = "The server didn't find that. Is this a Radiance Music Server?"
        case 413: words = "That's too big for the server."
        case 502, 503, 504: words = "The server isn't running right now, or it's starting. Try again in a minute."
        default: words = "The server couldn't do that (it answered \(code)). Try again."
        }
        throw Refused(code: code, words: words)
    }

    /** "FLAC", "Opus", "AAC": what kind of file a name is, as the app shows it. */
    public static func formatOf(_ file: String) -> String {
        switch (file.split(separator: ".").last.map(String.init) ?? "").lowercased() {
        case "flac": return "FLAC"
        case "opus", "ogg": return "Opus"
        case "m4a", "mp4", "aac": return "AAC"
        default: return ""
        }
    }
}

// MARK: - what a server answers

extension JSON {
    /** nil for a missing key, JSON null or "" (Android's str()). */
    func str(_ k: String) -> String? { self[k].flatMap { $0.isNull ? nil : $0.string }.flatMap { $0.isEmpty ? nil : $0 } }
    func flag(_ k: String, _ otherwise: Bool = false) -> Bool { self[k]?.bool ?? otherwise }
}

/** What the owner lets this iPhone's person do (the owner: everything). */
public struct Can: Equatable, Sendable {
    public var add = true, split = true, host = true
    static func from(_ o: JSON?) -> Can { Can(add: o?.flag("add", true) ?? true, split: o?.flag("split", true) ?? true, host: o?.flag("host", true) ?? true) }
}

/** Someone on a server. */
public struct Person: Equatable, Sendable {
    public let id: Int64
    public let name: String
    public let role: String
    public var owner: Bool { role == "owner" }
    static func from(_ o: JSON?) -> Person? {
        guard let o, o.object != nil else { return nil }
        return Person(id: o["id"]?.int64 ?? 0, name: o["name"]?.string ?? "", role: o.str("role") ?? "friend")
    }
}

/** [serverId]: the server's own id, the same at any address (nil: a server older than 0.1.2). */
public struct Joined: Equatable, Sendable {
    public let token: String
    public let person: Person
    public let device: Int64
    public let server: String?
    public let serverId: String?
    static func from(_ o: JSON) throws -> Joined {
        guard let token = o.str("token") else { throw Refused(code: 500, words: "The server didn't give this iPhone a key. Try again.") }
        return Joined(token: token, person: Person.from(o["person"]) ?? Person(id: 0, name: "", role: "friend"),
                      device: o["device"]?["id"]?.int64 ?? 0, server: o["server"]?.str("name"), serverId: o["server"]?.str("id"))
    }
}

public struct Me: Equatable, Sendable {
    public let person: Person
    public let device: Int64
    public let deviceName: String
    public let server: String?
    public let can: Can
    public let serverId: String?
    static func from(_ o: JSON) -> Me {
        Me(person: Person.from(o["person"]) ?? Person(id: 0, name: "", role: "friend"), device: o["device"]?["id"]?.int64 ?? 0,
           deviceName: o["device"]?.str("name") ?? "", server: o["server"]?.str("name"), can: Can.from(o["can"]), serverId: o["server"]?.str("id"))
    }
}

/** GET /api/status: the server's name and its own id, and how its splitter is getting on. */
public struct Status: Equatable, Sendable {
    public let server: String?
    public let needsSetup: Bool
    public let version: String
    public let splitterReady: Bool
    public let splitterMessage: String
    public let id: String?
    static func from(_ o: JSON) -> Status {
        Status(server: o.str("server"), needsSetup: o.flag("needs_setup"), version: o["version"]?.string ?? "",
               splitterReady: o["splitter"]?.flag("ready") ?? false, splitterMessage: o["splitter"]?.str("message") ?? "", id: o.str("id"))
    }
}

/** A page of the library: [songs] from [offset], of [total] that match. */
public struct Page: Equatable, Sendable {
    public let songs: [ServerSong]
    public let total: Int
    public let offset: Int
    public var more: Bool { offset + songs.count < total }
}

/** One of a song's files on the server: its name, its size, its whole address. */
public struct ServerFile: Equatable, Sendable {
    public let name: String
    public let size: Int64
    public let url: String
}

/** A song in a server's library, with its parts, lyrics, cover and who added it. */
public struct ServerSong: Equatable, Sendable {
    public let id: Int64
    public let artist: String
    public let title: String
    public let file: String
    /** The song's own file, whole address (no key in it). */
    public let url: String
    public let durationMs: Int64?
    public let split: Bool
    public let parts: [String]
    public let lyrics: Bool
    public let wordTimes: Bool
    public let cover: String?
    /** kind (song, drums, bass, other, vocals, music, lyrics, cover) → the file. */
    public let files: [String: ServerFile]
    public let addedBy: Person?

    /** As the app's players and lists hold a song: from this server, its file the address, its cover the picture. */
    public func track() -> Track {
        Track(source: .server, id: url, title: title, artist: artist, seconds: Int((durationMs ?? 0) / 1000), art: cover ?? "", format: Rms.formatOf(file))
    }

    static func from(_ o: JSON, _ whole: (String) -> String) -> ServerSong? {
        guard let file = o.str("file") else { return nil }
        var files: [String: ServerFile] = [:]
        for (k, e) in o["files"]?.object ?? [:] where e.object != nil {
            files[k] = ServerFile(name: e["name"]?.string ?? "", size: e["size"]?.int64 ?? 0, url: whole(e["url"]?.string ?? ""))
        }
        let d = o["duration_ms"]?.int64
        return ServerSong(id: o["id"]?.int64 ?? 0, artist: o["artist"]?.string ?? "", title: o["title"]?.string ?? "", file: file,
                          url: whole(o.str("url") ?? "/files/\(file)"), durationMs: (d ?? 0) > 0 ? d : nil, split: o.flag("split"),
                          parts: (o["parts"]?.array ?? []).compactMap { $0.string }, lyrics: o.flag("lyrics"), wordTimes: o.flag("word_times"),
                          cover: o.str("cover").map(whole), files: files, addedBy: Person.from(o["added_by"]))
    }
}

/** A song in the split queue, and how it's getting on (the server's words: "Waiting: 2 songs before it."). */
public struct Job: Equatable, Sendable {
    public let id: Int64
    public let song: Int64
    public let artist: String
    public let title: String
    public let askedBy: Person?
    public let state: String
    public let progress: Double
    public let note: String
    public var working: Bool { state == "splitting" || state == "timing" }
    public var waiting: Bool { state == "waiting" }
    public var open: Bool { working || waiting }
    static func from(_ o: JSON) -> Job {
        let s = o["song"]
        return Job(id: o["id"]?.int64 ?? 0, song: s?["id"]?.int64 ?? 0, artist: s?["artist"]?.string ?? "", title: s?["title"]?.string ?? "",
                   askedBy: Person.from(o["asked_by"]), state: o["state"]?.string ?? "", progress: o["progress"]?.double ?? 0, note: o["note"]?.string ?? "")
    }
}

/** GET /api/queue: the jobs (at work, waiting in their turns, finished lately), whose turn is next, and the splitter's state. */
public struct SplitQueue: Equatable, Sendable {
    public let jobs: [Job]
    public let nextTurn: Person?
    public let splitterReady: Bool
    public let splitterMessage: String
    /** [song]'s job still in the queue (at work or waiting), if there is one. */
    public func of(_ song: Int64) -> Job? { jobs.first { $0.song == song && $0.open } }
    /** Its place among the waiting songs (0: next), or nil. */
    public func place(_ job: Job) -> Int? { jobs.filter(\.waiting).firstIndex { $0.id == job.id } }
    static func from(_ o: JSON) -> SplitQueue {
        SplitQueue(jobs: (o["jobs"]?.array ?? []).filter { $0.object != nil }.map(Job.from), nextTurn: Person.from(o["next_turn"]),
                   splitterReady: o["splitter"]?.flag("ready") ?? false, splitterMessage: o["splitter"]?.str("message") ?? "")
    }
}

/** POST /api/split's answer: split already, or its job (new, or the one there was). */
public struct SplitAnswer: Equatable, Sendable {
    public let alreadySplit: Bool
    public let queued: Bool
    public let job: Job?
    static func from(_ o: JSON) -> SplitAnswer {
        SplitAnswer(alreadySplit: o.flag("already_split"), queued: o.flag("queued"), job: o["job"].flatMap { $0.object != nil ? Job.from($0) : nil })
    }
}
