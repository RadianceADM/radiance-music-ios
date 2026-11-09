import Foundation
import XCTest
@testable import RadianceKit

func sample(_ name: String) throws -> Data {
    let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Samples"))
    return try Data(contentsOf: url)
}

func song(_ artist: String, _ title: String, album: String = "", genres: [String]? = nil) -> Track {
    Track(source: .youtube, id: "\(artist)-\(title)", title: title, artist: artist, album: album, genres: genres)
}

/** Songs read and written as the computer and Android have them (the same JSON on all three). */
final class TrackTests: XCTestCase {
    func testTheComputersLikedSongsAreRead() throws {
        let list = Track.list(try sample("computer-liked.json"))
        // a song from another source and one without an id are left out
        XCTAssertEqual(list.count, 3)
        XCTAssertEqual(list[0].key, "yt:plM0zlPlRW8")
        XCTAssertEqual(list[0].genres, [])
        XCTAssertEqual(list[1].genres, ["Rap/Hip Hop"])
        XCTAssertEqual(list[2].source, .archive)
        XCTAssertEqual(list[2].key, "ia:https://archive.org/download/gd1970/d1t01.flac")
        XCTAssertNil(list[2].file) // null
        XCTAssertNil(list[2].genres) // not looked up yet
        XCTAssertEqual(list[2].seconds, 245)
        XCTAssertTrue(list[2].lossless)
    }

    func testAndroidsLikedSongsAreRead() throws {
        let list = Track.list(try sample("android-liked.json"))
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0].file, "content://media/external/audio/media/1000123")
        XCTAssertEqual(list[1].seconds, 188) // written as text: still a number
        XCTAssertEqual(list[1].genres, ["Pop", "R&B"])
        // a server's song: a short key, the same on every phone (the first 16 hex digits of its address's SHA-256)
        XCTAssertEqual(list[1].key, "rms:" + String(SHA256.hex(list[1].id).prefix(16)))
    }

    func testWrittenAndReadBackTheSame() throws {
        let t = Track(source: .youtube, id: "abc", title: "T", artist: "A", album: "Al", seconds: 61, art: "https://x/y", format: "AAC",
                      file: "Radiance Music/A - T.m4a", genres: ["Pop"])
        XCTAssertEqual(Track.list(Track.data([t])), [t])
        // nothing yet: written as null, as Android and the computer do
        let bare = Track(source: .archive, id: "u", title: "T", artist: "A")
        let text = String(decoding: Track.data([bare]), as: UTF8.self)
        XCTAssertTrue(text.contains("\"file\":null"), text)
        XCTAssertTrue(text.contains("\"genres\":null"), text)
        XCTAssertEqual(Track.list(Track.data([bare])), [bare])
    }

    func testSHA256() {
        XCTAssertEqual(SHA256.hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(SHA256.hex(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SHA256.hex(String(repeating: "a", count: 1000)), "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
    }

    // the computer app's own cases (core/src/track.rs featured_artists_count)
    func testFeaturedArtists() {
        XCTAssertEqual(song("Uncle Dags", "Tamaraw (feat. KKRAM)").artists(), ["Uncle Dags", "KKRAM"])
        XCTAssertEqual(song("Gat Putch, Icetizy & Uncle Dags", "MATIKAS (feat. Smugglaz)").artists(), ["Gat Putch", "Icetizy", "Uncle Dags", "Smugglaz"])
        XCTAssertEqual(song("SUPAFLY", "PUFF ME UP (feat. Gat Putch, Gaspari, OG CRY & Ghoti Scale)").artists().count, 5)
        XCTAssertEqual(song("Hev Abi", "Para Sa Streets").artists(), ["Hev Abi"])
        XCTAssertEqual(song("Al James & Muric", "Mood (feat. Muric)").artists(), ["Al James", "Muric"]) // named twice: once
        XCTAssertEqual(song("A", "Song (Feat. B)").artists(), ["A", "B"]) // any case
    }

    func testTextAsCompared() {
        XCTAssertEqual(fold("Ñino Café"), "Nino Cafe")
        XCTAssertEqual(plain("Héllo, World! (Remastered 2011)"), "helloworld")
        XCTAssertEqual(clock(245), "4:05")
        XCTAssertEqual(clock(-3), "0:00")
        XCTAssertEqual(splitCredit("A feat. B & C, D"), ["A", "B", "C", "D"])
        let t = Track(source: .youtube, id: "x", title: "Araw-Araw", artist: "Ben&Ben", album: "Limasawa Street")
        XCTAssertTrue(matches(t, "araw araw"))
        XCTAssertTrue(matches(t, "benben"))
        XCTAssertTrue(matches(t, "  LIMASAWA  "))
        XCTAssertFalse(matches(t, "moonlight"))
        XCTAssertEqual(t.byline(), "Ben&Ben · Limasawa Street")
    }
}
