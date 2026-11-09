import AVFoundation
import MediaPlayer
import RadianceKit
import UIKit

enum RepeatMode { case off, all, one }

/**
 * The player (Android's play/PlayerHub.kt + PlaybackService.kt): the queue, the song playing, shuffle and repeat,
 * and the iPhone's side of it: playing on with the screen locked, the lock screen's and Control Center's controls,
 * headphone buttons, pausing when headphones come out, where you left off. A song is found only as it starts (a
 * saved file, the Archive's address, a server's file with this iPhone's key; a YouTube song: your server's copy).
 */
@MainActor
@Observable
final class PlayerHub {
    private(set) var queue: [Track] = []
    private(set) var index = 0
    /** Meant to play (pressed Play and not paused since). */
    private(set) var playing = false
    /** Play pressed and the song not here yet (finding it, loading it): the Play button spins. */
    private(set) var buffering = false
    /** What it's doing while the song isn't here yet ("Getting it from YouTube on Bassi's server…"). */
    private(set) var note: String?
    /** Why the music stopped (a song that wouldn't play), until one plays again. */
    private(set) var problem: String?
    private(set) var shuffle = false
    private(set) var repeatMode = RepeatMode.off
    /** Where in the song (seconds), as last heard. */
    private(set) var position: Double = 0
    private(set) var duration: Double = 0

    var current: Track? { queue.indices.contains(index) ? queue[index] : nil }

    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var order: [Int] = []
    @ObservationIgnored private var streak = Streak()
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var statusWatch: NSKeyValueObservation?
    @ObservationIgnored private var itemWatch: NSKeyValueObservation?
    @ObservationIgnored private var ends: [NSObjectProtocol] = []
    @ObservationIgnored private var ticker: Any?
    @ObservationIgnored private var artFor: String?
    /** A YouTube song's copy on your server, by its key (asked once per run). */
    @ObservationIgnored private var serverCopy: [String: String] = [:]

    /** How many songs like it come after a song from search. */
    static let related = 30

