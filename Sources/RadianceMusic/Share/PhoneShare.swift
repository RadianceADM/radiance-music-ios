import Foundation
import RadianceKit

/**
 * This iPhone's side of the wire (Android's share/PhoneShare.kt): what it offers (your saved liked songs, with their
 * parts, lyrics and cover) and where songs from another device land (Liked Songs: the song in Files → Radiance Music,
 * its parts, lyrics and cover where the app keeps them). What's here already is never asked for again.
 */
struct PhoneOffer: Wire.Offer {
    let songs: [(Track, [String: URL])]

    @MainActor
    init(_ app: AppModel, only: [Track]? = nil) {
        var out: [(Track, [String: URL])] = []
        for t in (only ?? app.library.liked).map(app.library.best) {
            guard let f = app.paths.file(t.file), f.isFileURL, FileManager.default.fileExists(atPath: f.path) else { continue }
            var files: [String: URL] = ["song": f]
            if let c = Saver.keptCover(app.paths, t) { files["cover"] = c }
            let l = Saver.lyricsFile(app.paths, t)
            if FileManager.default.fileExists(atPath: l.path) { files["lyrics"] = l }
            for (k, u) in app.mixer.partsOf(t) where Wire.kinds.contains(k) { files[k] = u }
            out.append((t, files))
        }
        songs = out
    }

    func items() -> [Wire.Item] {
        songs.map { t, files in
            var track = t.json
            if case .object(var o) = track { o["file"] = .null; track = .object(o) } // its place here means nothing there
            let info = files.mapValues { u in
                Wire.FileInfo(name: u.lastPathComponent, size: (try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int64) ?? 0)
            }
            return Wire.Item(key: t.key, track: track, files: info)
        }
    }

    func open(_ key: String, _ kind: String) -> URL? { songs.first { $0.0.key == key }?.1[kind] }
}

struct PhoneStore: Wire.Store {
    let app: AppModel

    func have(_ item: Wire.Item) async -> Set<String> {
        await MainActor.run {
            var have = Set<String>()
            guard let t = Track.from(json: item.track) else { return have }
            let best = app.library.best(t)
            if let f = app.paths.file(best.file), f.isFileURL, FileManager.default.fileExists(atPath: f.path) { have.insert("song") }
            if Saver.keptCover(app.paths, t) != nil { have.insert("cover") }
            if FileManager.default.fileExists(atPath: Saver.lyricsFile(app.paths, t).path) { have.insert("lyrics") }
            for k in app.mixer.partsOf(t).keys { have.insert(k) }
            return have
        }
    }

    func write(_ item: Wire.Item, _ kind: String, _ file: URL) async throws {
        try await MainActor.run {
            guard let t = Track.from(json: item.track) else { throw Plain("That song's details didn't come.") }
            let fm = FileManager.default
            let ext = (item.files[kind]?.name.split(separator: ".").last.map(String.init) ?? "m4a").lowercased()
            switch kind {
            case "song":
                let dest = Saver.place(app.paths, Saver.name(t), ext)
                try fm.moveItem(at: file, to: dest)
                var now = app.library.best(t)
                now.file = app.paths.name(of: dest)
                if app.library.isLiked(now.key) { app.library.update(now) } else { app.library.like(now) }
            case "cover":
                let dest = Saver.coverFile(app.paths, t)
                try? fm.removeItem(at: dest)
                try fm.moveItem(at: file, to: dest)
                Saver.coverKept(t.key)
            case "lyrics":
                let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
                let lyrics = ext == "yaml" || ext == "yml" ? Import.lyricsfile(text) : LyricsFinder.fromFile(text)
                if let out = lyrics?.file() { try out.write(to: Saver.lyricsFile(app.paths, t), atomically: true, encoding: .utf8) }
            default:
                // a part: kept with the song's other parts
                let dir = Splits.dir(app.paths, t.key)
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                let dest = dir.appendingPathComponent("\(kind).\(ext)")
                try? fm.removeItem(at: dest)
                try fm.moveItem(at: file, to: dest)
            }
        }
    }

    func done(_ item: Wire.Item) async {
        await MainActor.run {
            guard let t = Track.from(json: item.track) else { return }
            if !app.library.isLiked(t.key) { app.library.like(t) }
            app.mixer.recheck()
        }
    }
}
