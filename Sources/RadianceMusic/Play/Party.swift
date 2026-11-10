import Darwin
import Foundation
import RadianceKit

/**
 * The listening party this iPhone is in (Android's server/Party.kt; owner's choice, 2026-10-31): everyone in it hears
 * the same song at the same moment. The server keeps the clock and the queue and sends every change over a WebSocket;
 * this iPhone measures its clock's offset to the server's (a few pings), plays the party's song from the server's
 * library, and checks every second where it is against where the party is (PartyClock): a small drift is eased out
 * with the speed (up to 3 %, the pitch kept), a big one is a jump. It plays on with the screen locked. Leaving goes back
 * to your own music, where it was.
 */
@MainActor
@Observable
final class Party {
    /** The party as this iPhone has it. */
    struct Now: Equatable {
        var server: Server
        var state: PartyState
        /** You, on that server. */
        var me: Person?
        /** Connected: its changes come at once. False: joining it again. */
        var linked = false
        /** Playing on this iPhone (you can stop listening here; the party goes on without you). */
        var listening = true
        /** How it's keeping time, in plain words ("In step with the party (+12 ms)"). */
        var sync = "Joining the party…"
        /** The clock's error at most (half the quickest ping's round trip), ms; nil: not measured yet. */
        var clockMs: Int64?

        var host: Bool { me != nil && state.host?.id == me?.id }
        /** You may play, pause, skip, seek and order the queue (the host, or everyone when the host allows). */
        var controls: Bool { host || state.everyoneControls }
        var hostName: String { host ? "you" : state.host?.name ?? "the host" }
    }

    /** A reaction floating up the party's screen. */
    struct Floating: Identifiable, Equatable {
        let id: Int
        let reaction: Reaction
    }

    private(set) var now: Now?
    var joined: Bool { now != nil }
    /** The party's screen is open. */
    var shown = false
    private(set) var floats: [Floating] = []

    @ObservationIgnored private unowned let app: AppModel
    @ObservationIgnored private var jobs: [Task<Void, Never>] = []
    @ObservationIgnored private var socket: URLSessionWebSocketTask?
    /** Your own music before the party, to go back to. */
    @ObservationIgnored private var before: PlayerHub.Mine?
    /** The server's clock minus this iPhone's, ms. */
    @ObservationIgnored private var offset: Int64 = 0
    /** How much further on a jump lands (the time the player takes to go on), learned. */
    @ObservationIgnored private var lead: Int64 = 0
    @ObservationIgnored private var jumpedAt: Int64 = 0
    /** When the player last jumped: none again till it settles (PartyClock.settleMs). */
    @ObservationIgnored private var lastJumpAt: Int64 = 0
    /** The last check found it further off than a jump: a second one in a row jumps. */
    @ObservationIgnored private var farLast = false
    /** The party's song in the player (its entry); loaded false: whatever comes first is loaded. */
    @ObservationIgnored private var entry: Int64?
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var starting: Task<Void, Never>?
    @ObservationIgnored private var retriedAt: Int64 = 0
    @ObservationIgnored private var lastReaction: Int64 = -1
    @ObservationIgnored private var floated = 0
    /** Each join is a new one: late answers for the last one are dropped. */
    @ObservationIgnored private var round = 0
    @ObservationIgnored private var backoff: Int64 = 1000

    init(app: AppModel) { self.app = app }

    /** This iPhone's own clock, ms (it runs on while the screen is off). */
    private func local() -> Int64 { Int64(clock_gettime_nsec_np(CLOCK_MONOTONIC) / 1_000_000) }
    private func serverNow() -> Int64 { local() + offset }

    // MARK: - joining and leaving

    /** Starts a party on [s] (you host it; [everyone]: everyone may play, pause and skip), and joins it. One on already: joins it. */
    func start(_ s: Server, everyone: Bool, then: @escaping () -> Void = {}) {
        Task {
            do {
                _ = try await s.rms.startParty(everyoneControls: everyone)
            } catch let r as Refused where r.code == 409 {
                // one at a time on a server: one's on already, so it's joined
            } catch {
                app.tell("Couldn't start a party on \(s.name). \(words(error))", action: ("Retry", { [weak self] in self?.start(s, everyone: everyone, then: then) }))
                return
            }
            join(s)
            then()
        }
    }

