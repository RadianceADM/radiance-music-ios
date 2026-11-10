import Foundation

// The listening party on a Radiance Music Server (Android's server/Party.kt, PartyClock.kt and Rms.kt's party): the
// server keeps the clock and the queue and sends every change over a WebSocket; the phones play its song in step.

/** A song in the party: playing, or waiting its turn ([entry]: its place's own number). */
public struct PartySong: Equatable, Sendable {
    public let entry: Int64
    public let id: Int64
    public let artist: String
    public let title: String
    public let file: String
    public let url: String
    public let cover: String?
    public let durationMs: Int64?
    public let addedBy: Person?

    public init(entry: Int64, id: Int64, artist: String, title: String, file: String, url: String, cover: String? = nil, durationMs: Int64? = nil, addedBy: Person? = nil) {
        self.entry = entry; self.id = id; self.artist = artist; self.title = title; self.file = file; self.url = url
        self.cover = cover; self.durationMs = durationMs; self.addedBy = addedBy
    }

    public func track() -> Track {
        Track(source: .server, id: url, title: title, artist: artist, seconds: Int((durationMs ?? 0) / 1000), art: cover ?? "", format: Rms.formatOf(file))
    }

    static func from(_ o: JSON, _ whole: (String) -> String) -> PartySong {
        let d = o["duration_ms"]?.int64
        return PartySong(entry: o["entry"]?.int64 ?? 0, id: o["id"]?.int64 ?? 0, artist: o["artist"]?.string ?? "", title: o["title"]?.string ?? "",
                         file: o["file"]?.string ?? "", url: whole(o.str("url") ?? "/files/\(o["file"]?.string ?? "")"),
                         cover: o.str("cover").map(whole), durationMs: (d ?? 0) > 0 ? d : nil, addedBy: Person.from(o["added_by"]))
    }
}

public struct Member: Equatable, Sendable {
    public let id: Int64
    public let name: String
    public let devices: Int
    public let host: Bool
}

/** A reaction (an emoji, drawn as a soft picture) and when it came, by the server's clock. */
public struct Reaction: Equatable, Sendable {
    public let emoji: String
    public let by: Person?
    public let atServerMs: Int64
}

/**
 * The party as everyone sees it. A playing song has [startedAtServerMs]: the server time its position was (or will
 * be) 0; a paused one, [pausedAtMs]. Each change starts [leadMs] after it's made, so everyone has it in time.
 */
public struct PartyState: Equatable, Sendable {
    public var on: Bool
    public var id: String? = nil
    public var host: Person? = nil
    public var everyoneControls = false
    public var song: PartySong? = nil
    public var playing = false
    public var startedAtServerMs: Int64? = nil
    public var pausedAtMs: Int64? = nil
    public var serverMs: Int64 = 0
    public var leadMs: Int64 = 800
    public var queue: [PartySong] = []
    public var members: [Member] = []
    public var reactions: [Reaction] = []
    public var version: Int64 = 0

    public init(on: Bool, id: String? = nil, host: Person? = nil, everyoneControls: Bool = false, song: PartySong? = nil, playing: Bool = false,
                startedAtServerMs: Int64? = nil, pausedAtMs: Int64? = nil, queue: [PartySong] = [], version: Int64 = 0) {
        self.on = on; self.id = id; self.host = host; self.everyoneControls = everyoneControls; self.song = song; self.playing = playing
        self.startedAtServerMs = startedAtServerMs; self.pausedAtMs = pausedAtMs; self.queue = queue; self.version = version
    }

    public static let off = PartyState(on: false)

