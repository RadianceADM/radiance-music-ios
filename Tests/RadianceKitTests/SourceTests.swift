import Foundation
import XCTest
@testable import RadianceKit

/** Covers at the size they're shown (android#36; owner, 2026-11-08: "ang low quality ng album art"). */
final class ArtTests: XCTestCase {
    let search = "https://yt3.googleusercontent.com/i1qCCS4BbP6z11E08FkQg6fN-83Uj4fQg4bmBsD2E6SvGQ3RW7nXxpQ3hmcSlI5Ipek10H7R4BjV5mAY=w120-h120-l90-rj"
    var base: String { String(search.split(separator: "=").first!) }

    func testBigForNowPlayingAndStories() { XCTAssertEqual(Art.sized(search, Art.big), "\(base)=w1200-h1200-l90-rj") }

    func testRoundedUpToASize() {
        XCTAssertEqual(Art.sized(search, 100), "\(base)=w120-h120-l90-rj")
        XCTAssertEqual(Art.sized(search, 132), "\(base)=w226-h226-l90-rj")
        XCTAssertEqual(Art.sized(search, 420), "\(base)=w544-h544-l90-rj")
        XCTAssertEqual(Art.sized(search, 3000), "\(base)=w1200-h1200-l90-rj")
    }

    func testOtherSizeForms() {
        XCTAssertEqual(Art.sized("https://lh3.googleusercontent.com/abc=s120-c-k-c0x00ffffff-no-rj", 500), "https://lh3.googleusercontent.com/abc=w544-h544-l90-rj")
        XCTAssertEqual(Art.sized("https://lh3.googleusercontent.com/abc", 500), "https://lh3.googleusercontent.com/abc=w544-h544-l90-rj")
    }

    func testOtherAddressesAsTheyAre() {
        for url in ["https://archive.org/services/img/some-album", "https://i.ytimg.com/vi/abc/hqdefault.jpg", "https://bassi.example/files/song.jpg", ""] {
            XCTAssertEqual(Art.sized(url, Art.big), url)
            XCTAssertFalse(Art.grows(url))
        }
    }

    func testAPicturesSize() {
        var png = [UInt8](repeating: 0, count: 32)
        png[0...3] = [0x89, 0x50, 0x4E, 0x47]
        png[16...23] = [0, 0, 4, 0xB0, 0, 0, 2, 0x58] // 1200 × 600
        XCTAssertTrue(ImageSize.of(Data(png))! == (1200, 600))
        // a JPEG: start, an APP0 segment, then the frame (SOF0) with height 120 and width 160
        let jpg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00, 0xFF, 0xC0, 0x00, 0x11, 0x08, 0x00, 0x78, 0x00, 0xA0, 0x03, 0, 0, 0, 0, 0, 0, 0]
        XCTAssertTrue(ImageSize.of(Data(jpg))! == (160, 120))
        XCTAssertNil(ImageSize.of(Data([1, 2, 3])))
    }
}

/** Deezer's answers, as they came on 2026-11-08 (android#38). */
final class GenresTests: XCTestCase {
    let search = JSON.parse("""
    {"data":[
        {"title":"Headshots","artist":{"name":"Lilwaddy"},"album":{"id":469914725,"title":"Who Is He"}},
        {"title":"Headshot","artist":{"name":"Lil Tjay"},"album":{"id":218804652,"title":"Destined 2 Win"}}
    ]}
    """)!

    func testTheSameArtistsAlbumWithItsTitle() {
        let p = Genres.pick(search, "Lil Tjay")!
        XCTAssertEqual(p.0, 218804652)
        XCTAssertEqual(p.1, "Destined 2 Win")
    }

    func testElseTheFirstHitWithoutAnAlbum() {
        let p = Genres.pick(search, "Someone Else")!
        XCTAssertEqual(p.0, 469914725)
        XCTAssertNil(p.1)
    }