    /** Joins the party on [s]: its song plays here, in step with everyone's. */
    func join(_ s: Server) {
        if now?.server.base == s.base { return }
        if joined { leave(resume: false) }
        round += 1
        let r = round
        now = Now(server: s, state: PartyState(on: true), me: s.me)
        if !app.player.inParty { before = app.player.enterParty() }
        jobs.append(Task { [weak self] in await self?.clock(r) })
        jobs.append(Task { [weak self] in
            while !Task.isCancelled {
                guard let self, r == self.round else { return }
                self.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        })
        link(r)
    }

    /** Leaves the party (it goes on for the others); [resume]: back to your own music, where it was. */
    func leave(resume: Bool = true) {
        guard now != nil else { return }
        round += 1
        jobs.forEach { $0.cancel() }
        jobs.removeAll()
        starting?.cancel()
        starting = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        lead = 0
        jumpedAt = 0
        loaded = false
        entry = nil
        lastReaction = -1
        backoff = 1000
        now = nil
        floats = []
        shown = false
        if resume {
            app.player.leaveParty(before)
            before = nil
        }
    }

    // MARK: - what you do in it

    /** Listening on this iPhone, or not (the party goes on either way). */
    func listenHere(_ on: Bool) {
        now?.listening = on
        if !on { app.player.partyHold() }
        tick()
    }

    func add(_ song: Int64) { ask("add the song") { try await $0.addToParty(song) } }
    func play() { ask("play") { try await $0.control("play") } }
    func pause() { ask("pause") { try await $0.control("pause") } }
    func skip() { if now?.controls == true { ask("skip") { try await $0.control("skip") } } }

    func seek(_ ms: Int64) {
        if now?.controls == true { ask("move the song") { try await $0.control("seek", ["position_ms": .number(Double(max(ms, 0)))]) } }
    }

    /** Moves a waiting song to [to] in the queue (0: next). */
    func reorder(_ entry: Int64, to: Int) {
        ask("move the song") { try await $0.control("reorder", ["entry": .number(Double(entry)), "to": .number(Double(max(to, 0)))]) }
    }

    func remove(_ entry: Int64) { ask("take the song out") { try await $0.control("remove", ["entry": .number(Double(entry))]) } }
    /** The host lets everyone play, pause and skip, or only themselves. */
    func allow(everyone: Bool) { ask("change who controls the party") { try await $0.control("allow", ["everyone": .bool(everyone)]) } }
    func react(_ emoji: String) { ask("send the reaction") { try await $0.react(emoji) } }
    /** Ends the party for everyone (the host, or the server's owner). */
    func end() { ask("end the party") { try await $0.endParty() } }

    /** A reaction has floated away. */
    func landed(_ id: Int) { floats.removeAll { $0.id == id } }

    /** Where the party's song is now (ms into it), by the server's clock; nil: nothing playing, or the clock not set yet. */
    func position() -> Int64? {
        guard let n = now, n.clockMs != nil else { return nil }
        return PartyClock.target(n.state, serverNow())
    }

    /** [what] asked of the server; its answer is the party's state (the WebSocket brings it too). */
    private func ask(_ what: String, _ call: @escaping @Sendable (Rms) async throws -> PartyState) {
        guard let s = now?.server else { return }
        let r = round
        Task {
            do {
                let p = try await call(s.rms)
                if r == round { apply(p) }
            } catch {
                app.tell("Couldn't \(what). \(words(error))")
            }
        }
    }

    private func words(_ error: Error) -> String { (error as? Refused)?.words ?? (error as? Plain)?.words ?? Errors.say(error, online: app.online) }

    // MARK: - the server's clock

    /** A few pings to the server's clock (the quickest wins), again every minute (a phone's clock wanders). */
    private func clock(_ r: Int) async {
        while r == round, !Task.isCancelled {
            guard let s = now?.server else { return }
            var pings: [PartyClock.Ping] = []
            for _ in 0..<6 {
                let sent = local()
                if let server = try? await s.rms.time(), server > 0 { pings.append(PartyClock.Ping(sent: sent, server: server, received: local())) }
            }
            let best = PartyClock.best(pings)
            if let best, r == round {
                offset = best.offset
                now?.clockMs = max(best.rtt / 2, 1)
                tick()
            }
            try? await Task.sleep(for: .seconds(best == nil ? 5 : 60))
        }
    }

    // MARK: - the party's changes, over its WebSocket

    private func link(_ r: Int) {
        guard let s = now?.server, let url = s.rms.partySocket() else { return }
        var request = URLRequest(url: url)
        request.setValue(Http.userAgent, forHTTPHeaderField: "User-Agent")
        let task = URLSession.shared.webSocketTask(with: request)
        socket = task
        task.resume()
        jobs.append(Task { [weak self] in
            var first = true
            while !Task.isCancelled {
                let message: URLSessionWebSocketTask.Message
                do {
                    message = try await task.receive()
                } catch {
                    guard let self, r == self.round else { return }
                    return self.lost(r, s, task)
                }
                guard let self, r == self.round else { return }
                // the server sends the party's state first: it's up
                if first {
                    first = false
                    self.backoff = 1000
                    self.now?.linked = true
                }
                let text: String
                switch message {
                case .string(let t): text = t
                case .data(let d): text = String(decoding: d, as: UTF8.self)
                @unknown default: continue
                }
                guard let o = JSON.parse(text) else { continue }
                switch o["type"]?.string {
                case "state": self.apply(PartyState.from(o, s.rms.id))
                case "removed": return self.removed(s)
                default: break
                }
            }
        })
    }

    /** The connection dropped: joining again (more slowly each time), unless this iPhone was removed. */
    private func lost(_ r: Int, _ s: Server, _ task: URLSessionWebSocketTask) {
        if (task.response as? HTTPURLResponse)?.statusCode == 401 { return removed(s) }
        socket = nil
        now?.linked = false
        now?.sync = app.online ? "Lost the party: joining again…" : "You're offline: the party plays on here as it was. Joining again once you're back…"
        let wait = backoff
        backoff = min(backoff * 2, 15_000)
        jobs.append(Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(wait))
            guard let self, r == self.round else { return }
            // still joined there? (removed meanwhile: it says so)
            do {
                _ = try await s.rms.me()
            } catch let x as Refused where x.removed {
                return self.removed(s)
            } catch {}
            if r == self.round { self.link(r) }
        })
    }

    private func removed(_ s: Server) {
        app.servers.healthy(s.base, .removed(why: "This iPhone was removed from \(s.name)."))
        app.tell("This iPhone was removed from \(s.name), so it left the party. Ask its owner for a new invite.")
        leave()
    }

    /** The party's state now: the song changes, reactions float up, the player follows. */
    private func apply(_ p: PartyState) {
        guard let n = now else { return }
        // an answer older than what's here already (the WebSocket was quicker)
        if p.id == n.state.id, p.version >= 1, p.version < n.state.version { return }
        if !p.on {
            app.tell("The listening party on \(n.server.name) ended.")
            return leave()
        }
        // reactions since the last state float up (not the ones from before you came)
        let newest = p.reactions.map(\.atServerMs).max() ?? 0
        if lastReaction >= 0 {
            for x in p.reactions where x.atServerMs > lastReaction {
                floats.append(Floating(id: floated, reaction: x))
                floated += 1
            }
            if floats.count > 12 { floats.removeFirst(floats.count - 12) }
        }
        lastReaction = max(lastReaction, newest, 0)
        now?.state = p
        if !loaded || p.song?.entry != entry {
            loaded = true
            entry = p.song?.entry
            load(p)
        }
        tick()
    }

    // MARK: - keeping the player in step

    /** The party's new song into the player (it starts in time: tick). */
    private func load(_ p: PartyState) {
        starting?.cancel()
        starting = nil
        jumpedAt = 0
        lastJumpAt = 0
        farLast = false
        let song = p.song.flatMap { Servers.playable($0.file) ? $0 : nil }
        let at = now?.clockMs != nil ? max(PartyClock.target(p, serverNow()) ?? 0, 0) : 0
        app.player.partyLoad(song?.track(), at: Double(at) / 1000)
    }

    /** Once a second (and at every change): where the party is, where the player is, and what to do about it. */
    private func tick() {
        guard let n = now else { return }
        let hub = app.player
        let p = n.state
        func say(_ words: String) { if now?.sync != words { now?.sync = words } }
        if p.id == nil {
            hub.partyHold()
            return say("Joining the party…")
        }
        if n.clockMs == nil {
            hub.partyHold()
            return say("Setting the clock with \(n.server.name)…")
        }
        guard let song = p.song, let target = PartyClock.target(p, serverNow()) else {
            hub.partyHold()
            return say(p.queue.isEmpty ? "Nothing playing. Add a song: it starts at once." : "Quiet for now.")
        }
        // most of a computer's songs are Opus, which the iPhone's player doesn't open yet
        if !Servers.playable(song.file) {
            hub.partyHold()
            return say("The iPhone can't play this one yet (an Opus file). It plays on the others' phones; the next song may play here.")
        }
        if !hub.partyHasSong { load(p) }
        if !p.playing {
            hub.partyHold()
            if abs(hub.partyMs - target) > 300 { hub.partySeek(target) }
            return say("Paused by \(n.hostName).")
        }
        if !n.listening {
            hub.partyHold()
            return say("Not playing on this iPhone. Tap Listen here to join in.")
        }
        if hub.partyFailed {
            // a dropped stream: tried again every few seconds
            if local() - retriedAt > 3_000 {
                retriedAt = local()
                hub.partyRetry(at: max(target, 0))
            }
            return say("The song stopped loading. Trying again…")
        }
        if target < 0 {
            // it starts in a moment: ready at 0, started right on time
            hub.partyHold()
            if hub.partyMs > 50 { hub.partySeek(0) }
            if starting == nil {
                let r = round
                starting = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(-target))
                    guard let self, !Task.isCancelled, r == self.round else { return }
                    self.starting = nil
                    guard let st = self.now?.state, let at = PartyClock.target(st, self.serverNow()), self.now?.listening == true else { return }
                    self.app.player.partyPlay(at: max(at, 0))
                    self.jumpedAt = self.local()
                }
            }
            return say("Starting…")
        }
        if let length = song.durationMs, target > length {
            hub.partyHold()
            return say("Next song in a moment…")
        }
        if !hub.playing {
            hub.partyPlay(at: target + lead)
            hub.partySpeed(1)
            jumpedAt = local()
            lastJumpAt = jumpedAt
            return say("Catching up…")
        }
        if hub.interrupted { return say("Paused by the iPhone for a moment (a call?).") }
        if hub.partyWaiting || !hub.partySounding { return say("Loading…") }
        let at = hub.partyMs
        // the first check after a jump: how late it landed, learned for the next one
        if jumpedAt > 0, local() - jumpedAt > PartyClock.landedMs {
            lead = PartyClock.learn(lead, at - target)
            jumpedAt = 0
        }
        // karaoke on: the parts are what's heard (the player's silent), and they don't follow a nudge
        let parts = app.mixer.playsParts
        let far = abs(at - target) > PartyClock.jumpPast(parts)
        switch PartyClock.decide(at, target, lead: lead, nudging: hub.partyNudging, farBefore: farLast, sinceJumpMs: local() - lastJumpAt, parts: parts) {
        case .jump(let to):
            Log.say("party", "jumped, \(at - target) ms off\(parts ? " (karaoke)" : "")")
            hub.partySeek(to)
            hub.partySpeed(1)
            jumpedAt = local()
            lastJumpAt = jumpedAt
            farLast = false
        case .nudge(let s):
            hub.partySpeed(s)
            farLast = far
        case .steady:
            hub.partySpeed(1)
            farLast = far
        }
        let ms = at - target
        let shown = "\(ms >= 0 ? "+" : "−")\(abs(ms)) ms"
        say(abs(ms) <= 100 ? "In step with the party (\(shown))" : "Catching up (\(shown))")
    }
}
