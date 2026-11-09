import Foundation
import XCTest
@testable import RadianceKit

/** A Radiance Music Server's answers as rms makes them (the Android app's RmsTest cases). */
final class ServerTests: XCTestCase {
    /** A song as rms's library.rs song_json makes it. */
    let dilaw = """
    {"id": 7, "artist": "Maki", "title": "Dilaw", "file": "Maki - Dilaw.opus", "url": "/files/Maki%20-%20Dilaw.opus",
     "duration_ms": 228000, "split": true, "parts": ["drums", "bass", "other", "vocals", "music"], "lyrics": true, "word_times": true,
     "cover": "/files/Maki%20-%20Dilaw.jpg", "video": null,
     "files": {"song": {"name": "Maki - Dilaw.opus", "size": 3400000, "url": "/files/Maki%20-%20Dilaw.opus"},
               "drums": {"name": "Maki - Dilaw.drums.ogg", "size": 900000, "url": "/files/Maki%20-%20Dilaw.drums.ogg"}},
     "added_by": {"id": 2, "name": "Ana"}, "added_ms": 1761900000000}
    """

    func testASongOnTheServer() {
        let rms = Rms("https://music.example.com/join/X", token: "tok")
        let s = ServerSong.from(JSON.parse(dilaw)!, rms.id)!
        XCTAssertEqual(s.url, "https://music.example.com/files/Maki%20-%20Dilaw.opus")
        XCTAssertEqual(s.cover, "https://music.example.com/files/Maki%20-%20Dilaw.jpg")
        XCTAssertEqual(s.files["drums"]?.url, "https://music.example.com/files/Maki%20-%20Dilaw.drums.ogg")
        XCTAssertEqual(s.parts.count, 5)
        XCTAssertEqual(s.addedBy?.name, "Ana")
        let t = s.track()
        XCTAssertEqual(t.source, .server)
        XCTAssertEqual(t.seconds, 228)
        XCTAssertEqual(t.format, "Opus")
        XCTAssertTrue(t.key.hasPrefix("rms:"))
        XCTAssertEqual(rms.withKey(t.id), "https://music.example.com/files/Maki%20-%20Dilaw.opus?t=tok")
    }

    func testInvitesAsPastedOrScanned() {
        XCTAssertEqual(Servers.invite("Join my server: https://music.example.com/join/ABCD-EFGH-JKLM"),
                       Servers.Invite(base: "https://music.example.com", code: "ABCD-EFGH-JKLM"))
        XCTAssertEqual(Servers.invite("music.example.com/join/ABCD-EFGH")?.base, "https://music.example.com") // a name: https
        XCTAssertEqual(Servers.invite("203.0.113.5:8080/join/ABCD-EFGH")?.base, "http://203.0.113.5:8080") // a bare address: http
        XCTAssertEqual(Servers.invite("radiancemusic://join?u=https%3A%2F%2Fmusic.example.com%2Fjoin%2FWXYZ-1234")?.code, "WXYZ-1234")
        XCTAssertNil(Servers.invite("https://music.example.com/"))
        XCTAssertNil(Servers.invite("hello"))
    }

    func testAddresses() {
        XCTAssertEqual(Rms.origin("https://Music.Example.com:443/join/X"), "https://music.example.com")
        XCTAssertEqual(Rms.origin("http://10.0.0.5:8080/x"), "http://10.0.0.5:8080")
        XCTAssertNil(Rms.origin("not an address"))
        // a server given a domain: its songs keep the first address (their keys), what's fetched goes to the new one
        let s = Server(base: "https://music.example.com", token: "t", name: "Bassi's server", first: "http://10.0.0.5:8080")
        XCTAssertEqual(s.here("http://10.0.0.5:8080/files/a.opus"), "https://music.example.com/files/a.opus")
        XCTAssertEqual(s.here("https://elsewhere/files/a.opus"), "https://elsewhere/files/a.opus")
    }

    func testWhatsSaidWhenItGoesWrong() {
        func words(_ code: Int, _ body: String) -> String {
            do { _ = try Rms.answer(code, Data(body.utf8)); return "" } catch let r as Refused { return r.words } catch { return "\(error)" }
        }
        XCTAssertEqual(words(410, #"{"error": "That invite was used already."}"#), "That invite was used already.") // the server's own words
        XCTAssertEqual(words(401, ""), "This iPhone isn't joined to the server any more. Ask its owner for a new invite.")
        XCTAssertEqual(words(503, "<html>"), "The server isn't running right now, or it's starting. Try again in a minute.")
        XCTAssertEqual(words(200, "<html>"), "The server's answer didn't make sense. Is this a Radiance Music Server?")
    }

    @MainActor
    func testJoinedServersAreKeptAndSigned() {
        let dir = scratch().support
        let servers = Servers(dir: dir)
        XCTAssertTrue(servers.list.isEmpty)
        let q = SplitQueue.from(JSON.parse(#"{"jobs":[{"id":1,"song":{"id":7,"artist":"Maki","title":"Dilaw"},"state":"splitting","progress":0.4},{"id":2,"song":{"id":9},"state":"waiting"}],"splitter":{"ready":true}}"#)!)
        XCTAssertEqual(q.of(7)?.working, true)
        XCTAssertEqual(q.place(q.jobs[1]), 0)
        XCTAssertNil(servers.of("https://music.example.com/files/a.opus"))
        XCTAssertEqual(servers.sign("https://music.example.com/files/a.opus"), "https://music.example.com/files/a.opus") // not joined: as it is
    }
}

final class ServerCopyTests: XCTestCase {
    func testTheServersCopyIsTheSameSong() {
        let rms = Rms("https://music.example.com")
        func song(_ artist: String, _ title: String) -> ServerSong {
            ServerSong.from(JSON.parse(#"{"id":1,"artist":"\#(artist)","title":"\#(title)","file":"x.m4a"}"#)!, rms.id)!
        }
        let t = Track(source: .youtube, id: "v", title: "Audio (feat. Sia, Diplo & Labrinth)", artist: "LSD")
        XCTAssertTrue(Servers.same(song("LSD", "Audio (feat. Sia, Diplo & Labrinth)"), t))
        XCTAssertTrue(Servers.same(song("Lsd", "Audio (feat. Siá, Diplo & Labrinth)"), t)) // accents aside
        XCTAssertTrue(Servers.same(song("lsd", "AUDIO (FEAT. SIA, DIPLO & LABRINTH)"), t)) // case and spaces aside
        XCTAssertFalse(Servers.same(song("LSD", "Audio"), t)) // what's in brackets counts too (as Android)
        XCTAssertFalse(Servers.same(song("Maki", "Dilaw (Acoustic)"), Track(source: .youtube, id: "d", title: "Dilaw", artist: "Maki")))
        XCTAssertFalse(Servers.same(song("LSD, Sia & Diplo", "Audio (feat. Sia, Diplo & Labrinth)"), t)) // another credit
        XCTAssertFalse(Servers.same(song("Someone Else", "Audio"), t))
        XCTAssertFalse(Servers.same(song("LSD", "Genius"), t))
        XCTAssertTrue(Servers.playable("Maki - Dilaw.m4a"))
        XCTAssertFalse(Servers.playable("Maki - Dilaw.opus")) // the iPhone's player can't open Opus
    }
}
