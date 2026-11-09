import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/**
 * Songs going from one device to another, straight, on the same Wi-Fi (or the iPhone's Personal Hotspot): no server
 * in between (Android's share/Wire.kt, the same wire, so an iPhone, an Android phone and the computer share with each
 * other).
 *
 * The device showing the QR code listens; the one scanning it connects. The QR says which way the songs go: "get"
 * (the scanner takes the songs shown) or "put" (the scanner sends its songs here). Before anything moves, the
 * receiving side says what it has already: a song saved there is never sent again, nor parts already split there;
 * only what's missing goes. A tiny HTTP: GET /list, GET /file; POST /plan, PUT /file, POST /done; ?k= the key.
 */
public enum Wire {
    public static let version = 1
    /** What a song can come with. Never a music video (owner, 2026-11-08: "final na walang music video sa mobile"). */
    public static let kinds = ["song", "drums", "bass", "other", "vocals", "music", "lyrics", "cover"]
    /** Bigger than any song would be: refused. */
    public static let mostBytes: Int64 = 4 << 30

    public struct FileInfo: Equatable, Sendable {
        public let name: String
        public let size: Int64
        public init(name: String, size: Int64) { self.name = name; self.size = size }
    }

    /** One song on offer: its key, its details (Track's JSON) and its files by kind. */
    public struct Item: Equatable, Sendable {
        public let key: String
        public let track: JSON
        public let files: [String: FileInfo]
        public init(key: String, track: JSON, files: [String: FileInfo]) { self.key = key; self.track = track; self.files = files }

        public var json: JSON {
            var f: [String: JSON] = [:]
            for (k, v) in files { f[k] = ["name": .string(v.name), "size": .number(Double(v.size))] }
            return ["key": .string(key), "track": track, "files": .object(f)]
        }

        public static func from(_ o: JSON) -> Item? {
            guard let key = o["key"]?.string, !key.isEmpty else { return nil }
            var files: [String: FileInfo] = [:]
            for (k, e) in o["files"]?.object ?? [:] where kinds.contains(k) {
                let size = e["size"]?.int64 ?? -1
                if size >= 0 && size <= mostBytes { files[k] = FileInfo(name: e["name"]?.string ?? "", size: size) }
            }
            return Item(key: key, track: o["track"] ?? .object([:]), files: files)
        }

        public var title: String { track["title"]?.string ?? "" }
    }

    /** How far along: bytes done of all, songs done of all, the song now. */
    public struct Progress: Equatable, Sendable {
        public let bytes: Int64, totalBytes: Int64, songs: Int, totalSongs: Int
        public let now: String?
        public init(bytes: Int64, totalBytes: Int64, songs: Int, totalSongs: Int, now: String?) {
            self.bytes = bytes; self.totalBytes = totalBytes; self.songs = songs; self.totalSongs = totalSongs; self.now = now
        }
    }

    /** A QR's words: `radiancemusic://share?…`. */
    public struct Ticket: Equatable, Sendable {
        public let mode: String // "get" or "put"
        public let host: String?
        public let port: Int
        public let key: String
        public let name: String
        /** Android's own Wi-Fi Direct network (an iPhone can't join one by itself: same Wi-Fi only). */
        public let group: String?
        public let pass: String?
        public let groupHost: String?

        public init(mode: String, host: String?, port: Int, key: String, name: String, group: String? = nil, pass: String? = nil, groupHost: String? = nil) {
            self.mode = mode; self.host = host; self.port = port; self.key = key; self.name = name
            self.group = group; self.pass = pass; self.groupHost = groupHost
        }

        public var uri: String {
            var s = "radiancemusic://share?v=\(Wire.version)&m=\(mode)&k=\(key)&p=\(port)&n=\(enc(name))"
            if let host { s += "&h=\(host)" }
            if let group { s += "&g=\(enc(group))" }
            if let pass { s += "&w=\(enc(pass))" }
            if let groupHost { s += "&gh=\(groupHost)" }
            return s
        }

