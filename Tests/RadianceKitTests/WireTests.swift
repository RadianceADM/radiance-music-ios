import Foundation
import XCTest
@testable import RadianceKit

/** The share wire's words, as Android's WireTest has them (the same QR works across all three apps). */
final class WireTests: XCTestCase {
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
