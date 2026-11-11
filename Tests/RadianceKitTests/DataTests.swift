import Foundation
import XCTest
@testable import RadianceKit

func scratch() -> Paths {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rk-\(UUID().uuidString)")
    return Paths(support: root.appendingPathComponent("support"), documents: root.appendingPathComponent("docs"))
}

/** Albums, Artists and Genres (android#38), grouped as the computer app groups them (core/src/library.rs). */
final class ShelfTests: XCTestCase {
    func testEveryCreditedArtistHasTheSong() {
        let a = song("Lil Tjay", "Headshot (feat. Polo G & Fivio Foreign)")
        let b = song("Lil Tjay", "Calling My Phone (feat. 6LACK)")
        let g = Shelf.groups([a, b], .artists)
        XCTAssertEqual(g.map(\.name), ["6LACK", "Fivio Foreign", "Lil Tjay", "Polo G"])
        XCTAssertEqual(g.first { $0.name == "Lil Tjay" }?.songs, [a, b])
    }

    func testAlbumsWithSinglesForNone() {
        let g = Shelf.groups([song("Lil Tjay", "Headshot", album: "Destined 2 Win"), song("Lil Tjay", "Oh Well", album: "Destined 2 Win"), song("Maki", "Dilaw")], .albums)
        XCTAssertEqual(g.map(\.name), ["Destined 2 Win", Shelf.singles])
        XCTAssertEqual(g.map(\.songs.count), [2, 1])
    }

    func testGenresOtherAndStillFinding() {
        let g = Shelf.groups([song("Lil Tjay", "Headshot", genres: ["Rap/Hip Hop", "Pop"]), song("Maki", "Dilaw", genres: []), song("Ben&Ben", "Pasilyo")], .genres)
        XCTAssertEqual(g.map(\.name), [Shelf.finding, Shelf.other, "Pop", "Rap/Hip Hop"])
    }

    func testSameNameAnyCaseIsOneGroup() {
        let g = Shelf.groups([song("SB19", "Gento", album: "Pagsibol"), song("SB19", "What?", album: "PAGSIBOL")], .albums)
        XCTAssertEqual(g.count, 1)
        XCTAssertEqual(g[0].songs.count, 2)
    }

