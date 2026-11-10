import XCTest
@testable import RadianceKit

/** The party's clock: the offset from pings, where the song is, and staying in step (Android's PartyClockTest). */
final class PartyClockTests: XCTestCase {
    private func song(_ entry: Int64 = 1, ms: Int64? = 200_000) -> PartySong {
        PartySong(entry: entry, id: 7, artist: "Maki", title: "Dilaw", file: "Maki - Dilaw.opus", url: "https://s/files/Maki%20-%20Dilaw.opus", durationMs: ms)
    }

    func testTheQuickestPingWins() {
        // this phone's clock runs 5 000 ms behind the server's; the slow pings' answers came late on the way back
        let pings = [
            PartyClock.Ping(sent: 1_000, server: 6_150, received: 1_400),
            PartyClock.Ping(sent: 2_000, server: 7_010, received: 2_020), // 20 ms: the best
            PartyClock.Ping(sent: 3_000, server: 8_090, received: 3_100),
        ]
        let best = PartyClock.best(pings)!
        XCTAssertEqual(best.rtt, 20)
        XCTAssertEqual(best.offset, 5_000)
        XCTAssertNil(PartyClock.best([]))
    }

    func testWhereTheSongIs() {
        var playing = PartyState(on: true, id: "p1", song: song(), playing: true, startedAtServerMs: 10_000)
        XCTAssertEqual(PartyClock.target(playing, 94_000), 84_000)
        // a fresh song starts lead_ms after the change: before then, it's below 0
        var fresh = playing
        fresh.startedAtServerMs = 10_800
        XCTAssertEqual(PartyClock.target(fresh, 10_000), -800)
        // paused: where it stopped, whatever the time
        var paused = playing
        paused.playing = false
        paused.startedAtServerMs = nil
        paused.pausedAtMs = 61_500
        XCTAssertEqual(PartyClock.target(paused, 999_999), 61_500)
        // nothing playing, or no party
        playing.song = nil
        XCTAssertNil(PartyClock.target(playing, 94_000))
        XCTAssertNil(PartyClock.target(.off, 94_000))
    }

    func testInStepNudgedOrJumped() {
        XCTAssertEqual(PartyClock.decide(50_010, 50_000), .steady)
        XCTAssertEqual(PartyClock.decide(49_985, 50_000), .steady)
        // a little ahead: slower; a little behind: faster; the further off, the bigger the nudge (1 %, 2 %, 3 %)
        XCTAssertEqual(PartyClock.decide(50_050, 50_000), .nudge(0.99))
        XCTAssertEqual(PartyClock.decide(49_930, 50_000), .nudge(1.02))
        XCTAssertEqual(PartyClock.decide(50_400, 50_000), .nudge(0.97))
        XCTAssertEqual(PartyClock.decide(49_000, 50_000), .nudge(1.03)) // 1 s: still a nudge
        // past a second either way: a jump, landing the learned lead further on
        XCTAssertEqual(PartyClock.decide(51_001, 50_000), .jump(50_000))
        XCTAssertEqual(PartyClock.decide(48_000, 50_000, lead: 150), .jump(50_150))
        // never before the song's start
        XCTAssertEqual(PartyClock.decide(1_900, 0, lead: 0), .jump(0))
    }

    func testAJumpLearnsHowLateItLands() {
        XCTAssertEqual(PartyClock.learn(0, -180), 180)
        XCTAssertEqual(PartyClock.learn(180, 40), 140)
        XCTAssertEqual(PartyClock.learn(180, 10), 180)
        XCTAssertEqual(PartyClock.learn(30, 200), 0)
        XCTAssertEqual(PartyClock.learn(2_900, -900), PartyClock.mostLeadMs)
        XCTAssertEqual(PartyClock.learn(180, -4_000), 180)
    }

    /** A player whose clock runs 0.4 % fast, checked once a second: once in step it stays within reach, mostly within 20 ms. */
    func testADriftingPlayerStaysInStep() {
        var player = 0.0
        var speed: Float = 1
        var jumps = 0
        var worst: [Int64] = []
        for second in 1...300 {
            player += 1000.0 * 1.004 * Double(speed)
            let target = Int64(second) * 1000
            switch PartyClock.decide(Int64(player), target) {
            case .jump(let to): player = Double(to); speed = 1; jumps += 1
            case .nudge(let s): speed = s
            case .steady: speed = 1
            }
            if second > 10 { worst.append(abs(Int64(player) - target)) }
        }
        XCTAssertEqual(jumps, 0)
        XCTAssertLessThanOrEqual(worst.max()!, PartyClock.jumpMs)
        XCTAssertGreaterThan(worst.filter { $0 <= PartyClock.steadyMs + 4 }.count, worst.count / 2)
    }

