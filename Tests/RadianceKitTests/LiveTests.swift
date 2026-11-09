import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import RadianceKit

/**
 * The real services, asked as the app asks them (RADIANCE_LIVE=1 only: they need the internet and change on their
 * own): YouTube Music's search and sound, the Internet Archive, LRCLIB, Deezer.
 */
final class LiveTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RADIANCE_LIVE"] == "1", "set RADIANCE_LIVE=1 to ask the real services")
    }

    func testYouTubeFindsAndPlaysASong() async throws {
        let found = try await YouTube.search("moonlight kali uchis")
        let t = try XCTUnwrap(found.first)
        print("found:", found.prefix(3).map { "\($0.artist) - \($0.title) [\($0.album)] \($0.seconds)s" })
        XCTAssertEqual(t.artist, "Kali Uchis")
        let s = try await YouTube.audio(t.id)
        print("stream:", s.kbps, "kbps,", s.size ?? -1, "bytes")
        XCTAssertEqual(s.ext, "m4a")
        // the first piece of it, as the player and Saver fetch it
        var req = URLRequest(url: URL(string: s.url)!)
        req.setValue("bytes=0-65535", forHTTPHeaderField: "Range")
        s.headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let (data, r) = try await Http.send(req)
        XCTAssertEqual(r.statusCode, 206)
        XCTAssertEqual(data.count, 65536)
        XCTAssertEqual(String(decoding: data[4..<8], as: UTF8.self), "ftyp") // an MP4 (.m4a)
        // and as the iPhone's player asks (its own User-Agent)
        req.setValue("AppleCoreMedia/1.0.0.22F76 (iPhone; U; CPU OS 18_5 like Mac OS X; en_us)", forHTTPHeaderField: "User-Agent")
        let (_, r2) = try await Http.send(req)
        print("as AppleCoreMedia:", r2.statusCode)
        let related = try await YouTube.related(t.id)
        print("up next:", related.count, related.prefix(3).map(\.title))
        XCTAssertGreaterThan(related.count, 5)
        let sugg = await YouTube.suggestions("moonl")
        XCTAssertFalse(sugg.isEmpty)
    }

    func testSavingASongWithItsCoverAndLyrics() async throws {
        let p = scratch()
        let results = try await YouTube.search("Maki Dilaw")
        let t = try XCTUnwrap(results.first)
        let saved = try await Saver.save(p, t)
        let f = try XCTUnwrap(p.file(saved.file))
        let size = try FileManager.default.attributesOfItem(atPath: f.path)[.size] as? Int ?? 0
        print("saved:", saved.file ?? "", size, "bytes")
        XCTAssertGreaterThan(size, 1_000_000)
        XCTAssertTrue(saved.file!.hasPrefix("Radiance Music/"))
        XCTAssertNotNil(Saver.keptCover(p, saved))
        XCTAssertFalse(Saver.small(Saver.coverFile(p, saved)))
        let lyrics = await Saver.lyrics(p, saved)
        print("lyrics:", lyrics.file()?.prefix(80) ?? "none")
    }

    func testTheArchiveLyricsAndGenres() async throws {
        let a = try await Archive.search("grateful dead casey jones")
        print("archive:", a.count, a.prefix(2).map { "\($0.title) \($0.format)" })
        XCTAssertFalse(a.isEmpty)
        let t = Track(source: .youtube, id: "x", title: "Headshot", artist: "Lil Tjay", seconds: 179)
        let g = await Genres.lookup(t)
        print("genres:", g as Any)
        XCTAssertEqual(g?.genres.isEmpty, false)
        let l = await LyricsFinder.find(Track(source: .youtube, id: "XqJosdWocto", title: "Moonlight", artist: "Kali Uchis", seconds: 188))
        if case .timed(let lines) = l { XCTAssertGreaterThan(lines.count, 10) } else { XCTFail("no timed lyrics: \(l)") }
    }
}