    func testGenresKeptWithTheSong() {
        let t = song("Lil Tjay", "Headshot", genres: ["Rap/Hip Hop"])
        XCTAssertEqual(Track.from(json: t.json)?.genres, ["Rap/Hip Hop"])
        XCTAssertNil(Track.from(json: song("Maki", "Dilaw").json)?.genres)
        XCTAssertEqual(Track.from(json: song("Maki", "Dilaw", genres: []).json)?.genres, [])
        XCTAssertNil(Track.from(json: JSON.parse(#"{"source":"youtube","id":"x","title":"T","artist":"A"}"#)!)?.genres)
    }
}

/**
 * Liked Songs A to Z, history, where you left off; and the covers that went missing on the owner's S24 (android#41):
 * songs imported from the computer came without a cover's address, blanking the one the phone had.
 */
@MainActor
final class LibraryTests: XCTestCase {
    let art = "https://lh3.googleusercontent.com/abc=w544-h544-l90-rj"

    func testACopyWithoutAnAddressKeepsTheOneItHad() {
        let p = scratch()
        let lib = Library(dir: p.support)
        let s = Track(source: .youtube, id: "kept1", title: "Bad Type", artist: "Shanti Dope", art: art)
        lib.like(s)
        var imported = s
        imported.art = ""
        imported.file = "Radiance Music/Shanti Dope - Bad Type.opus"
        lib.update(imported) // as the import did
        let now = lib.liked.first { $0.key == s.key }!
        XCTAssertEqual(now.art, art)
        XCTAssertEqual(now.file, "Radiance Music/Shanti Dope - Bad Type.opus")
        var fresh = s
        fresh.art = "https://lh3.googleusercontent.com/new"
        lib.update(fresh) // a real new address still goes in
        XCTAssertEqual(lib.liked.first { $0.key == s.key }?.art, "https://lh3.googleusercontent.com/new")
        XCTAssertEqual(lib.liked.first { $0.key == s.key }?.file, "Radiance Music/Shanti Dope - Bad Type.opus") // and its file stays
    }

    func testTheKeptCoverFirst() throws {
        let p = scratch()
        let t = Track(source: .youtube, id: "kept2-\(UUID().uuidString)", title: "Bad Type", artist: "Shanti Dope", art: art)
        XCTAssertNil(Saver.keptCover(p, t)) // none kept: the address is shown
        try Data([1, 2, 3]).write(to: Saver.coverFile(p, t))
        XCTAssertNil(Saver.keptCover(p, t)) // asked once: not looked at again until told
        Saver.coverKept(t.key)
        XCTAssertEqual(Saver.keptCover(p, t), Saver.coverFile(p, t))
    }

    func testLikedAToZLettersFirstAndKeptAcrossStarts() {
        let p = scratch()
        let lib = Library(dir: p.support)
        for t in ["zebra", "\"Quoted\" song", "Árbol", "123 go", "beta"] { lib.like(song("A", t)) }
        XCTAssertEqual(lib.liked.map(\.title), ["Árbol", "beta", "\"Quoted\" song", "zebra", "123 go"])
        lib.like(song("A", "beta")) // twice: once
        XCTAssertEqual(lib.liked.count, 5)
        let again = Library(dir: p.support)
        XCTAssertEqual(again.liked.map(\.title), lib.liked.map(\.title))
        again.unlike(song("A", "zebra"))
        XCTAssertFalse(Library(dir: p.support).isLiked(song("A", "zebra").key))
    }

    func testTheRailFilesEachSongUnderItsLetter() {
        let songs = Library.sortedByTitle(["zebra", "\"Quoted\" song", "Árbol", "123 go", "beta", "élan", "Bravo"].map { song("A", $0) })
        XCTAssertEqual(songs.map(Library.letter), ["A", "B", "B", "E", "Q", "Z", "#"])
        let firsts = Library.firsts(songs)
        XCTAssertEqual(firsts["B"], 1)
        XCTAssertEqual(firsts["#"], 6)
        XCTAssertNil(firsts["C"])
        // a letter with no songs jumps to the next one that has them; past the last, nothing
        XCTAssertEqual(Library.jump(firsts, Library.rail.firstIndex(of: "C")!), 3)
        XCTAssertEqual(Library.jump(firsts, Library.rail.firstIndex(of: "R")!), 5)
        XCTAssertEqual(Library.jump(firsts, Library.rail.count - 1), 6)
        XCTAssertNil(Library.jump([:], 0))
        XCTAssertNil(Library.jump(firsts, 99))
    }

    /** 2026-11-10: a split that read nothing left 557-byte parts, and the song went quiet; such parts are no parts. */
    func testAnEmptyPartIsNoPart() throws {
        let p = scratch()
        let d = Splits.dir(p, "yt:plM0zlPlRW8")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try Data(count: 557).write(to: d.appendingPathComponent("music.m4a"))
        try Data(count: 557).write(to: d.appendingPathComponent("vocals.m4a"))
        XCTAssertEqual(Splits.parts(p, "yt:plM0zlPlRW8"), [:])
        try Data(count: 3_000_000).write(to: d.appendingPathComponent("music.m4a"))
        try Data(count: 2_900_000).write(to: d.appendingPathComponent("vocals.m4a"))
        XCTAssertEqual(Set(Splits.parts(p, "yt:plM0zlPlRW8").keys), ["music", "vocals"])
    }

    /** radiance-music#77 on the iPhone: Remove from library takes the song out and deletes all it had here. */
    func testRemoveFromLibraryDeletesItsFiles() throws {
        let p = scratch()
        let lib = Library(dir: p.support)
        var t = song("Maki", "Dilaw")
        let file = p.songs.appendingPathComponent("Maki - Dilaw.m4a")
        try Data(count: 10).write(to: file)
        t.file = p.name(of: file)
        lib.like(t)
        try Data([0xFF, 0xD8]).write(to: Saver.coverFile(p, t))
        try "[00:01.00]Dilaw".write(to: Saver.lyricsFile(p, t), atomically: true, encoding: .utf8)
        let parts = Splits.dir(p, t.key)
        try FileManager.default.createDirectory(at: parts, withIntermediateDirectories: true)
        try Data(count: 20_000).write(to: parts.appendingPathComponent("vocals.m4a"))
        // one of the computer's parts, sent along with it
        let theirs = p.imports.appendingPathComponent("Maki - Dilaw.drums.m4a")
        try Data(count: 20_000).write(to: theirs)
        let list = #"{"songs":[{"key":"\#(t.key)","parts":{"drums":"Maki - Dilaw.drums.m4a"}}]}"#
        try list.write(to: p.imports.appendingPathComponent("library.json"), atomically: true, encoding: .utf8)

        Saver.remove(p, t)
        lib.remove(t)
        XCTAssertFalse(lib.isLiked(t.key))
        for f in [file, Saver.coverFile(p, t), Saver.lyricsFile(p, t), parts, theirs] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.path), f.lastPathComponent)
        }
        XCTAssertFalse(lib.unlikedFiles().contains(t.file!)) // nothing kept to find again
        XCTAssertFalse(Library(dir: p.support).isLiked(t.key))
    }

