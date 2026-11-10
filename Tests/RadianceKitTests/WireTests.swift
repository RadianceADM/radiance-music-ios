import Foundation
import XCTest
@testable import RadianceKit

/** The share wire's words, as Android's WireTest has them (the same QR works across all three apps). */
final class WireTests: XCTestCase {
    /** Gentle with Bluetooth (Android's Paced): at 3 MB a second, 1 MB moved at once waits about a third of a second. */
    func testThePaceKeepsATransferUnderItsLimit() {
        var p = Wire.Pacer()
        let mb = 1 << 20
        let limit = Int64(3 << 20)
        XCTAssertEqual(p.wait(after: mb, limit: limit, now: 0), 333_333_333)
        // a third of a second on, the next MB: two thirds in all, so a third more
        XCTAssertEqual(p.wait(after: mb, limit: limit, now: 333_333_333), 333_333_333)
        // slower than the pace: no wait
        XCTAssertEqual(p.wait(after: 1024, limit: limit, now: 900_000_000), 0)
        // no pace (no Bluetooth music): never a wait
        var free = Wire.Pacer()
        XCTAssertEqual(free.wait(after: 50 * mb, limit: 0, now: 0), 0)
    }

    func testATicketThereAndBack() {
        let t = Wire.Ticket(mode: "get", host: "192.168.1.20", port: 41234, key: "0123456789abcdef0123", name: "Bassi’s iPhone")
        XCTAssertEqual(Wire.Ticket.parse(t.uri), t)
        XCTAssertTrue(t.uri.contains("n=Bassi%E2%80%99s+iPhone")) // as Java's URLEncoder writes it
        // an Android phone's, with its Wi-Fi Direct group
        let a = Wire.Ticket.parse("radiancemusic://share?v=1&m=put&k=0123456789abcdef&p=5000&n=Samsung+SM-S928B&h=10.0.0.5&g=DIRECT-xy&w=pass+1&gh=192.168.49.1")!
        XCTAssertEqual(a.mode, "put")
        XCTAssertEqual(a.name, "Samsung SM-S928B")
        XCTAssertEqual(a.group, "DIRECT-xy")
        XCTAssertEqual(a.pass, "pass 1")
        XCTAssertEqual(a.groupHost, "192.168.49.1")
    }

    func testWhatIsntATicket() {
        XCTAssertNil(Wire.Ticket.parse("https://example.com"))
        XCTAssertNil(Wire.Ticket.parse("radiancemusic://share?v=2&m=get&k=0123456789abcdef&p=5000")) // another version
        XCTAssertNil(Wire.Ticket.parse("radiancemusic://share?v=1&m=take&k=0123456789abcdef&p=5000"))
        XCTAssertNil(Wire.Ticket.parse("radiancemusic://share?v=1&m=get&k=short&p=5000"))
        XCTAssertNil(Wire.Ticket.parse("radiancemusic://share?v=1&m=get&k=0123456789abcdef&p=70000"))
    }

    func testAnItemOnOfferNeverAMusicVideo() {
        let o = JSON.parse(#"{"key":"yt:x","track":{"title":"Dilaw"},"files":{"song":{"name":"Maki - Dilaw.m4a","size":3400000},"video":{"name":"v.mkv","size":9},"vocals":{"name":"v.ogg","size":-1}}}"#)!
        let i = Wire.Item.from(o)!
        XCTAssertEqual(Set(i.files.keys), ["song"]) // the video left off, a broken size too
        XCTAssertEqual(i.title, "Dilaw")
        XCTAssertEqual(Wire.Item.from(i.json), i)
        XCTAssertEqual(Wire.newKey().count, 32)
    }
}

/** Picking lyric lines for a story, as Android's ShareSheet tests them. */
final class LyricPickTests: XCTestCase {
    func testTapsPickLinesNextToEachOther() {
        let lengths = [20, 30, 40, 50, 60]
        var p: [Int] = []
        XCTAssertNil(LyricPick.tap(&p, 1, lengths)); XCTAssertEqual(p.sorted(), [1])
        XCTAssertNil(LyricPick.tap(&p, 2, lengths)); XCTAssertEqual(p.sorted(), [1, 2])
        XCTAssertNil(LyricPick.tap(&p, 0, lengths)); XCTAssertEqual(p.sorted(), [0, 1, 2])
        XCTAssertNil(LyricPick.tap(&p, 3, lengths)); XCTAssertEqual(p.sorted(), [0, 1, 2, 3]) // 140 characters
        XCTAssertEqual(LyricPick.tap(&p, 4, lengths), "150 characters at most")
        XCTAssertNil(LyricPick.tap(&p, 0, lengths)); XCTAssertEqual(p.sorted(), [1, 2, 3]) // an end comes off
        XCTAssertNil(LyricPick.tap(&p, 2, lengths)); XCTAssertEqual(p, [2]) // the middle: just it
        XCTAssertNil(LyricPick.tap(&p, 4, lengths)); XCTAssertEqual(p, [4]) // away: starts again
        XCTAssertEqual(LyricPick.tap(&p, 0, [200, 1, 1, 1, 1]), "That line is longer than 150 characters")
    }

    func testHoldAndSlide() {
        let lengths = [40, 40, 40, 40, 40]
        XCTAssertTrue(LyricPick.stretch(1, 3, lengths) == ([1, 2, 3], false))
        XCTAssertTrue(LyricPick.stretch(3, 0, lengths) == ([1, 2, 3], true)) // the 4th line would pass 150
    }
}
