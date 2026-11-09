import Foundation
import Observation

/**
 * A Radiance Music Server this iPhone joined (Android's server/Servers.kt): where it is, this iPhone's key for it,
 * its name ("Bassi's server"), who you are there and what its owner lets you do (as last heard). Its [id] is its
 * own, the same at any address; its songs keep the address it was [first] joined at in their ids (so their keys never
 * change); what's asked of it goes to [base], where it is now.
 */
public struct Server: Equatable, Sendable, Identifiable {
    /** "https://music.example.com" (or "http://203.0.113.5:8080"). */
    public var base: String
    public var token: String
    public var name: String
    public var me: Person?
    /** This iPhone's device number there (to leave). */
    public var device: Int64 = 0
    public var can = Can()
    public var joinedMs: Int64 = 0
    /** The server's own id (from 0.1.2; nil: not heard yet). */
    public var serverId: String?
    /** Where it was when this iPhone joined it: its songs' addresses keep it. */
    public var first: String

    public var id: String { first }
    public var rms: Rms { Rms(base, token: token, first: first) }

    /** One of its addresses (a song's id: at the address first joined) where it is now. */
    public func here(_ url: String) -> String {
        first != base && url.hasPrefix("\(first)/") ? base + url.dropFirst(first.count) : url
    }

    /** Its address as you'd say it: "music.example.com". */
    public var host: String { base.components(separatedBy: "://").last ?? base }

    var json: JSON {
        ["base": .string(base), "token": .string(token), "name": .string(name),
         "me": me.map { ["id": .number(Double($0.id)), "name": .string($0.name), "role": .string($0.role)] } ?? .null,
         "device": .number(Double(device)), "can": ["add": .bool(can.add), "split": .bool(can.split), "host": .bool(can.host)],
         "joined_ms": .number(Double(joinedMs)), "id": serverId.map { .string($0) } ?? .null, "first_address": .string(first)]
    }

    static func from(_ o: JSON) -> Server? {
        guard let base = o.str("base"), let token = o.str("token") else { return nil }
        return Server(base: base, token: token, name: o.str("name") ?? (base.components(separatedBy: "://").last ?? base), me: Person.from(o["me"]),
                      device: o["device"]?.int64 ?? 0, can: Can.from(o["can"]), joinedMs: o["joined_ms"]?.int64 ?? 0, serverId: o.str("id"),
                      first: o.str("first_address") ?? base)
    }
}

/** How a server is doing, as last heard from it. */
public enum Health: Equatable, Sendable {
    case unknown
    case answering
    /** It didn't answer: [why] in plain words; [offline]: the iPhone is. */
    case down(why: String, offline: Bool)
    /** Its owner removed this iPhone (or you): its key doesn't work any more. */
    case removed(why: String)
}

/**
 * The servers this iPhone joined, kept in a small JSON file: each one's address, key and name. Joining reads an
 * invite (its link, or its QR) and asks the server for this iPhone's key; leaving gives it back. Songs from a joined
 * server are played with its key in their address (`?t=`).
 */
@MainActor
@Observable
public final class Servers {
    @ObservationIgnored let file: URL
    /** Joined servers, the first joined first. */
    public private(set) var list: [Server] = []
    /** Each server's last answer (by its base address). */
    public private(set) var health: [String: Health] = [:]

    public init(dir: URL) {
        file = dir.appendingPathComponent("servers.json")
        list = ((try? Data(contentsOf: file)).flatMap { JSON.parse($0)?.array } ?? []).compactMap(Server.from)
    }

    private func save(_ l: [Server]) {
        list = l
        try? JSON.array(l.map(\.json)).data().write(to: file, options: .atomic)
    }

    public func healthy(_ base: String, _ h: Health) { health[base] = h }

    public func byBase(_ base: String) -> Server? { list.first { $0.base == base } }

    /** The joined server [url] is on (where it is now or was first joined), if it's one. */
    public func of(_ url: String) -> Server? {
        guard !list.isEmpty, let origin = Rms.origin(url) else { return nil }
        return list.first { $0.base == origin } ?? list.first { $0.first == origin }
    }

    /** The server a song came from (a server's song: its file's address). */
    public func of(_ t: Track) -> Server? { t.source == .server ? of(t.id) : nil }

    /** A joined server's file address where it is now, with this iPhone's key in it (`?t=`), for the player; any other address as it is. */
    public func sign(_ url: String) -> String {
        guard let c = URLComponents(string: url), c.percentEncodedPath.hasPrefix("/files/"), let s = of(url) else { return url }
        let now = s.here(url)
        if URLComponents(string: now)?.queryItems?.contains(where: { $0.name == "t" }) == true { return now }
        return s.rms.withKey(now)
    }

    /** An invite: the server's address and its one-time code. */
    public struct Invite: Equatable, Sendable {
        public let base: String
        public let code: String
    }