    /** A late joiner, its jumps landing 250 ms late each time: after one jump it's learned, and the second lands in step. */
    func testALateJoinerCatchesUp() {
        var lead: Int64 = 0
        let target: Int64 = 95_000
        guard case .jump(let first) = PartyClock.decide(0, target, lead: lead) else { return XCTFail("a jump first") }
        var player = first - 250
        lead = PartyClock.learn(lead, player - target)
        XCTAssertEqual(lead, 250)
        guard case .jump(let second) = PartyClock.decide(0, target, lead: lead) else { return XCTFail("a jump again") }
        player = second - 250
        XCTAssertEqual(PartyClock.decide(player, target, lead: lead), .steady)
    }

    func testOneOddReadingIsntAJump() {
        XCTAssertEqual(PartyClock.decide(51_200, 50_000, farBefore: false), .nudge(0.97))
        XCTAssertEqual(PartyClock.decide(51_200, 50_000, farBefore: true), .jump(50_000))
    }

    func testAJumpSettlesBeforeAnother() {
        XCTAssertEqual(PartyClock.decide(48_700, 50_000, sinceJumpMs: 2_000), .nudge(1.03))
        XCTAssertEqual(PartyClock.decide(48_700, 50_000, sinceJumpMs: PartyClock.settleMs), .jump(50_000))
    }

    func testKaraokeIsNeverNudgedAndJumpsOnlyFarOff() {
        XCTAssertEqual(PartyClock.decide(50_050, 50_000, parts: true), .steady)
        XCTAssertEqual(PartyClock.decide(50_900, 50_000, parts: true), .steady)
        XCTAssertEqual(PartyClock.decide(51_001, 50_000, parts: true), .jump(50_000))
    }

    func testANudgeGoesOnTillItsClose() {
        XCTAssertEqual(PartyClock.decide(50_015, 50_000), .steady)
        XCTAssertEqual(PartyClock.decide(50_015, 50_000, nudging: true), .nudge(0.99))
        XCTAssertEqual(PartyClock.decide(50_008, 50_000, nudging: true), .steady)
    }

    /**
     * Readings that jump about by up to ±60 ms, a speed change landing half a second late, a clock 0.4 % off (Android's
     * phones in the owner's party, 2026-11-10): never a jump, and within 250 ms.
     */
    func testAPartyPhoneIsEasedNotJumped() {
        var rnd = JavaRandom(7)
        var player = 0.0
        var speed: Float = 1
        var pending: Float = 1
        var jumps = 0
        var lastJump: Int64 = -100_000
        var farLast = false
        var worst: [Int64] = []
        for second in 1...600 {
            player += 500.0 * 1.004 * Double(speed) + 500.0 * 1.004 * Double(pending)
            speed = pending
            let target = Int64(second) * 1000
            let read = Int64(player) + Int64(rnd.nextInt(121)) - 60
            let now = Int64(second) * 1000
            let m = PartyClock.decide(read, target, nudging: pending != 1, farBefore: farLast, sinceJumpMs: now - lastJump)
            farLast = abs(read - target) > PartyClock.jumpMs
            switch m {
            case .jump(let to): player = Double(to); pending = 1; speed = 1; jumps += 1; lastJump = now; farLast = false
            case .nudge(let s): pending = s
            case .steady: pending = 1
            }
            if second > 20 { worst.append(abs(Int64(player) - target)) }
        }
        XCTAssertEqual(jumps, 0)
        XCTAssertLessThanOrEqual(worst.max()!, 250)
    }

    /** Joining late (5 s behind): one jump, then eased; not a jump every few seconds. */
    func testALateJoinerJumpsOnce() {
        var player = 0.0
        var pending: Float = 1
        var jumps = 0
        var lastJump: Int64 = -100_000
        var farLast = true
        let lead: Int64 = 0
        for second in 1...60 {
            let target = 5_000 + Int64(second) * 1000
            player += 1000.0 * Double(pending)
            let m = PartyClock.decide(Int64(player), target, lead: lead, nudging: pending != 1, farBefore: farLast, sinceJumpMs: Int64(second) * 1000 - lastJump)
            farLast = abs(Int64(player) - target) > PartyClock.jumpMs
            switch m {
            case .jump(let to): player = Double(to) - 300; jumps += 1; lastJump = Int64(second) * 1000; farLast = false
            case .nudge(let s): pending = s
            case .steady: pending = 1
            }
        }
        XCTAssertEqual(jumps, 1)
        XCTAssertLessThanOrEqual(abs(Int64(player) - 65_000), 30)
    }

