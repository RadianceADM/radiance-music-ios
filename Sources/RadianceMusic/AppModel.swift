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
     * library). Nothing happens without them.
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
            Task { @MainActor in self?.online = up }
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
        }
    }

    /**
     * A liked song saved on the iPhone with its cover and lyrics (Documents/Radiance Music, seen in Files). A YouTube
     * song from a joined server's copy when it has one, else from YouTube.
     */
    func save(_ t: Track) {
        guard saving[t.key] == nil else { return }
        saving[t.key] = 0
        Task {
            defer { saving[t.key] = nil }
            do {
                var song = t
                if t.source == .youtube && t.file == nil, let (_, copy) = await servers.copy(of: t) {
                    let ext = (copy.file.split(separator: ".").last.map(String.init) ?? "m4a").lowercased()
                    let f = Saver.place(paths, Saver.name(t), ext)
                    let key = t.key
                    try await Http.download(servers.sign(copy.url), to: f) { p in Task { @MainActor in self.saving[key] = p } }
                    song.file = paths.name(of: f)
                }
                let key = t.key
                let saved = try await Saver.save(paths, song) { p in Task { @MainActor in self.saving[key] = p } }
                if library.isLiked(saved.key) { library.update(saved) }
                player.refresh(saved)
                Saver.coverKept(saved.key)
            } catch {
                let why = (error as? Refused)?.words ?? Errors.say(error, online: online)
                tell("Couldn't save “\(t.title)”. \(why)", action: ("Retry", { [weak self] in self?.save(t) }))
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