    public static func from(_ o: JSON, _ whole: (String) -> String) -> PartyState {
        var p = PartyState(on: o.flag("on"))
        p.id = o.str("id")
        p.host = Person.from(o["host"])
        p.everyoneControls = o.flag("everyone_controls")
        p.song = o["song"].flatMap { $0.object != nil ? PartySong.from($0, whole) : nil }
        p.playing = o.flag("playing")
        p.startedAtServerMs = o["started_at_server_ms"]?.int64
        p.pausedAtMs = o["paused_at_ms"]?.int64
        p.serverMs = o["server_ms"]?.int64 ?? 0
        p.leadMs = o["lead_ms"]?.int64 ?? 800
        p.queue = (o["queue"]?.array ?? []).filter { $0.object != nil }.map { PartySong.from($0, whole) }
        p.members = (o["members"]?.array ?? []).filter { $0.object != nil }.map {
            Member(id: $0["id"]?.int64 ?? 0, name: $0["name"]?.string ?? "", devices: $0["devices"]?.int ?? 1, host: $0.flag("host"))
        }
        p.reactions = (o["reactions"]?.array ?? []).filter { $0.object != nil }.map {
            Reaction(emoji: $0["emoji"]?.string ?? "", by: Person.from($0["by"]), atServerMs: $0["at_server_ms"]?.int64 ?? 0)
        }
        p.version = o["version"]?.int64 ?? 0
        return p
    }
}

/**
 * The listening party's clock, apart from any player (so it's tested on Linux): this phone's offset to the server's
 * clock from a few pings (NTP-style: the quickest one wins), where the party's song is now (as party.rs keeps it), and
 * what to do about the player's own place: stay, nudge its speed a little, or jump.
 *
 *   position = (this phone's now + offset) - started_at_server_ms
 *
 * A change starts lead_ms after it's made, so a fresh song's position is below 0 for a moment: it starts at 0 when
 * that moment comes.
 */
public enum PartyClock {
    /**
     * Further off than this (ms): the player jumps to where the party is (it stalled, or it's just joined). Anything
     * less is eased back with the speed (owner, 2026-11-10: the party "paputol putol" on Android when it jumped at 80 ms).
     */
    public static let jumpMs: Int64 = 1_000
    /** Within this (ms) it's in step: normal speed. In between: a nudge. */
    public static let steadyMs: Int64 = 20
    /** The biggest nudge: 3 % faster or slower (with the pitch kept, nobody hears it). */
    public static let nudge: Float = 0.03
    /** The nudge grows with how far off it is, a step of 1 % at a time. */
    public static let nudgeStep: Float = 0.01
    /** A jump lands late by however long the player takes to go on; it learns that, up to this. */
    public static let mostLeadMs: Int64 = 3_000
    /** Karaoke on (the parts play, the song's own player is silent): never nudged; further off than this, a jump. */
    public static let jumpPartsMs: Int64 = jumpMs
    /** After a jump, this long without another (ms): it settles first (a nudge meanwhile). */
    public static let settleMs: Int64 = 8_000
    /** How long after a jump its landing is judged (ms): once it's playing again, not while it's still loading. */
    public static let landedMs: Int64 = 2_000
    /** Nudging, it goes on till it's this close (ms): the speed doesn't flip every second at the edge. */
    public static let nudgeUntilMs: Int64 = 8

    /** One ping: [sent] and [received] by this phone's clock (ms), [server] the server's clock in between. */
    public struct Ping: Equatable, Sendable {
        public let sent: Int64, server: Int64, received: Int64
        public init(sent: Int64, server: Int64, received: Int64) { self.sent = sent; self.server = server; self.received = received }
        public var rtt: Int64 { received - sent }
        /** The server's clock minus this phone's, taking the answer as made halfway. */
        public var offset: Int64 { server - (sent + received) / 2 }
    }

    /** The quickest ping (its offset is off by at most half its round trip); nil: none came back. */
    public static func best(_ pings: [Ping]) -> Ping? { pings.filter { $0.rtt >= 0 }.min { $0.rtt < $1.rtt } }

    /**
     * Where the party's song should be at [serverNow] (ms into it): playing, from when it started; paused, where it
     * stopped. Negative: it starts in that long. nil: nothing's playing.
     */
    public static func target(_ p: PartyState, _ serverNow: Int64) -> Int64? {
        guard p.on, p.song != nil else { return nil }
        if p.playing { return p.startedAtServerMs.map { serverNow - $0 } }
        return p.pausedAtMs ?? 0
    }

