import AVFoundation
import RadianceKit

/**
 * The Mixer (Android's play/Mixer.kt, android#20): a split song played as the whole song, as karaoke (the singing
 * down to [singing]), or as its singing only. One tap, as Apple Music Sing, no slider per part. A song has its two
 * halves (Music, Vocals) or its four parts (split on the computer or a server); four win when it has both. Karaoke
 * stays on from song to song.
 *
 * The player keeps playing the song silently and drives everything; the engine follows it, and is pulled back in
 * step only when it's really off (small differences are left alone: that pull was Android's "talon").
 */
@MainActor
@Observable
final class Mixer {
    enum Voice: String { case song, karaoke, vocalsOnly }

    static let parts = ["drums", "bass", "other", "vocals"]
    static let halves = ["music", "vocals"]
    /** A song split in six on the computer: Piano and Guitar move with Other. */
    static let extras = ["guitar", "piano"]
    /** Karaoke keeps some of the singing at first, as Apple Music Sing (owner, 2026-11-05). */
    static let guide: Float = 0.1

    private(set) var voice = Voice.song
    private(set) var singing: Float
    /** The song playing has its parts on this iPhone. */
    private(set) var available = false

    @ObservationIgnored private unowned let app: AppModel
    @ObservationIgnored private var engine: PartsEngine?
    @ObservationIgnored private var track: Track?
    @ObservationIgnored private var watch: Task<Void, Never>?

    init(app: AppModel) {
        self.app = app
        singing = UserDefaults.standard.object(forKey: "singing.level") as? Float ?? Mixer.guide
    }

    // MARK: - what the song has

    /** The song's parts here (copied from the computer, or split here); empty: none. */
    func partsOf(_ t: Track) -> [String: URL] {
        let p = Import.parts(app.paths, t.key).merging(Splits.parts(app.paths, t.key)) { $1 }
        guard let set = Mixer.setFor(Set(p.keys)) else { return [:] }
        let names = set == Mixer.parts ? set + Mixer.extras.filter { p[$0] != nil } : set
        return p.filter { names.contains($0.key) }
    }

    static func setFor(_ names: Set<String>) -> [String]? {
        if Set(parts).isSubset(of: names) { return parts }
        if Set(halves).isSubset(of: names) { return halves }
        return nil
    }

    func hasParts(_ t: Track) -> Bool { !partsOf(t).isEmpty }

    /** The parts are what's heard now (the player's own sound is down): a party doesn't nudge their speed. */
    var playsParts: Bool { engine != nil }

    /** The song's own file on the iPhone (its saved copy), if it has one the engine can play. */
    private func ownFile(_ t: Track) -> URL? {
        guard let f = app.paths.file(app.library.best(t).file), f.isFileURL, FileManager.default.fileExists(atPath: f.path), engineReads(f) else { return nil }
        return f
    }

    @ObservationIgnored private var readable: [String: Bool] = [:]