    /** The party's state as the server sends it (Android's RmsTest, thePartysStateOverItsWebSocket). */
    func testThePartysStateAsTheServerSendsIt() throws {
        let text = """
        {"type": "state", "on": true, "id": "p19a", "host": {"id": 1, "name": "Bassi"}, "everyone_controls": false,
         "song": {"entry": 3, "id": 7, "artist": "Maki", "title": "Dilaw", "file": "Maki - Dilaw.opus", "url": "/files/Maki%20-%20Dilaw.opus", "cover": "/files/Maki%20-%20Dilaw.jpg", "duration_ms": 228000, "added_by": {"id": 2, "name": "Ana"}},
         "playing": true, "started_at_server_ms": 1761900000800, "paused_at_ms": null, "position_ms": -800, "server_ms": 1761900000000, "lead_ms": 800,
         "queue": [{"entry": 4, "id": 9, "artist": "Dionela", "title": "Sining", "file": "Dionela - Sining.flac", "url": "/files/Dionela%20-%20Sining.flac", "cover": null, "duration_ms": 201000, "added_by": {"id": 1, "name": "Bassi"}}],
         "members": [{"id": 1, "name": "Bassi", "devices": 1, "host": true}, {"id": 2, "name": "Ana", "devices": 2, "host": false}],
         "reactions": [{"emoji": "🔥", "by": {"id": 2, "name": "Ana"}, "at_server_ms": 1761899990000}], "started_ms": 1761899000000, "version": 12}
        """
        let rms = Rms("https://music.example.com", token: "tok")
        let p = PartyState.from(try XCTUnwrap(JSON.parse(text)), rms.id)
        XCTAssertTrue(p.on)
        XCTAssertEqual(p.id, "p19a")
        XCTAssertEqual(p.host?.name, "Bassi")
        XCTAssertEqual(p.song?.entry, 3)
        XCTAssertEqual(p.song?.url, "https://music.example.com/files/Maki%20-%20Dilaw.opus")
        XCTAssertEqual(p.song?.cover, "https://music.example.com/files/Maki%20-%20Dilaw.jpg")
        XCTAssertEqual(p.song?.addedBy?.name, "Ana")
        XCTAssertEqual(p.startedAtServerMs, 1_761_900_000_800)
        XCTAssertNil(p.pausedAtMs)
        XCTAssertEqual(p.queue.map(\.title), ["Sining"])
        XCTAssertNil(p.queue[0].cover)
        XCTAssertEqual(p.members.map(\.devices), [1, 2])
        XCTAssertEqual(p.members.filter(\.host).map(\.name), ["Bassi"])
        XCTAssertEqual(p.reactions.first?.emoji, "🔥")
        XCTAssertEqual(p.version, 12)
        // a song in the player, from that server
        XCTAssertEqual(p.song?.track().source, .server)
        XCTAssertEqual(p.song?.track().seconds, 228)
        // no party: off
        XCTAssertFalse(PartyState.from(try XCTUnwrap(JSON.parse(#"{"on": false}"#)), rms.id).on)
    }

    func testThePartysSocketCarriesTheKey() {
        XCTAssertEqual(Rms("https://music.example.com", token: "tok").partySocket()?.absoluteString, "wss://music.example.com/api/party/ws?t=tok")
        XCTAssertEqual(Rms("http://203.0.113.5:8080", token: "k").partySocket()?.absoluteString, "ws://203.0.113.5:8080/api/party/ws?t=k")
    }
}

/** java.util.Random, so the jitter test reads the same numbers as Android's. */
struct JavaRandom {
    private var seed: UInt64
    init(_ seed: Int64) { self.seed = (UInt64(bitPattern: seed) ^ 0x5DEECE66D) & ((1 << 48) - 1) }

    private mutating func next(_ bits: Int) -> Int32 {
        seed = (seed &* 0x5DEECE66D &+ 0xB) & ((1 << 48) - 1)
        return Int32(truncatingIfNeeded: Int64(seed >> UInt64(48 - bits)))
    }

    mutating func nextInt(_ bound: Int32) -> Int32 {
        var r = next(31)
        let m = bound - 1
        if bound & m == 0 { return Int32(truncatingIfNeeded: (Int64(bound) * Int64(r)) >> 31) }
        var u = r
        while true {
            r = u % bound
            if u &- r &+ m >= 0 { break }
            u = next(31)
        }
        return r
    }
}