    func testNoHits() { XCTAssertNil(Genres.pick(JSON.parse(#"{"data":[]}"#)!, "Lil Tjay")) }

    func testTheAlbumsGenres() {
        XCTAssertEqual(Genres.genresOf(JSON.parse(#"{"title":"Destined 2 Win","genres":{"data":[{"id":116,"name":"Rap/Hip Hop"},{"id":132,"name":"Pop"}]}}"#)!), ["Rap/Hip Hop", "Pop"])
        XCTAssertEqual(Genres.genresOf(JSON.parse(#"{"title":"X"}"#)!), [])
    }
}

/** YouTube Music's answers as they came on 2026-11-09 (search, suggestions, Up next) and the player's. */
final class YouTubeTests: XCTestCase {
    func testSearchGivesSongsWithArtistAlbumAndLength() throws {
        let songs = YouTube.songs(JSON.parse(try sample("yt-search.json"))!)
        XCTAssertGreaterThan(songs.count, 3)
        let first = songs[0]
        XCTAssertEqual(first.id, "XqJosdWocto")
        XCTAssertEqual(first.title, "Moonlight")
        XCTAssertEqual(first.artist, "Kali Uchis")
        XCTAssertEqual(first.album, "Red Moon In Venus")
        XCTAssertEqual(first.seconds, 188)
        XCTAssertTrue(first.art.hasSuffix("=w120-h120-l90-rj"), first.art) // the biggest offered
        XCTAssertEqual(first.format, "AAC")
        XCTAssertEqual(Set(songs.map(\.id)).count, songs.count) // each once
        XCTAssertTrue(songs.allSatisfy { !$0.artist.isEmpty && !$0.title.isEmpty && $0.seconds > 0 })
    }

    func testSuggestions() throws {
        XCTAssertEqual(Array(YouTube.suggestionsIn(JSON.parse(try sample("yt-suggest.json"))!).prefix(2)), ["moonlight", "moonlight over paris"])
    }

    func testUpNext() throws {
        let next = JSON.parse(try sample("yt-next.json"))!
        let songs = next.collect("playlistPanelVideoRenderer").compactMap(YouTube.upNext)
        XCTAssertGreaterThan(songs.count, 5)
        XCTAssertTrue(songs.allSatisfy { !$0.artist.contains("•") && $0.seconds > 0 })
    }

    // one item of YouTube Music's "Up next" (a playlistPanelVideoRenderer), as /next sends it (Android's UpNextTest)
    func testAnUpNextItemIsASong() {
        let item = JSON.parse("""
        {"videoId":"abc123XYZ_-",
         "title":{"runs":[{"text":"Come Inside Of My Heart"}]},
         "longBylineText":{"runs":[{"text":"IV OF SPADES"},{"text":" • "},{"text":"CLAPCLAPCLAP!"},{"text":" • "},{"text":"2019"}]},
         "lengthText":{"runs":[{"text":"4:21"}]},
         "thumbnail":{"thumbnails":[{"url":"https://lh3.googleusercontent.com/x=w60-h60-l90-rj","width":60,"height":60},
                                    {"url":"https://lh3.googleusercontent.com/x=w120-h120-l90-rj","width":120,"height":120}]}}
        """)!
        let t = YouTube.upNext(item)!
        XCTAssertEqual(t.id, "abc123XYZ_-")
        XCTAssertEqual(t.title, "Come Inside Of My Heart")
        XCTAssertEqual(t.artist, "IV OF SPADES")
        XCTAssertEqual(t.seconds, 261)
        XCTAssertEqual(t.art, "https://lh3.googleusercontent.com/x=w544-h544-l90-rj")
        XCTAssertEqual(t.key, "yt:abc123XYZ_-")
        XCTAssertNil(YouTube.upNext(JSON.parse(#"{"title":{"runs":[{"text":"x"}]}}"#)!))
        XCTAssertNil(YouTube.upNext(JSON.parse(#"{"videoId":"v"}"#)!))
    }
}

/** The player's answer, read (no network): the best AAC stream, and YouTube's "no" in plain words. */
final class StreamTests: XCTestCase {
    func testThePlayersBestAACStream() throws {
        let ok = JSON.parse("""
        {"playabilityStatus":{"status":"OK"},"streamingData":{"adaptiveFormats":[
          {"itag":251,"mimeType":"audio/webm; codecs=\\"opus\\"","bitrate":136544,"url":"https://rr1.googlevideo.com/251"},
          {"itag":139,"mimeType":"audio/mp4; codecs=\\"mp4a.40.5\\"","bitrate":50152,"url":"https://rr1.googlevideo.com/139"},
          {"itag":140,"mimeType":"audio/mp4; codecs=\\"mp4a.40.2\\"","bitrate":130677,"averageBitrate":129500,"contentLength":"3449447","url":"https://rr1.googlevideo.com/140"},
          {"itag":137,"mimeType":"video/mp4","bitrate":4000000,"url":"https://rr1.googlevideo.com/137"}]}}
        """)!
        let s = try YouTube.stream(ok, userAgent: "UA")
        XCTAssertEqual(s.url, "https://rr1.googlevideo.com/140") // AAC, the best of it (never Opus: the iPhone can't play WebM)
        XCTAssertEqual(s.ext, "m4a")
        XCTAssertEqual(s.size, 3449447)
        XCTAssertEqual(s.kbps, 129)
    }

    func testWhyYouTubeSaidNoInPlainWords() {
        func why(_ status: String, _ reason: String) -> String {
            do { _ = try YouTube.stream(JSON.parse(#"{"playabilityStatus":{"status":"\#(status)","reason":"\#(reason)"}}"#)!, userAgent: ""); return "" }
            catch { return Errors.say(error) }
        }
        XCTAssertEqual(why("LOGIN_REQUIRED", "Sign in to confirm you’re not a bot"), Errors.robot)
        XCTAssertEqual(why("UNPLAYABLE", "The uploader has not made this video available in your country"), Errors.country)
        XCTAssertEqual(why("ERROR", "Video unavailable"), Errors.unavailable)
        XCTAssertEqual(why("LOGIN_REQUIRED", "This video may be inappropriate for some users. Sign in to confirm your age"), Errors.adults)
    }
}

final class LyricsTests: XCTestCase {
    func testTimedLinesEachEndWhereTheNextStarts() {
        let lines = LyricsFinder.parseLrc("[ar: Maki]\n[00:12.50]First\n[00:15.00][01:00.00]Chorus\n[00:20.25]\nnot timed")
        XCTAssertEqual(lines, [Line(12.5, 15, "First"), Line(15, 20.25, "Chorus"), Line(20.25, 60, "♪"), Line(60, 65, "Chorus")])
        XCTAssertEqual(LyricsFinder.fromFile("just words"), .plain("just words"))
        XCTAssertEqual(LyricsFinder.fromFile("  \n"), .none)
    }

    func testWrittenAsLrcAndReadBack() {
        let l = Lyrics.timed([Line(5, 10, "One"), Line(65.5, 70, "Two")])
        XCTAssertEqual(l.file(), "[00:05.00]One\n[01:05.50]Two")
        XCTAssertEqual(LyricsFinder.fromFile(l.file()!), .timed([Line(5, 65.5, "One"), Line(65.5, 70.5, "Two")]))
    }

    // someone once filed Young Greatness's "Moolah" under SCOOP DOGG's: another artist's lyrics are turned away
    func testAnotherArtistsLyricsAreRefused() {
        let t = Track(source: .youtube, id: "m", title: "Moolah", artist: "Young Greatness")
        XCTAssertTrue(LyricsFinder.byThem(t, JSON.parse(#"{"artistName":"Young Greatness","syncedLyrics":"[00:01.00]x"}"#)!))
        XCTAssertFalse(LyricsFinder.byThem(t, JSON.parse(#"{"artistName":"SCOOP DOGG","syncedLyrics":"[00:01.00]x"}"#)!))
        XCTAssertFalse(LyricsFinder.byThem(t, JSON.parse(#"{"artistName":"Young Greatness","plainLyrics":"[ar: SCOOP DOGG]\nwords"}"#)!))
        XCTAssertTrue(LyricsFinder.byThem(Track(source: .youtube, id: "x", title: "T", artist: "Al James & Muric"), JSON.parse(#"{"artistName":"Muric"}"#)!))
    }

    func testArchiveFiles() {
        let meta = JSON.parse("""
        {"metadata":{"title":"Live 1970","creator":"Grateful Dead"},
         "files":[{"name":"gd70/d1t01.flac","format":"Flac","title":"Casey Jones","length":"4:05"},
                  {"name":"d1t02_Uncle_Johns_Band.flac","format":"24bit Flac","length":"301.2"},
                  {"name":"d1t01.mp3","format":"VBR MP3"}]}
        """)!
        let t = Archive.tracks("gd1970", meta)
        XCTAssertEqual(t.count, 2)
        XCTAssertEqual(t[0].id, "https://archive.org/download/gd1970/gd70/d1t01.flac")
        XCTAssertEqual(t[0].artist, "Grateful Dead")
        XCTAssertEqual(t[0].album, "Live 1970")
        XCTAssertEqual(t[0].seconds, 245)
        XCTAssertEqual(t[1].title, "d1t02 Uncle Johns Band")
        XCTAssertEqual(t[1].format, "24-bit FLAC")
        XCTAssertEqual(t[1].seconds, 301)
        XCTAssertEqual(Archive.encodePath("a b/ñ.flac"), "a%20b/%C3%B1.flac")
    }

    func testPlainWords() {
        XCTAssertEqual(Errors.say(URLError(.notConnectedToInternet)), Errors.offline)
        XCTAssertEqual(Errors.say(URLError(.timedOut)), Errors.slow)
        XCTAssertEqual(Errors.say(URLError(.timedOut), online: false), Errors.offline)
        XCTAssertEqual(Errors.say(Plain("My own words.", "HTTP 500")), "My own words.")
        XCTAssertEqual(Errors.say(CancellationError()), Errors.stopped)
    }
}