    /**
     * The engine reads [f] (AVAudioFile): not Opus inside .m4a, as the computer's songs come, which only the player
     * opens (2026-11-10: the song went quiet once split, the engine playing nothing in its place).
     */
    private func engineReads(_ f: URL) -> Bool {
        if let r = readable[f.path] { return r }
        var ok = false
        if let file = try? AVAudioFile(forReading: f), let b = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096) {
            ok = (try? file.read(into: b)) != nil && b.frameLength > 0
        }
        if !ok { Log.say("mix", "the engine can't read \(f.lastPathComponent); the player plays it") }
        readable[f.path] = ok
        return ok
    }

    /** The engine plays [t]: karaoke or the singing only, any split song with its own file here, or a saved song with effects on. */
    private func wanted(_ t: Track) -> Bool {
        if available && (voice != .song || ownFile(t) != nil) { return true }
        return !Effects.shared.neutral && ownFile(t) != nil
    }

    // MARK: - the player says

    /** Another song: the old engine goes; this one's parts are looked for. */
    func songChanged(_ t: Track?) {
        leave(quick: true)
        track = t
        available = t.map(hasParts) ?? false
    }

    /** Playing or not (the player's own sound started or stopped), and where. */
    func playingChanged(_ on: Bool, at: Double) {
        guard let t = track else { return }
        if !on { engine?.pause(); return }
        if let e = engine { if !e.running { e.play(from: at) }; return }
        if wanted(t) { engage(t, at: at) }
    }

    func seeked(to at: Double) {
        guard let e = engine, app.player.playing else { return }
        e.play(from: at)
    }

    // MARK: - you say

    func choose(_ v: Voice) {
        voice = v
        mix()
    }

    /** Karaoke's singing, as its slider moves (karaoke goes on). */
    func sing(_ level: Float) {
        singing = min(max(level, 0), 1)
        UserDefaults.standard.set(singing, forKey: "singing.level")
        if voice != .karaoke { voice = .karaoke }
        mix()
    }

    /** Low cut, high cut or reverb moved. */
    func effectsChanged() {
        engine?.apply(Effects.shared)
        if engine == nil, let t = track, wanted(t), app.player.playing { engage(t, at: app.player.exactPosition) }
    }

    /** A split just finished here: the song playing may have its parts now. */
    func recheck() {
        guard let t = track, !available else { return }
        available = hasParts(t)
        if available, engine == nil, wanted(t), app.player.playing { engage(t, at: app.player.exactPosition) }
    }

    // MARK: - underneath

    private func gains() -> [String: Float] {
        let (vocals, rest): (Float, Float) = switch voice {
        case .song: (1, 1)
        case .karaoke: (singing, 1)
        case .vocalsOnly: (1, 0)
        }
        var g: [String: Float] = [:]
        for p in Mixer.parts + Mixer.halves + Mixer.extras { g[p] = p == "vocals" ? vocals : rest }
        // the whole song: the file itself (untouched), not the parts added up
        if engine?.hasSong == true || ownFile(track ?? Track(source: .archive, id: "-", title: "", artist: "")) != nil {
            if voice == .song { g = g.mapValues { _ in 0 }; g["song"] = 1 } else { g["song"] = 0 }
        }
        if !available { g = ["song": 1] } // effects on a saved song that isn't split
        return g
    }

    private func mix() {
        guard let t = track else { return }
        if let e = engine {
            if voice == .song && !e.hasSong { return leave(quick: false) }
            e.set(gains())
        } else if wanted(t), app.player.playing {
            engage(t, at: app.player.exactPosition)
        }
    }

    private func engage(_ t: Track, at: Double) {
        let parts = available ? partsOf(t) : [:]
        do {
            let own = ownFile(t)
            let e = try PartsEngine(parts: parts, song: own)
            Log.say("mix", "on for “\(t.title)”: \(parts.keys.sorted().joined(separator: ", "))\(own != nil ? " and the song itself" : ""), \(voice.rawValue)")
            engine = e
            e.set(gains(), seconds: 0.08)
            e.play(from: at)
            app.player.setVolume(0)
            follow()
        } catch {
            Log.say("mix", "the parts won't open: \(error)")
            engine = nil
            app.player.setVolume(1)
        }
    }

    /** The engine out and the player's sound back. */
    private func leave(quick: Bool) {
        watch?.cancel()
        watch = nil
        guard let e = engine else { app.player.setVolume(1); return }
        engine = nil
        if quick { e.stop(); app.player.setVolume(1); return }
        e.set(["song": 0], seconds: 0.4)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            self.app.player.setVolume(1)
            e.stop()
        }
    }

    /** Pulled back in step only when it's really off (over a third of a second). */
    private func follow() {
        watch?.cancel()
        watch = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, let e = self.engine, self.app.player.playing, !self.app.player.buffering,
                      let mine = e.position else { continue }
                let theirs = self.app.player.exactPosition
                if abs(mine - theirs) > 0.35 { e.play(from: theirs) }
            }
        }
    }
}