    /** An invite as pasted or scanned: `https://HOST/join/CODE` (anywhere in the words, with or without https://). */
    public nonisolated static func invite(_ text: String) -> Invite? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let inner = joinLink(t), inner != t { return invite(inner) }
        let pattern = #"(?:(https?)://)?([A-Za-z0-9.\-]+|\[[0-9A-Fa-f:.]+\])(:\d{1,5})?/join/([A-Za-z0-9\-]{4,40})"#
        guard let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) else { return nil }
        func group(_ i: Int) -> String { Range(m.range(at: i), in: t).map { String(t[$0]) } ?? "" }
        let scheme = group(1), host = group(2), port = group(3), code = group(4)
        // a link without its https://: a name gets https, a bare address (a server without a domain) http
        let bare = host.hasPrefix("[") || host.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil
        let s = scheme.isEmpty ? (bare || host == "localhost" ? "http" : "https") : scheme
        guard let base = Rms.origin("\(s)://\(host)\(port)/"), code.lettersAndDigits.count >= 4 else { return nil }
        return Invite(base: base, code: code)
    }

    /** The invite in an app link, `radiancemusic://join?u=<the invite's address>` (nil: it isn't one). */
    public nonisolated static func joinLink(_ link: String) -> String? {
        guard link.hasPrefix("radiancemusic://join"), let c = URLComponents(string: link) else { return nil }
        let u = c.queryItems?.first { $0.name == "u" }?.value?.trimmingCharacters(in: .whitespaces)
        return (u?.isEmpty ?? true) ? nil : u
    }

    /**
     * Joins the server in [text] (an invite's link or QR) as this iPhone: its key, its name, who you are there.
     * Joined there already: the new key takes the old one's place (and the old one is given back). The same server
     * (its id) at a new address moves there, keeping its first address for its songs.
     */
    public func join(_ text: String, deviceName: String) async throws -> Server {
        guard let inv = Servers.invite(text) else {
            throw Plain("That isn't an invite. It looks like https://music.example.com/join/ABCD-EFGH-JKLM: paste the whole link, or scan its QR.")
        }
        let status = try? await Rms(inv.base).status()
        let known = byBase(inv.base) ?? status?.id.flatMap { i in list.first { $0.serverId == i } }
        if let known, known.base != inv.base, let there = try? await Rms(inv.base, token: known.token).me() {
            var moved = known
            moved.base = inv.base
            moved.name = there.server ?? status?.server ?? known.name
            moved.me = there.person
            moved.can = there.can
            moved.serverId = known.serverId ?? there.serverId
            return replace(known, moved)
        }
        let joined = try await Rms(inv.base).join(inv.code, deviceName: deviceName)
        let me = try? await Rms(inv.base, token: joined.token).me()
        let server = Server(base: inv.base, token: joined.token, name: joined.server ?? me?.server ?? status?.server ?? (inv.base.components(separatedBy: "://").last ?? inv.base),
                            me: me?.person ?? joined.person, device: me?.device ?? joined.device, can: me?.can ?? Can(),
                            joinedMs: Int64(Date().timeIntervalSince1970 * 1000), serverId: joined.serverId ?? me?.serverId ?? status?.id,
                            first: known?.first ?? inv.base)
        if let known, known.token != joined.token { try? await Rms(inv.base, token: known.token).leave(known.device) }
        if let known { return replace(known, server) }
        save(list + [server])
        healthy(server.base, .answering)
        return server
    }

    private func replace(_ was: Server, _ now: Server) -> Server {
        save(list.map { $0.first == was.first ? now : $0 })
        health[was.base] = nil
        healthy(now.base, .answering)
        return now
    }

    /**
     * Leaves [s]: this iPhone's key stops working there ([onServer]), and the iPhone forgets it. The server said no,
     * or didn't answer: it's kept, and why comes back (forget it here anyway with [onServer] false).
     */
    public func leave(_ s: Server, onServer: Bool = true) async throws {
        if onServer {
            do { try await s.rms.leave(s.device) } catch let r as Refused where r.removed {
                // removed there already: nothing to give back
            }
        }
        save(list.filter { $0.first != s.first })
        health[s.base] = nil
    }

    /** Asks each server who this iPhone is there now (its name, what it may do), and keeps how it answered. */
    public func refresh(online: Bool = true) async {
        for s in list {
            do {
                let me = try await s.rms.me()
                var n = s
                n.name = me.server ?? s.name
                n.me = me.person
                n.can = me.can
                n.serverId = s.serverId ?? me.serverId
                if n != s { save(list.map { $0.first == s.first ? n : $0 }) }
                healthy(s.base, .answering)
            } catch let r as Refused where r.removed {
                healthy(s.base, .removed(why: r.words))
            } catch {
                healthy(s.base, .down(why: Errors.say(error, online: online), offline: !online))
            }
        }
    }
}

// MARK: - the server's copy first

extension Servers {
    /**
     * A joined server's copy of [t] (owner, 2026-11-09: the server's copy first, else the song from where it's from):
     * the same title and artist there (accents, case and bracketed extras aside). Nil: no joined server has it, or
     * none answered.
     */
    public func copy(of t: Track) async -> (Server, ServerSong)? {
        guard t.source != .server else { return nil }
        for s in list {
            if case .removed = health[s.base] ?? .unknown { continue }
            guard let page = try? await s.rms.page("\(t.artist) \(t.title)", limit: 10) else { continue }
            if let song = page.songs.first(where: { Servers.same($0, t) && Servers.playable($0.file) }) { return (s, song) }
        }
        return nil
    }

    /** A file the iPhone's player opens (not Opus in Ogg or WebM, which most of a computer's songs are). */
    public nonisolated static func playable(_ file: String) -> Bool {
        ["m4a", "mp4", "aac", "flac", "mp3", "wav", "caf", "aif", "aiff", "alac"].contains((file.split(separator: ".").last.map(String.init) ?? "").lowercased())
    }

    /**
     * [song] on a server is [t]: the same plain artist and plain title (accents, case, spaces and bracketed extras
     * aside), exactly as Android matches it (owner, 2026-11-09, for every app: the server's copy first).
     */
    public nonisolated static func same(_ song: ServerSong, _ t: Track) -> Bool {
        !plain(t.title).isEmpty && plain(song.title) == plain(t.title) && plain(song.artist) == plain(t.artist)
    }
}