        public static func parse(_ s: String) -> Ticket? {
            guard s.hasPrefix("radiancemusic://share?") else { return nil }
            let q = query(String(s[s.index(after: s.firstIndex(of: "?")!)...]))
            guard Int(q["v"] ?? "") == Wire.version, let mode = q["m"], mode == "get" || mode == "put",
                  let key = q["k"], key.count >= 16, let port = Int(q["p"] ?? ""), (1...65535).contains(port) else { return nil }
            return Ticket(mode: mode, host: q["h"], port: port, key: key, name: q["n"] ?? "a device", group: q["g"], pass: q["w"], groupHost: q["gh"])
        }
    }

    public static func newKey() -> String {
        var g = SystemRandomNumberGenerator()
        return (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &g)) }.joined()
    }

    static func enc(_ s: String) -> String {
        // as Java's URLEncoder: spaces as "+", the rest escaped
        let ok = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.*")
        return s.unicodeScalars.map { u in
            if u == " " { return "+" }
            if ok.contains(u) { return String(u) }
            return String(u).utf8.map { String(format: "%%%02X", $0) }.joined()
        }.joined()
    }

    public static func query(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        for pair in s.split(separator: "&") where pair.contains("=") {
            let k = pair[..<pair.firstIndex(of: "=")!], v = pair[pair.index(after: pair.firstIndex(of: "=")!)...]
            func dec(_ x: Substring) -> String { String(x).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(x) }
            out[dec(k)] = dec(v)
        }
        return out
    }

    /** What a device offers. */
    public protocol Offer: Sendable {
        func items() -> [Item]
        func open(_ key: String, _ kind: String) -> URL?
    }

    /** Where songs land. */
    public protocol Store: Sendable {
        /** The kinds of [item] already here (it's saved here: "song"; split here: the parts…). */
        func have(_ item: Item) async -> Set<String>
        /** [kind] of [item] came: its file (in a temporary place: the store moves it). */
        func write(_ item: Item, _ kind: String, _ file: URL) async throws
        /** All [item]'s files are here: it joins the library. */
        func done(_ item: Item) async
    }

    static func url(_ base: String, _ path: String, _ key: String, _ extra: [(String, String)] = []) -> URL {
        URL(string: "\(base)\(path)?k=\(key)" + extra.map { "&\($0.0)=\(enc($0.1))" }.joined())!
    }

    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 3600
        return URLSession(configuration: c)
    }()

    /** Can [base] be reached (a moment)? */
    public static func reachable(_ base: String, key: String, mode: String) async -> Bool {
        var r = URLRequest(url: url(base, mode == "get" ? "/list" : "/plan", key), timeoutInterval: 3)
        if mode == "put" { r.httpMethod = "POST"; r.httpBody = Data(#"{"songs":[]}"#.utf8); r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return (try? await send(r).1.statusCode) == 200
    }

    static func send(_ r: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { cont in
            session.dataTask(with: r) { d, resp, e in
                if let e { return cont.resume(throwing: e) }
                guard let h = resp as? HTTPURLResponse else { return cont.resume(throwing: Plain("The other device didn't answer.")) }
                cont.resume(returning: (d ?? Data(), h))
            }.resume()
        }
    }

    /** Takes what's missing here of what [base] offers, into [store]. How many songs came. */
    public static func pull(_ base: String, key: String, store: Store, cancelled: @Sendable () -> Bool = { false },
                            progress: @escaping @Sendable (Progress) -> Void = { _ in }) async throws -> Int {
        let (d, r) = try await send(URLRequest(url: url(base, "/list", key)))
        guard r.statusCode == 200, let list = JSON.parse(d)?["songs"]?.array else { throw Plain("The other device said no. Scan its QR again.", "HTTP \(r.statusCode)") }
        let items = list.compactMap(Item.from)
        var todo: [(Item, [String])] = []
        for i in items {
            let have = await store.have(i)
            let missing = i.files.keys.filter { !have.contains($0) }.sorted()
            if !missing.isEmpty { todo.append((i, missing)) }
        }
        let total = todo.reduce(Int64(0)) { t, e in t + e.1.reduce(Int64(0)) { $0 + (e.0.files[$1]?.size ?? 0) } }
        var bytes: Int64 = 0
        var songs = 0
        progress(Progress(bytes: 0, totalBytes: total, songs: 0, totalSongs: todo.count, now: nil))
        for (item, kinds) in todo {
            if cancelled() { break }
            for kind in kinds {
                if cancelled() { break }
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("wire-\(UUID().uuidString)")
                let (f, resp): (URL, HTTPURLResponse) = try await withCheckedThrowingContinuation { cont in
                    session.downloadTask(with: url(base, "/file", key, [("key", item.key), ("kind", kind)])) { u, resp, e in
                        if let e { return cont.resume(throwing: e) }
                        guard let u, let h = resp as? HTTPURLResponse else { return cont.resume(throwing: Plain("“\(item.title)” didn't come.")) }
                        do { try FileManager.default.moveItem(at: u, to: tmp); cont.resume(returning: (tmp, h)) } catch { cont.resume(throwing: error) }
                    }.resume()
                }
                guard resp.statusCode == 200 else { try? FileManager.default.removeItem(at: f); throw Plain("“\(item.title)” didn't come.", "HTTP \(resp.statusCode)") }
                try await store.write(item, kind, f)
                try? FileManager.default.removeItem(at: f)
                bytes += item.files[kind]?.size ?? 0
                progress(Progress(bytes: bytes, totalBytes: total, songs: songs, totalSongs: todo.count, now: item.title))
            }
            if cancelled() { break }
            await store.done(item)
            songs += 1
            progress(Progress(bytes: bytes, totalBytes: total, songs: songs, totalSongs: todo.count, now: nil))
        }
        return songs
    }

    /** Sends [offer]'s songs that [base] hasn't got. How many went. */
    public static func push(_ base: String, key: String, offer: Offer, cancelled: @Sendable () -> Bool = { false },
                            progress: @escaping @Sendable (Progress) -> Void = { _ in }) async throws -> Int {
        let items = offer.items()
        var r = URLRequest(url: url(base, "/plan", key))
        r.httpMethod = "POST"
        r.httpBody = JSON.object(["songs": .array(items.map(\.json))]).data()
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (d, resp) = try await send(r)
        guard resp.statusCode == 200, let want = JSON.parse(d)?["want"]?.object else { throw Plain("The other device said no. Scan its QR again.", "HTTP \(resp.statusCode)") }
        let todo: [(Item, [String])] = items.compactMap { i in
            guard let w = want[i.key]?.array else { return nil }
            return (i, w.compactMap { $0.string }.filter { i.files[$0] != nil })
        }
        let total = todo.reduce(Int64(0)) { t, e in t + e.1.reduce(Int64(0)) { $0 + (e.0.files[$1]?.size ?? 0) } }
        var bytes: Int64 = 0
        var songs = 0
        progress(Progress(bytes: 0, totalBytes: total, songs: 0, totalSongs: todo.count, now: nil))
        for (item, kinds) in todo {
            if cancelled() { break }
            for kind in kinds {
                if cancelled() { break }
                guard let f = offer.open(item.key, kind) else { throw Plain("“\(item.title)” isn't on this iPhone any more.") }
                var put = URLRequest(url: url(base, "/file", key, [("key", item.key), ("kind", kind)]))
                put.httpMethod = "PUT"
                put.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                let code: Int = try await withCheckedThrowingContinuation { cont in
                    session.uploadTask(with: put, fromFile: f) { _, resp, e in
                        if let e { return cont.resume(throwing: e) }
                        cont.resume(returning: (resp as? HTTPURLResponse)?.statusCode ?? 0)
                    }.resume()
                }
                guard code == 200 else { throw Plain("“\(item.title)” wasn't taken.", "HTTP \(code)") }
                bytes += item.files[kind]?.size ?? 0
                progress(Progress(bytes: bytes, totalBytes: total, songs: songs, totalSongs: todo.count, now: item.title))
            }
            if cancelled() { break }
            var done = URLRequest(url: url(base, "/done", key, [("key", item.key)]))
            done.httpMethod = "POST"
            done.httpBody = Data()
            _ = try? await send(done)
            songs += 1
            progress(Progress(bytes: bytes, totalBytes: total, songs: songs, totalSongs: todo.count, now: nil))
        }
        return songs
    }
}