    func testUnlikedSavedFilesAreRemembered() {
        let p = scratch()
        let lib = Library(dir: p.support)
        let t = song("Maki", "Dilaw").with(file: "Radiance Music/Maki - Dilaw.m4a")
        lib.like(t)
        lib.unlike(t)
        XCTAssertEqual(Library(dir: p.support).unlikedFiles(), ["Radiance Music/Maki - Dilaw.m4a"])
        lib.like(t) // liked again: no longer left out
        XCTAssertEqual(Library(dir: p.support).unlikedFiles(), [])
    }

    func testHistoryNewestFirstAtMost300() {
        let p = scratch()
        let lib = Library(dir: p.support)
        for i in 0..<310 { lib.played(song("A", "s\(i)")) }
        lib.played(song("A", "s309")) // the same again at once: once
        XCTAssertEqual(lib.history.count, 300)
        XCTAssertEqual(lib.history.first?.title, "s309")
        XCTAssertEqual(Library(dir: p.support).history.count, 300)
    }

    func testWhereYouLeftOff() {
        let p = scratch()
        let lib = Library(dir: p.support)
        XCTAssertNil(lib.session())
        let a = song("A", "one"), b = song("B", "two")
        lib.like(b.with(file: "Radiance Music/B - two.m4a"))
        lib.saveSession(queue: [a, b], index: 1, positionMs: 61_500)
        let s = Library(dir: p.support).session()!
        XCTAssertEqual(s.queue.map(\.key), [a.key, b.key])
        XCTAssertEqual(s.queue[1].file, "Radiance Music/B - two.m4a") // the liked copy, with its file
        XCTAssertEqual(s.index, 1)
        XCTAssertEqual(s.positionMs, 61_500)
    }
}

final class FoundTests: XCTestCase {
    func yt(_ id: String, _ title: String, _ artist: String, _ seconds: Int) -> Track {
        Track(source: .youtube, id: id, title: title, artist: artist, seconds: seconds)
    }

    func testASavedNameIsItsArtistAndTitle() {
        XCTAssertTrue(Found.split("Al James - Mood (feat. Muric)") == ("Al James", "Mood (feat. Muric)"))
        // a title with " - " in it: the artist is before the first one
        XCTAssertTrue(Found.split("Baby Blood - 3 AM - Baby Blood (Official Lyric Video)") == ("Baby Blood", "3 AM - Baby Blood (Official Lyric Video)"))
        XCTAssertTrue(Found.split("Untitled") == ("", "Untitled"))
    }