    init(app: AppModel) {
        self.app = app
        player.automaticallyWaitsToMinimizeStalling = true
        setUpSession()
        setUpRemote()
        ticker = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.tick(t.seconds) }
        }
        statusWatch = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            let status = p.timeControlStatus
            Task { @MainActor in self?.statusChanged(status) }
        }
        // where you left off: paused at the same spot
        if let s = app.library.session() {
            queue = s.queue
            index = min(max(s.index, 0), s.queue.count - 1)
            position = Double(s.positionMs) / 1000
            duration = Double(current?.seconds ?? 0)
            rebuildOrder()
            updateNowPlaying()
        }
    }

    // MARK: - what you ask for

    /** Plays [list] from [start], as the songs are now (saved copies when liked). */
    func play(_ list: [Track], _ start: Int) {
        guard !list.isEmpty else { return }
        picked()
        queue = list.map(app.library.best)
        index = min(max(start, 0), queue.count - 1)
        rebuildOrder()
        load(index, at: 0, play: true)
    }

    /** [t] now, then songs like it (YouTube Music's "Up next" for it), added once they come. */
    func playWithRelated(_ t: Track) {
        play([t], 0)
        Task {
            let more = await relatedTo(t)
            // only while the pick still plays (moved on: dropped); songs added meanwhile stay, these after them
            guard !more.isEmpty, current?.key == t.key else { return }
            append(more)
        }
    }

    /** "Songs like this": the song playing goes on and songs like it come next; another song plays now, with songs like it after it. */
    func radio(_ t: Track) {
        guard current?.key == t.key else { return playWithRelated(t) }
        Task {
            let more = await relatedTo(t)
            guard current?.key == t.key else { return }
            if more.isEmpty { return app.tell("Couldn't find songs like “\(t.title)”. Try again in a bit.") }
            queue = Array(queue.prefix(index + 1)) + more.map(app.library.best)
            rebuildOrder()
            app.tell("Up next: \(more.count) songs like “\(t.title)”.")
            prepareNext()
        }
    }

    func playNext(_ t: Track) {
        if queue.isEmpty { return play([t], 0) }
        queue.insert(app.library.best(t), at: index + 1)
        rebuildOrder()
        app.tell("“\(t.title)” plays next.")
    }

    func enqueue(_ t: Track) {
        if queue.isEmpty { return play([t], 0) }
        append([t])
        app.tell("Added “\(t.title)” to the queue.")
    }

    private func append(_ more: [Track]) {
        queue += more.map(app.library.best)
        rebuildOrder()
        prepareNext()
    }

    func toggle() {
        if playing { return pause() }
        // stopped by a song that wouldn't play: Play tries it again
        if problem != nil { streak.retry(); problem = nil }
        guard current != nil else { return }
        if player.currentItem == nil { return load(index, at: position, play: true) }
        if duration > 0 && position >= duration - 0.5 { player.seek(to: .zero) }
        resume()
    }

    /** The song's own sound (the Mixer turns it down while it plays the parts). */
    func setVolume(_ v: Float) { player.volume = min(max(v, 0), 1) }

    /** Where the player is right now (not the last tick's). */
    var exactPosition: Double {
        let s = player.currentTime().seconds
        return s.isFinite ? s : position
    }

    func pause() {
        player.pause()
        app.mixer.playingChanged(false, at: exactPosition)
        playing = false
        buffering = false
        updateNowPlaying()
        saveSession()
    }

    private func resume() {
        activate()
        playing = true
        player.play()
        updateNowPlaying()
    }

    func next() {
        picked()
        if let n = nextIndex(auto: false) { load(n, at: 0, play: true) }
    }

    func previous() {
        picked()
        if position > 4 || previousIndex() == nil { return seek(0) }
        load(previousIndex()!, at: 0, play: playing || player.currentItem == nil)
    }

    /** The song before, whatever the place in this one (a swipe on the cover). */
    func previousSong() {
        picked()
        if let p = previousIndex() { load(p, at: 0, play: true) } else { seek(0) }
    }

    func playAt(_ i: Int) {
        guard queue.indices.contains(i) else { return }
        picked()
        load(i, at: 0, play: true)
    }

    func seek(_ seconds: Double) {
        position = max(0, seconds)
        player.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        app.mixer.seeked(to: position)
        updateNowPlaying()
    }

    func toggleShuffle() {
        shuffle.toggle()
        rebuildOrder()
        prepareNext()
    }

    func cycleRepeat() {
        repeatMode = switch repeatMode { case .off: .all; case .all: .one; case .one: .off }
    }

    func remove(at offsets: IndexSet) {
        let wasCurrent = offsets.contains(index)
        let key = current?.key
        queue.remove(atOffsets: offsets)
        if queue.isEmpty {
            stop()
            return
        }
        if wasCurrent {
            index = min(offsets.first ?? 0, queue.count - 1)
            rebuildOrder()
            load(index, at: 0, play: playing)
        } else {
            index = queue.firstIndex { $0.key == key } ?? 0
            rebuildOrder()
        }
    }

    func move(from: IndexSet, to: Int) {
        let key = current?.key
        queue.move(fromOffsets: from, toOffset: to)
        index = queue.firstIndex { $0.key == key } ?? index
        rebuildOrder()
        prepareNext()
    }

    /** Tries the song that wouldn't play again. */
    func retry() {
        streak.retry()
        problem = nil
        load(index, at: position, play: true)
    }

    /** A liked song saved: the queue's copy plays the file from now on. */
    func refresh(_ t: Track) {
        for i in queue.indices where queue[i].key == t.key && i != index { queue[i] = t }
    }

    func stop() {
        loading?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        playing = false
        buffering = false
        note = nil
        updateNowPlaying()
    }

    func saveSession() {
        app.library.saveSession(queue: queue, index: index, positionMs: Int64(position * 1000))
    }

    // MARK: - the order songs come in

    private func rebuildOrder() {
        let all = Array(queue.indices)
        order = shuffle ? [index] + all.filter { $0 != index }.shuffled() : all
    }

    private func nextIndex(auto: Bool) -> Int? {
        if auto && repeatMode == .one { return index }
        guard let p = order.firstIndex(of: index) else { return nil }
        if p + 1 < order.count { return order[p + 1] }
        return repeatMode == .all ? order.first : nil
    }

    private func previousIndex() -> Int? {
        guard let p = order.firstIndex(of: index) else { return nil }
        if p > 0 { return order[p - 1] }
        return repeatMode == .all ? order.last : nil
    }

    /** You picked a song: whatever wouldn't play before is forgotten. */
    private func picked() {
        streak.picked()
        problem = nil
    }

    // MARK: - loading a song

    private func load(_ i: Int, at: Double, play: Bool) {
        loading?.cancel()
        clearItem()
        index = i
        let t = queue[i]
        position = at
        duration = Double(t.seconds)
        problem = nil
        note = nil
        playing = play
        buffering = play
        if play { app.library.played(t) }
        app.mixer.songChanged(t)
        updateNowPlaying()
        saveSession()
        loading = Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await self.find(t)
                guard !Task.isCancelled, self.current?.key == t.key else { return }
                self.note = nil
                let item = AVPlayerItem(asset: AVURLAsset(url: url))
                self.watchItem(item, t)
                self.player.replaceCurrentItem(with: item)
                if at > 0 { await self.player.seek(to: CMTime(seconds: at, preferredTimescale: 600)) }
                if self.playing {
                    self.activate()
                    self.player.play()
                } else {
                    self.buffering = false
                }
                self.updateNowPlaying()
                if play { self.prepareNext() }
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, self.current?.key == t.key else { return }
                self.couldnt(t, error)
            }
        }
    }

    /** Where [t] plays from: its saved file, the Archive, its server (with this iPhone's key), or your server's copy of a YouTube song. */
    private func find(_ t: Track) async throws -> URL {
        if let f = app.paths.file(t.file), f.isFileURL, FileManager.default.fileExists(atPath: f.path) { return f }
        switch t.source {
        case .archive:
            guard let u = URL(string: t.id) else { throw Plain("This song's address is broken.") }
            return u
        case .server:
            guard let u = URL(string: app.servers.sign(t.id)) else { throw Plain("This song's address is broken.") }
            return u
        case .youtube:
            // a joined server's copy first (owner, 2026-11-09), else the iPhone gets it from YouTube itself
            if let have = serverCopy[t.key], let u = URL(string: app.servers.sign(have)) { return u }
            if let (_, song) = await app.servers.copy(of: t) {
                serverCopy[t.key] = song.url
                if let u = URL(string: app.servers.sign(song.url)) { return u }
            }
            let s = try await YouTube.audio(t.id)
            guard let u = URL(string: s.url) else { throw Plain("YouTube gave a broken address for this song.") }
            return u
        }
    }

    /** The next song from YouTube: looked up now (a server's copy, else YouTube's), so it starts at once when it's its turn. */
    private func prepareNext() {
        guard let n = nextIndex(auto: false), queue.indices.contains(n) else { return }
        let t = queue[n]
        guard t.source == .youtube, serverCopy[t.key] == nil,
              app.paths.file(t.file).map({ !FileManager.default.fileExists(atPath: $0.path) }) ?? true else { return }
        Task { [weak self] in
            guard let self else { return }
            if let (_, song) = await self.app.servers.copy(of: t) { self.serverCopy[t.key] = song.url } else { _ = try? await YouTube.audio(t.id) }
        }
    }

    private func relatedTo(_ t: Track) async -> [Track] {
        var seed: String? = t.source == .youtube ? t.id : nil
        if seed == nil { seed = (try? await YouTube.search("\(t.artist) \(t.title)"))?.first?.id }
        guard let seed, let more = try? await YouTube.related(seed) else { return [] }
        return Array(more.filter { $0.key != t.key }.prefix(PlayerHub.related))
    }

    private func clearItem() {
        itemWatch = nil
        for e in ends { NotificationCenter.default.removeObserver(e) }
        ends.removeAll()
        player.replaceCurrentItem(with: nil)
    }

    private func watchItem(_ item: AVPlayerItem, _ t: Track) {
        itemWatch = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            let failed = it.status == .failed ? it.error : nil
            let ready = it.status == .readyToPlay
            let d = it.duration.seconds
            Task { @MainActor in
                guard let self, self.current?.key == t.key else { return }
                if ready, d.isFinite, d > 0 { self.duration = d; self.updateNowPlaying() }
                if let failed { self.couldnt(t, failed) }
            }
        }
        let nc = NotificationCenter.default
        ends.append(nc.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.ended() }
        })
        ends.append(nc.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] n in
            let e = n.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            MainActor.assumeIsolated { self?.couldnt(t, e ?? Plain("The song stopped halfway.")) }
        })
    }

    private func ended() {
        if let n = nextIndex(auto: true) {
            if n == index { seek(0); player.play(); return }
            load(n, at: 0, play: true)
        } else {
            // the end of the queue: stopped at the last song's end
            playing = false
            buffering = false
            updateNowPlaying()
            saveSession()
        }
    }

    /** A song wouldn't play: why, in plain words, and on to the next one (not past three in a row). */
    private func couldnt(_ t: Track, _ error: Error) {
        print("radiance-play: “\(t.title)” (\(t.key)) wouldn't play: \(error)")
        let why: String
        if let r = error as? Refused { why = r.words } else { why = Errors.say(error, online: app.online) }
        note = nil
        let then = streak.failed(hasNext: nextIndex(auto: false) != nil)
        switch then {
        case .next:
            app.tell("Skipped “\(t.title)”. \(why)", action: ("Retry", { [weak self] in self?.retryKey(t.key) }))
            load(nextIndex(auto: false)!, at: 0, play: true)
        case .stop:
            problem = "Couldn't play. \(why)"
            stopped()
            app.tell("“\(t.title)” couldn't play. \(why)", action: ("Retry", { [weak self] in self?.retryKey(t.key) }))
        case .tooMany:
            problem = "Couldn't play. \(why)"
            stopped()
            app.tell("\(streak.inARow) songs in a row couldn't play, so the music stopped. \(why)", action: ("Retry", { [weak self] in self?.retryKey(t.key) }))
        }
    }

    private func retryKey(_ key: String) {
        if let i = queue.firstIndex(where: { $0.key == key }) { index = i }
        retry()
    }

    private func stopped() {
        player.pause()
        app.mixer.playingChanged(false, at: exactPosition)
        playing = false
        buffering = false
        updateNowPlaying()
    }

    private func tick(_ seconds: Double) {
        guard player.currentItem != nil, seconds.isFinite else { return }
        position = seconds
    }

    private func statusChanged(_ s: AVPlayer.TimeControlStatus) {
        switch s {
        case .playing:
            print("radiance-play: playing “\(current?.title ?? "?")”")
            app.mixer.playingChanged(true, at: exactPosition)
            buffering = false
            streak.played()
            problem = nil
        case .waitingToPlayAtSpecifiedRate:
            buffering = playing
        case .paused:
            if player.currentItem != nil { buffering = false }
        @unknown default:
            break
        }
        updateNowPlaying()
    }

    // MARK: - the iPhone's side: audio session, lock screen, buttons

    private func setUpSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default, policy: .longFormAudio)
        let nc = NotificationCenter.default
        // a call, an alarm: paused, and back on after if iOS says so
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: s, queue: .main) { [weak self] n in
            let type = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let opts = AVAudioSession.InterruptionOptions(rawValue: n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            MainActor.assumeIsolated {
                guard let self else { return }
                if type == .began { if self.playing { self.player.pause(); self.updateNowPlaying() } }
                else if type == .ended, opts.contains(.shouldResume), self.playing { self.resume() }
                else if type == .ended { self.playing = false; self.updateNowPlaying() }
            }
        }
        // headphones out: it pauses
        nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: s, queue: .main) { [weak self] n in
            let reason = (n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            MainActor.assumeIsolated { if reason == .oldDeviceUnavailable, self?.playing == true { self?.pause() } }
        }
    }

    private func activate() {
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func setUpRemote() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { if self?.playing == false { self?.toggle() } }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.pause() }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.toggle() }; return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.next() }; return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.previous() }; return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            let at = (e as? MPChangePlaybackPositionCommandEvent)?.positionTime ?? 0
            MainActor.assumeIsolated { self?.seek(at) }
            return .success
        }
    }

    private func updateNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard let t = current else {
            center.nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: t.title,
            MPMediaItemPropertyArtist: t.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: playing && !buffering ? 1.0 : 0.0,
        ]
        if !t.album.isEmpty { info[MPMediaItemPropertyAlbumTitle] = t.album }
        if let art = center.nowPlayingInfo?[MPMediaItemPropertyArtwork], artFor == t.key { info[MPMediaItemPropertyArtwork] = art }
        center.nowPlayingInfo = info
        center.playbackState = playing ? .playing : .paused
        if artFor != t.key {
            artFor = t.key
            Task { [weak self] in
                guard let self, let image = await self.app.covers.image(t, px: Art.medium), self.current?.key == t.key else { return }
                let art = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                var now = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                now[MPMediaItemPropertyArtwork] = art
                MPNowPlayingInfoCenter.default().nowPlayingInfo = now
            }
        }
    }
}
