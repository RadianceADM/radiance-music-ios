import AVFoundation
import Network
import RadianceKit
import SwiftUI
import UIKit

/** A short message at the bottom (Android's Notice), maybe with one thing to do about it. */
struct Notice: Identifiable, Equatable {
    let id = UUID()
    let words: String
    let actionLabel: String?
    let action: (() -> Void)?
    static func == (a: Notice, b: Notice) -> Bool { a.id == b.id }
}

/** Everything the screens share (Android's App): your library, your servers, the player, what to tell you. */
@MainActor
@Observable
final class AppModel {
    let paths = Paths.app()
    let library: Library
    let servers: Servers
    let covers: Covers
    @ObservationIgnored private var hub: PlayerHub?
    var player: PlayerHub { hub! }
    /** Songs being saved now (their keys) and how far, 0-1. */
    private(set) var saving: [String: Double] = [:]
    private(set) var notice: Notice?
    /** The iPhone has internet now. */
    private(set) var online = true
    /** The look: Stone (warm greys) or True Black. */
    var stone: Bool = UserDefaults.standard.bool(forKey: "look.stone") {
        didSet { UserDefaults.standard.set(stone, forKey: "look.stone") }
    }

    @ObservationIgnored private let monitor = NWPathMonitor()

    /**
     * For checking on the iPhone from the laptop (`pymobiledevice3 developer dvt launch --env RM_SEARCH=…`): a search
     * to run (RM_SEARCH), the result to play (RM_PLAY, from 0), a screen to open (RM_OPEN: nowplaying, settings,
     * library), a liked song to play (RM_PLAY_LIKED, from 0). Nothing happens without them.
     */
    @ObservationIgnored let test = ProcessInfo.processInfo.environment