    func testTheSongWithTheSameNameAndLengthIsPicked() {
        let f = Found.File(uri: "Radiance Music/Al James - PSG.m4a", name: "Al James - PSG", ext: "m4a", seconds: 201)
        let results = [yt("a", "PSG (Remix)", "Someone Else", 250), yt("b", "PSG", "Al James", 202), yt("c", "PSG", "Al James", 320)]
        XCTAssertEqual(Found.pick(f, results)?.id, "b")
    }

    func testASavedNameWithReplacedCharactersStillMatches() {
        let f = Found.File(uri: "x", name: "AC_DC - Back In Black", ext: "flac", seconds: 255)
        XCTAssertEqual(Found.pick(f, [yt("x", "Back In Black", "AC/DC", 255)])?.id, "x")
        XCTAssertEqual(Saver.name(Track(source: .youtube, id: "x", title: "Back In Black", artist: "AC/DC")), "AC_DC - Back In Black")
    }

    func testNothingLikeItIsNoMatch() {
        let f = Found.File(uri: "x", name: "HELLMERRY - Summer Crush", ext: "m4a", seconds: 180)
        XCTAssertNil(Found.pick(f, [yt("z", "Other Song", "Other Artist", 120)]))
        XCTAssertNil(Found.pick(f, []))
    }

    func testOnlySongsNotInLikedSongsComeBack() {
        let songs = [
            Found.File(uri: "Radiance Music/Maki - Dilaw.m4a", name: "Maki - Dilaw", ext: "m4a", seconds: 240), // liked: its own file
            Found.File(uri: "Radiance Music/Ben&Ben - Araw-Araw.m4a", name: "Ben&Ben - Araw-Araw", ext: "m4a", seconds: 250), // liked from the computer
            Found.File(uri: "Radiance Music/JVKE - Golden Hour.m4a", name: "JVKE - Golden Hour", ext: "m4a", seconds: 209), // liked, by its name
            Found.File(uri: "Radiance Music/Joji - Like You Do.m4a", name: "Joji - Like You Do", ext: "m4a", seconds: 240), // unliked
            Found.File(uri: "Radiance Music/IV OF SPADES - Mundo.m4a", name: "IV OF SPADES - Mundo", ext: "m4a", seconds: 300), // comes back
        ]
        let liked = [
            yt("a", "Dilaw", "Maki", 240).with(file: "Radiance Music/Maki - Dilaw.m4a"),
            yt("b", "Araw-Araw", "Ben&Ben", 250).with(file: "file:///home/bassi/Music/Radiance%20Music/Ben&Ben - Araw-Araw.m4a"),
            yt("c", "Golden Hour", "JVKE", 209).with(file: "Radiance Music/elsewhere.m4a"),
        ]
        let waiting = Found.waiting(songs, liked, ["Radiance Music/Joji - Like You Do.m4a"])
        XCTAssertEqual(waiting.map(\.name), ["IV OF SPADES - Mundo"])
    }

    func testAnUnknownLengthGoesByTheName() {
        let f = Found.File(uri: "x", name: "IV OF SPADES - Come Inside Of My Heart", ext: "m4a", seconds: 0)
        XCTAssertEqual(Found.pick(f, [yt("k", "Come Inside Of My Heart", "IV OF SPADES", 260)])?.id, "k")
    }

    func testTheSongFilesInTheFolderNotTheParts() throws {
        let p = scratch()
        for n in ["A - One.m4a", "A - One.vocals.ogg", "B - Two.flac", "notes.txt", "C - Three.m4a.part"] {
            try Data([0]).write(to: p.songs.appendingPathComponent(n))
        }
        XCTAssertEqual(Found.files(p).map(\.1.name), ["A - One", "B - Two"])
        XCTAssertEqual(Found.files(p).first?.1.uri, "Radiance Music/A - One.m4a")
    }

