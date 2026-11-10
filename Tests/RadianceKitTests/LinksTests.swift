import XCTest
@testable import RadianceKit

final class LinksTests: XCTestCase {
    private func track(_ source: Source, _ id: String) -> Track {
        Track(source: source, id: id, title: "Hello & Bye", artist: "Ben+Ben")
    }

    func testEachSongHasWhereToHearIt() {
        XCTAssertEqual(Links.song(track(.youtube, "abc123")), "https://music.youtube.com/watch?v=abc123")
        XCTAssertEqual(Links.song(track(.archive, "https://archive.org/download/live-1999/01 Song.flac")), "https://archive.org/details/live-1999")
        XCTAssertEqual(Links.song(track(.archive, "something else")), "something else")
        // a server's song: looked up on YouTube Music, the words written safely
        XCTAssertEqual(Links.song(track(.server, "https://my.server/api/songs/7")), "https://music.youtube.com/search?q=Ben%2BBen%20Hello%20%26%20Bye")
        XCTAssertEqual(Links.text(track(.youtube, "x")), "Hello & Bye — Ben+Ben\nhttps://music.youtube.com/watch?v=x")
    }

    func testTheEmailSaysWhichApp() {
        XCTAssertEqual(Links.mail(version: "0.1.0 (1)"), "mailto:hello@radianceph.com?subject=Radiance%20Music%200.1.0%20%281%29%20%28iPhone%29")
    }

    func testTheChangelogNewestFirstWrappedLinesJoined() {
        let text = """
        # Changelog

        ## 0.2.0

        - **Parties**: listen together,
          in step.
        - The A to Z rail.

        ## 0.1.0

        - First.
        """
        let r = Changelog.releases(text)
        XCTAssertEqual(r.map(\.version), ["0.2.0", "0.1.0"])
        XCTAssertEqual(r[0].items, ["**Parties**: listen together, in step.", "The A to Z rail."])
        XCTAssertEqual(r[1].items, ["First."])
        XCTAssertEqual(Changelog.releases(""), [])
    }
}