    init() {
        URLCache.shared = URLCache(memoryCapacity: 32 << 20, diskCapacity: 300 << 20)
        library = Library(dir: paths.support)
        servers = Servers(dir: paths.support)
        covers = Covers(paths: paths)
        covers.servers = servers
        hub = PlayerHub(app: self)
        monitor.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let was = self.online
                self.online = up
                if up && !was { self.backOnline() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "radiance.online"))
        Task { await servers.refresh(online: online) }
    }

    func tell(_ words: String, action: (String, () -> Void)? = nil) {
        let n = Notice(words: words, actionLabel: action?.0, action: action?.1)
        notice = n
        Task {
            try? await Task.sleep(for: .seconds(n.action == nil ? 4 : 7))
            if notice == n { notice = nil }
        }
    }

    func dismissNotice() { notice = nil }

    // MARK: - like it, save it

    func isLiked(_ t: Track) -> Bool { library.isLiked(t.key) }

    func toggleLike(_ t: Track) {
        if library.isLiked(t.key) {
            library.unlike(t)
            tell("Removed “\(t.title)” from Liked Songs.")
        } else {
            library.like(t)
            save(t)
            fillGenres()
        }
    }

    /** Saved in the background (one song at a time, as Android does). */
    func save(_ t: Track) {
        Task { _ = await saveNow(t) }
    }

    @ObservationIgnored private var queueOfSaves: Task<Void, Never>?

    /**
     * A liked song saved on the iPhone with its cover and lyrics (Documents/Radiance Music, seen in Files): a joined
     * server's copy when it has one (owner, 2026-11-09, for every app), else from where it's from. Saved or not.
     */
    @discardableResult
    func saveNow(_ t: Track) async -> Bool {
        // one at a time: each waits for the one before
        let before = queueOfSaves
        let mine = Task { @MainActor in
            await before?.value
            await self.saveOne(t)
        }
        queueOfSaves = Task { await mine.value }
        await mine.value
        return library.best(t).file.map { paths.file($0).map { FileManager.default.fileExists(atPath: $0.path) } ?? false } ?? false
    }

    private func saveOne(_ t0: Track) async {
        let t = library.best(t0)
        if let f = paths.file(t.file), FileManager.default.fileExists(atPath: f.path) {
            try? await Saver.cover(paths, t)
            _ = await Saver.lyrics(paths, t)
            return
        }
        guard saving[t.key] == nil else { return }
        saving[t.key] = 0
        defer { saving[t.key] = nil }
        do {
            var song = t
            song.file = nil
            if t.source != .server, let (_, copy) = await servers.copy(of: t) {
                let ext = (copy.file.split(separator: ".").last.map(String.init) ?? "m4a").lowercased()
                let f = Saver.place(paths, Saver.name(t), ext)
                let key = t.key
                try await Http.download(servers.sign(copy.url), to: f) { p in Task { @MainActor in self.saving[key] = p } }
                song.file = paths.name(of: f)
            }
            let key = t.key
            let saved = try await Saver.save(paths, song, progress: { p in Task { @MainActor in self.saving[key] = p } })
            if library.isLiked(saved.key) { library.update(saved) }
            player.refresh(saved)
            Saver.coverKept(saved.key)
        } catch {
            if !online || Errors.network(error) {
                if !toldOffline { tell("You're offline. Liked songs are saved when you're back online.") }
                toldOffline = true
            } else {
                let why = (error as? Refused)?.words ?? Errors.say(error, online: online)
                tell("Couldn't save “\(t.title)”. \(why)", action: ("Retry", { [weak self] in self?.save(t) }))
            }
        }
    }

    @ObservationIgnored private var toldOffline = false

    // MARK: - by themselves (Android's App: at start, and back online)

    /** What it's doing in the background ("Bringing back your saved songs · 3 of 10"). */
    private(set) var status: String?

    @ObservationIgnored private var started = false

    func startUp() {
        guard !started else { return }
        started = true
        if Import.waiting(paths) { importLibrary() } else { findSaved(auto: true) }
        saveMissing()
        sharpenCovers()
        fillGenres()
    }

    /** Back online: what waited for the internet goes on. */
    private func backOnline() {
        toldOffline = false
        saveMissing()
        sharpenCovers()
        fillGenres()
        Task { await servers.refresh(online: online) }
    }

    /** Your library from the computer, read into Liked Songs (once it's in Documents/Library; see Import). */
    func importLibrary() {
        Task {
            do {
                let n = try Import.run(paths, library)
                tell("Your library from the computer: \(n) songs in Liked Songs.")
                fillGenres()
            } catch {
                tell("Couldn't read your library. \(Errors.say(error, online: online))", action: ("Retry", { [weak self] in self?.importLibrary() }))
            }
        }
    }

    @ObservationIgnored private var finding: Task<Void, Never>?

    /**
     * Songs in Documents/Radiance Music back into Liked Songs (see Found): by itself each time the app opens ([auto]),
     * with nothing to do for you, or from Settings any time.
     */
    func findSaved(auto: Bool) {
        if finding != nil { return }
        finding = Task {
            defer { finding = nil; status = nil }
            let (back, of) = await Found.run(paths, library, everything: !auto, length: { u in
                let d = try? await AVURLAsset(url: u).load(.duration)
                return d.map { Int($0.seconds.isFinite ? $0.seconds : 0) } ?? 0
            }, say: { [weak self] done, of in if of > 0 { self?.status = "Bringing back your saved songs · \(done) of \(of)" } })
            if of == 0 { if !auto { tell("All the songs in Files → Radiance Music are in Liked Songs.") } }
            else if back == of { tell("\(back) songs from Files → Radiance Music are back in Liked Songs.") }
            else if back > 0 || !auto { tell("\(back) of \(of) songs from Files → Radiance Music are back in Liked Songs. The rest come back by themselves later.") }
            if back > 0 { fillGenres() }
        }
    }

    @ObservationIgnored private var missing: Task<Void, Never>?

    /** Liked songs not saved yet (liked offline, or on another device): saved now, one at a time. */
    func saveMissing() {
        guard missing == nil, online else { return }
        missing = Task {
            defer { missing = nil }
            for t in library.liked where paths.file(t.file).map({ !FileManager.default.fileExists(atPath: $0.path) }) ?? true {
                if !online { break }
                await saveNow(t)
            }
        }
    }

    @ObservationIgnored private var sharpening: Task<Void, Never>?

    /** Liked songs' covers kept small before (YouTube Music's 120 px): fetched again big, quietly, one at a time. */
    func sharpenCovers() {
        guard sharpening == nil, online else { return }
        sharpening = Task {
            defer { sharpening = nil }
            for t in library.liked {
                let f = Saver.coverFile(paths, t)
                if FileManager.default.fileExists(atPath: f.path), Art.grows(t.art), Saver.small(f) { try? await Saver.cover(paths, t) }
            }
        }
    }

    @ObservationIgnored private var genres: Task<Void, Never>?

    /** Liked songs' genres (and an album for one that came without), from Deezer, one at a time. */
    func fillGenres() {
        guard genres == nil, online else { return }
        genres = Task {
            defer { genres = nil }
            while true {
                let todo = library.liked.filter { $0.genres == nil }
                if todo.isEmpty { break }
                var answered = 0
                for t in todo {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard let found = await Genres.lookup(t) else { continue } // couldn't ask: later
                    answered += 1
                    var now = library.best(t)
                    now.genres = found.genres
                    if now.album.isEmpty, let a = found.album { now.album = a }
                    library.update(now)
                }
                if answered == 0 { break } // nothing answered (offline): at the next start, or back online
            }
        }
    }

    /** This iPhone as a server lists it: "Apple iPhone13,2". */
    static var deviceName: String {
        var u = utsname()
        uname(&u)
        let machine = withUnsafeBytes(of: &u.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return machine.isEmpty ? "iPhone" : "Apple \(machine)"
    }
}

/**
 * Covers: the one kept on the iPhone first (android#41), else the address asked at the size it's drawn (Art.sized),
 * with this iPhone's key for a server's. Pictures fetched stay in a small memory cache; URLCache keeps them on disk.
 */
@MainActor
final class Covers {
    let paths: Paths
    weak var servers: Servers?
    private let memory = NSCache<NSString, UIImage>()

    init(paths: Paths) {
        self.paths = paths
        memory.countLimit = 300
    }

    func address(_ t: Track, px: Int) -> URL? {
        if let f = Saver.keptCover(paths, t) { return f }
        guard !t.art.isEmpty else { return nil }
        let sized = Art.sized(t.art, px)
        return URL(string: servers?.sign(sized) ?? sized)
    }

    func cached(_ t: Track, px: Int) -> UIImage? {
        guard let u = address(t, px: px) else { return nil }
        return memory.object(forKey: u.absoluteString as NSString)
    }

    func image(_ t: Track, px: Int) async -> UIImage? {
        guard let u = address(t, px: px) else { return nil }
        if let m = memory.object(forKey: u.absoluteString as NSString) { return m }
        let data: Data?
        if u.isFileURL {
            data = try? Data(contentsOf: u)
        } else {
            data = try? await URLSession.shared.data(from: u).0
        }
        guard let data, let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: u.absoluteString as NSString)
        return image
    }
}