    public enum Move: Equatable, Sendable {
        /** In step: play at normal speed. */
        case steady
        /** A little off: this speed for now (1 ± nudge). */
        case nudge(Float)
        /** Too far off: go to this (ms). */
        case jump(Int64)
    }

    /**
     * The player is at [playerMs], the party at [targetMs]: jump past jumpMs (landing [lead] ms further on), nudge the
     * speed past steadyMs (slower when ahead, faster when behind), else normal speed. A jump only when it was that far
     * off at the check before too ([farBefore]) and not within settleMs of the last one ([sinceJumpMs]); meanwhile a
     * nudge. [nudging]: it's nudging now, so it goes on till within nudgeUntilMs. [parts]: karaoke on: past
     * jumpPartsMs a jump, never a nudge.
     */
    public static func decide(_ playerMs: Int64, _ targetMs: Int64, lead: Int64 = 0, nudging: Bool = false, farBefore: Bool = true,
                              sinceJumpMs: Int64 = .max, parts: Bool = false) -> Move {
        let drift = playerMs - targetMs
        let off = abs(drift)
        if off > jumpPast(parts), farBefore, sinceJumpMs >= settleMs { return .jump(max(targetMs + lead, 0)) }
        if parts { return .steady }
        if off <= (nudging ? nudgeUntilMs : steadyMs) { return .steady }
        let by = nudgeFor(off)
        return .nudge(drift > 0 ? 1 - by : 1 + by)
    }

    /** How big a nudge [off] ms gets: 1 % up to 50 ms, 2 % up to 100, else 3 %. */
    public static func nudgeFor(_ off: Int64) -> Float {
        if off <= 50 { return nudgeStep }
        if off <= 100 { return 2 * nudgeStep }
        return nudge
    }

    /** Further off than this (ms) is a jump. */
    public static func jumpPast(_ parts: Bool) -> Int64 { parts ? jumpPartsMs : jumpMs }

    /** The jump's lead, learned: [drift] is how far off the player was at the first check after a jump (positive: ahead). */
    public static func learn(_ lead: Int64, _ drift: Int64) -> Int64 {
        if abs(drift) <= steadyMs { return lead }
        if abs(drift) > mostLeadMs { return lead } // a reading that far off isn't the jump's doing (it stalled since)
        return min(max(lead - drift, 0), mostLeadMs)
    }
}

// MARK: - the party's calls

extension Rms {
    /** The party on the server now (on false: none). */
    public func party() async throws -> PartyState { PartyState.from(try await get("/api/party"), id) }

    /** Starts a party (you host it; [everyoneControls]: everyone may play, pause and skip). 409: one is on already. */
    public func startParty(everyoneControls: Bool) async throws -> PartyState {
        PartyState.from(try await post("/api/party/start", ["everyone_controls": .bool(everyoneControls)]), id)
    }

    public func addToParty(_ song: Int64) async throws -> PartyState {
        PartyState.from(try await post("/api/party/add", ["song": .number(Double(song))]), id)
    }

    /** play, pause, skip, seek (position_ms), reorder (entry, to), remove (entry), allow (everyone). */
    public func control(_ action: String, _ extra: [String: JSON] = [:]) async throws -> PartyState {
        PartyState.from(try await post("/api/party/control", extra.merging(["action": .string(action)]) { $1 }), id)
    }

    public func react(_ emoji: String) async throws -> PartyState {
        PartyState.from(try await post("/api/party/react", ["emoji": .string(emoji)]), id)
    }

    public func endParty() async throws -> PartyState { PartyState.from(try await post("/api/party/end", [:]), id) }

    /** The party's WebSocket: its whole state on every change (`?t=` carries the key: a WebSocket can't always take a header). */
    public func partySocket() -> URL? {
        let http = withKey(file("/api/party/ws"))
        let ws = http.hasPrefix("https://") ? "wss://" + http.dropFirst(8) : http.hasPrefix("http://") ? "ws://" + http.dropFirst(7) : Substring(http)
        return URL(string: String(ws))
    }
}