    func testANewSavedFileNeverOverwritesAnother() throws {
        let p = scratch()
        XCTAssertEqual(Saver.place(p, "A - One", "m4a").lastPathComponent, "A - One.m4a")
        try Data([0]).write(to: p.songs.appendingPathComponent("A - One.m4a"))
        XCTAssertEqual(Saver.place(p, "A - One", "m4a").lastPathComponent, "A - One (2).m4a")
    }
}

/** A computer's library on the iPhone (Android's Import), and the lyrics it brings. */
@MainActor
final class ImportTests: XCTestCase {
    func testTheComputersLibraryJoinsLikedSongs() throws {
        let p = scratch()
        let fm = FileManager.default
        try fm.createDirectory(at: p.imports, withIntermediateDirectories: true)
        try Data([0]).write(to: p.songs.appendingPathComponent("Maki - Dilaw.m4a"))
        try Data([0xFF, 0xD8]).write(to: p.imports.appendingPathComponent("Maki - Dilaw.jpg"))
        try "[00:01.00]Dilaw\n[00:04.00]ikaw".write(to: p.imports.appendingPathComponent("Maki - Dilaw.lrc"), atomically: true, encoding: .utf8)
        try Data(count: 600_000).write(to: p.imports.appendingPathComponent("Maki - Dilaw.vocals.ogg")) // a part with sound's size
        let list = """
        {"songs":[
          {"key":"yt:dilaw1","track":{"source":"youtube","id":"dilaw1","title":"Dilaw","artist":"Maki","album":"","seconds":240,"art":"","format":"Opus"},
           "song":"Maki - Dilaw.m4a","cover":"Maki - Dilaw.jpg","lrc":"Maki - Dilaw.lrc","parts":{"vocals":"Maki - Dilaw.vocals.ogg","drums":"missing.ogg"}},
          {"key":"yt:gone","track":{"source":"youtube","id":"gone","title":"Gone","artist":"X"},"song":"X - Gone.m4a"}
        ]}
        """
        try list.write(to: p.imports.appendingPathComponent("library.json"), atomically: true, encoding: .utf8)
        XCTAssertTrue(Import.waiting(p))
        let lib = Library(dir: p.support)
        lib.like(Track(source: .youtube, id: "dilaw1", title: "Dilaw", artist: "Maki", art: "https://lh3.googleusercontent.com/keep"))
        XCTAssertEqual(try Import.run(p, lib), 1) // the song whose file isn't here stays out
        XCTAssertFalse(Import.waiting(p))
        let t = lib.liked.first { $0.id == "dilaw1" }!
        XCTAssertEqual(t.file, "Radiance Music/Maki - Dilaw.m4a")
        XCTAssertEqual(t.art, "https://lh3.googleusercontent.com/keep") // android#41
        XCTAssertNotNil(Saver.keptCover(p, t))
        XCTAssertEqual(LyricsFinder.fromFile(try String(contentsOf: Saver.lyricsFile(p, t), encoding: .utf8)), .timed([Line(1, 4, "Dilaw"), Line(4, 9, "ikaw")]))
        XCTAssertEqual(Array(Import.parts(p, "yt:dilaw1").keys), ["vocals"]) // a part that isn't here: left out
    }

    func testALyricsfile() {
        let yaml = """
        version: 1
        lines:
          - text: "Hello, \\"world\\""
            start_ms: 1000
            end_ms: 2500
            words:
              - text: Hello
          - text: ''
            start_ms: 3000
          - text: it's 'quoted'
            start_ms: 500
            end_ms: 900
        meta:
          by: someone
        """
        XCTAssertEqual(Import.lyricsfile(yaml), .timed([Line(0.5, 0.9, "it's 'quoted'"), Line(1, 2.5, "Hello, \"world\""), Line(3, 6, "♪")]))
        XCTAssertNil(Import.lyricsfile("version: 1\n"))
    }
}
