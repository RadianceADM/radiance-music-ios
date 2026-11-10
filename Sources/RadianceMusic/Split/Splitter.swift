import AVFoundation
import CryptoKit
import Foundation
import OnnxRuntimeBindings
import RadianceKit
import UIKit

/**
 * Splitting on this iPhone (Android's split/Splitter.kt, SplitService.kt, Model.kt, Guard.kt): a song in two, its
 * vocals and its music, with Spleeter on ONNX Runtime; the parts kept in the app's own folder, one song at a time,
 * the ones asked for in a queue. It needs the song's sound here: its saved copy, else it's fetched for the split
 * (a joined server's copy first, else from where it's from) and let go after.
 */
@MainActor
@Observable
final class Splitter {
    /** One of the models: its name here, where it comes from, its size and SHA-256 (the same files as Android's). */
    struct Model {
        let name: String
        let url: String
        let size: Int64
        let sha256: String
    }

    static let repo = "https://huggingface.co/csukuangfj/sherpa-onnx-spleeter-2stems-fp16/resolve/93ba771920ade509f8cbd6825b1a90856c797e08"
    static let vocalsModel = Model(name: "vocals.fp16.onnx", url: "\(repo)/vocals.fp16.onnx", size: 19_681_017,
                                   sha256: "24cef84aedcd1fe87c0b743ef3370ad34dc1fabf6c9014d6128a75a538c7b668")
    static let musicModel = Model(name: "accompaniment.fp16.onnx", url: "\(repo)/accompaniment.fp16.onnx", size: 19_681_024,
                                  sha256: "d14cea55793cc531a5875f5f4da08207d1c5ab9292e8e0099a104eecb014fcc0")
    static let models = [vocalsModel, musicModel]

    /** The song being split now (its key), how far (0-1) and what's happening, in words. */
    private(set) var working: (key: String, progress: Double, words: String)?
    /** Songs waiting their turn (their keys). */
    private(set) var waiting: [Track] = []
    /** The models are being fetched (the first split): how much is here, 0-1. */
    private(set) var setup: Double?

    @ObservationIgnored private unowned let app: AppModel
    @ObservationIgnored private var job: Task<Void, Never>?
    /** Stop the split at work (read off the main thread, between blocks). */
    @ObservationIgnored private let stop = Flag()

    init(app: AppModel) { self.app = app }

    var dir: URL { app.paths.support.appendingPathComponent("splitter", isDirectory: true) }
    func file(_ m: Model) -> URL { dir.appendingPathComponent(m.name) }
    var ready: Bool { Splitter.models.allSatisfy { (try? FileManager.default.attributesOfItem(atPath: file($0).path)[.size] as? Int64) == $0.size } }

    func isWaiting(_ key: String) -> Bool { waiting.contains { $0.key == key } || working?.key == key }

    /** Splits [t] (after the ones waiting). */
    func split(_ t: Track) {
        guard !isWaiting(t.key), !app.mixer.hasParts(t) else { return }
        waiting.append(t)
        go()
    }

    /** Takes [key] out of the queue (the one at work stops). */
    func cancel(_ key: String) {
        waiting.removeAll { $0.key == key }
        if working?.key == key { stop.value = true }
    }

    private func go() {
        guard job == nil else { return }
        job = Task { [weak self] in
            while let self, !self.waiting.isEmpty {
                let t = self.waiting.removeFirst()
                self.stop.value = false
                self.working = (t.key, 0, "Getting ready…")
                var song: (URL, Bool)?
                do {
                    try await self.getModels()
                    song = try await self.soundOf(t)
                    try await self.run(t, song: song!.0)
                    self.working = nil
                    self.app.mixer.recheck()
                    self.app.tell("“\(t.title)” is split: karaoke and vocals only are ready.")
                    // a joined server gets the song and its parts (owner, 2026-11-09: rule 2, every app)
                    await self.app.uploadSplit(t, song: song!.0)
                } catch is CancellationError {
                    self.working = nil
                } catch {
                    self.working = nil
                    Log.say("split", "“\(t.title)” wouldn't split: \(error)")
                    let why = (error as? Plain)?.words ?? Errors.say(error, online: self.app.online)
                    self.app.tell("Couldn't split “\(t.title)”. \(why)", action: ("Retry", { [weak self] in self?.split(t) }))
                }
                if let (f, temporary) = song, temporary { try? FileManager.default.removeItem(at: f) }
            }
            self?.job = nil
        }
    }

    // MARK: - one song

    private func run(_ t: Track, song: URL) async throws {
        working = (t.key, 0, "Splitting…")
        let out = Splits.dir(app.paths, t.key)
        let key = t.key
        let models = (file(Splitter.vocalsModel), file(Splitter.musicModel))
        let stop = self.stop
        let check: @Sendable () throws -> Void = { [weak self] in
            try Guard.rest(say: { words in Task { @MainActor in if self?.working?.key == key { self?.working?.words = words } } },
                           stopped: { stop.value })
        }
        // the work itself, off the main thread
        try await Task.detached(priority: .utility) {
            try await Splitter.split(song: song, into: out, models: models, threads: Splitter.coresNow(), beforeBlock: check) { done in
                Task { @MainActor [weak self] in if self?.working?.key == key { self?.working = (key, done, "Splitting… \(Int(done * 100)) %") } }
            }
        }.value
    }

    /** The song's sound for the split: its saved file, else fetched (and let go after). */
    private func soundOf(_ t: Track) async throws -> (URL, Bool) {
        let best = app.library.best(t)
        if let f = app.paths.file(best.file), f.isFileURL, FileManager.default.fileExists(atPath: f.path) { return (f, false) }
        working = (t.key, 0, "Getting the song…")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("split-\(Saver.safe(t.key))")
        var url: String
        var headers: [String: String] = [:]
        var ext = "m4a"
        if let (_, copy) = await app.servers.copy(of: t) {
            url = app.servers.sign(copy.url)
            ext = copy.file.split(separator: ".").last.map(String.init) ?? "m4a"
        } else {
            switch t.source {
            case .youtube:
                let s = try await YouTube.audio(t.id)
                url = s.url; headers = s.headers; ext = s.ext
            case .archive: url = t.id; ext = "flac"
            case .server: url = app.servers.sign(t.id); ext = t.id.split(separator: ".").last.map(String.init) ?? "m4a"
            }
        }
        let f = tmp.appendingPathExtension(ext)
        let key = t.key
        try await Http.download(url, to: f, headers: headers) { p in Task { @MainActor in self.working = (key, 0, "Getting the song… \(Int(p * 100)) %") } }
        return (f, true)
    }

    /** The models, fetched once and checked to be exactly the published files. */
    private func getModels() async throws {
        if ready { return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let total = Double(Splitter.models.reduce(0) { $0 + $1.size })
        var before: Int64 = 0
        setup = 0
        defer { setup = nil }
        for m in Splitter.models {
            let f = file(m)
            if (try? FileManager.default.attributesOfItem(atPath: f.path)[.size] as? Int64) != m.size {
                working = (working?.key ?? "", 0, "Getting the splitter (39 MB, once)…")
                let b = before
                try await Http.download(m.url, to: f, size: m.size) { p in
                    Task { @MainActor in self.setup = (Double(b) + p * Double(m.size)) / total }
                }
                let data = try Data(contentsOf: f, options: .alwaysMapped)
                let sum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard sum == m.sha256 else {
                    try? FileManager.default.removeItem(at: f)
                    throw Plain("The splitter didn't download right. Try again.", "sha256 \(sum)")
                }
            }
            before += m.size
        }
    }

    // MARK: - how many cores (Android's Splits.cores, Settings → Splitting)

    /** All of this iPhone's cores. */
    nonisolated static let mostCores = max(ProcessInfo.processInfo.activeProcessorCount, 1)
    /** While the iPhone is warm, at most this many (Android's Guard.WARM_CORES). */
    nonisolated static let warmCores = 2

    /** How many of the iPhone's cores splitting may use: more split sooner, fewer keep it cooler (4 at first). */
    nonisolated static var cores: Int {
        get {
            let set = UserDefaults.standard.integer(forKey: "split.cores")
            return min(max(set == 0 ? min(4, mostCores) : set, 1), mostCores)
        }
        set { UserDefaults.standard.set(min(max(newValue, 1), mostCores), forKey: "split.cores") }
    }

    /** The cores a split starting now uses: the set ones, fewer while the iPhone is warm. */
    nonisolated static func coresNow() -> Int32 {
        Int32(ProcessInfo.processInfo.thermalState == .fair ? min(cores, warmCores) : cores)
    }

    // MARK: - the sound work (off the main thread)

    /**
     * [song] in two: decoded to 44.1 kHz stereo, through Spleeter, each part written as AAC beside its place, then
     * put in place (a stopped split leaves no half parts).
     */
    nonisolated static func split(song: URL, into out: URL, models: (URL, URL), threads: Int32, beforeBlock: () throws -> Void,
                                  progress: (Double) -> Void) async throws {
        let pcm = try await decode(song)
        let total = pcm.count / 2
        Log.say("split", "on \(threads) of \(mostCores) cores")
        let (env, vocals) = try Onnx.session(models.0, threads: threads)
        let (_, music) = try Onnx.session(models.1, threads: threads)
        _ = env
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 160_000]
        let names = Spleeter.parts
        let partials = names.map { out.appendingPathComponent("\($0).part.m4a") }
        for p in partials { try? FileManager.default.removeItem(at: p) }
        var writers = try partials.map { try AVAudioFile(forWriting: $0, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false) }
        let vocalsOut = try vocals.outputNames().first ?? "y"
        let musicOut = try music.outputNames().first ?? "y"
        try pcm.withUnsafeBufferPointer { x in
            try Spleeter.run(x, total: total, models: { input, shape in
                let data = NSMutableData(bytes: input, length: input.count * MemoryLayout<Float>.size)
                let value = try ORTValue(tensorData: data, elementType: .float, shape: shape.map { NSNumber(value: $0) })
                func floats(_ s: ORTSession, _ name: String) throws -> [Float] {
                    let r = try s.run(withInputs: ["x": value], outputNames: [name], runOptions: nil)
                    guard let v = r[name] else { throw Plain("The splitter's model didn't answer.") }
                    let d = try v.tensorData() as Data
                    return d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                }
                return (try floats(vocals, vocalsOut), try floats(music, musicOut))
            }, part: { p, buf, frames in
                let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
                b.frameLength = AVAudioFrameCount(frames)
                let l = b.floatChannelData![0], r = b.floatChannelData![1]
                for i in 0..<frames { l[i] = buf[2 * i]; r[i] = buf[2 * i + 1] }
                try writers[p].write(from: b)
            }, block: { done, of in progress(Double(done) / Double(of)) }, beforeBlock: beforeBlock)
        }
        writers.removeAll() // closes them
        for (i, n) in names.enumerated() {
            let f = out.appendingPathComponent("\(n).m4a")
            try? FileManager.default.removeItem(at: f)
            try FileManager.default.moveItem(at: partials[i], to: f)
        }
        let sizes = names.map { n in "\(n) \(((try? FileManager.default.attributesOfItem(atPath: out.appendingPathComponent("\(n).m4a").path))?[.size] as? NSNumber)?.intValue ?? 0) bytes" }
        Log.say("split", "\(total / 44100) s split: \(sizes.joined(separator: ", "))")
    }

    /** The song as 44.1 kHz stereo float samples, interleaved (a mono song made stereo). */
    /**
     * The song's sound as 44.1 kHz stereo, read the way the player reads it (AVAssetReader: Opus inside .m4a too, as
     * the computer's songs come; AVAudioFile opened those but read nothing, and the split wrote empty parts).
     */
    nonisolated static func decode(_ url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw Plain("This song's file has no sound to split.") }
        let seconds = (try? await asset.load(.duration).seconds) ?? 0
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw Plain("This song's file can't be read for a split.") }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? Plain("This song's file can't be read for a split.") }
        var out = [Float]()
        if seconds.isFinite, seconds > 0 { out.reserveCapacity(Int(seconds * 44100 * 2) + 88200) }
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let bytes = CMBlockBufferGetDataLength(block)
            let start = out.count
            out.append(contentsOf: repeatElement(0, count: bytes / MemoryLayout<Float>.size))
            _ = out.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes, destination: $0.baseAddress! + start * MemoryLayout<Float>.size) }
        }
        if reader.status == .failed { throw reader.error ?? Plain("This song's file stopped reading halfway.") }
        // less than a second of sound: something's wrong with the file, and parts made from it would be silent
        guard out.count >= 44100 * 2 else { throw Plain("This song's sound couldn't be read, so it wasn't split.") }
        return out
    }
}

/**
 * Splitting works the iPhone hard (Android's Guard): it pauses when the battery is low and it isn't charging, or
 * when the iPhone is really hot, and goes on by itself once it's charging or has cooled down.
 */
enum Guard {
    static let batteryLow: Float = 0.20
    static let batteryOn: Float = 0.25

    /** Why the iPhone needs a rest now, or nil. [resting]: already paused (it waits for a little more). */
    @MainActor
    static func reason(resting: Bool) -> String? {
        let d = UIDevice.current
        d.isBatteryMonitoringEnabled = true
        let charging = d.batteryState == .charging || d.batteryState == .full
        let level = d.batteryLevel
        if !charging, level >= 0, level < (resting ? batteryOn : batteryLow) {
            return "Paused: the battery is at \(Int(level * 100)) %. It goes on when the iPhone charges."
        }
        if ProcessInfo.processInfo.thermalState == .critical || ProcessInfo.processInfo.thermalState == .serious {
            return "Paused: the iPhone is hot. It goes on once it cools down."
        }
        return nil
    }

    /** Waits (telling [say] why) while the iPhone needs a rest; back as soon as it doesn't. Stopped: CancellationError. */
    static func rest(say: (String) -> Void, stopped: () -> Bool) throws {
        if stopped() { throw CancellationError() }
        var why = DispatchQueue.main.sync { MainActor.assumeIsolated { reason(resting: false) } }
        while let w = why {
            say(w)
            Thread.sleep(forTimeInterval: 5)
            if stopped() { throw CancellationError() }
            why = DispatchQueue.main.sync { MainActor.assumeIsolated { reason(resting: true) } }
        }
    }
}

/** A yes/no read and set from any thread. */
final class Flag: @unchecked Sendable {
    private var v = false
    private let lock = NSLock()
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return v }
        set { lock.lock(); v = newValue; lock.unlock() }
    }
}
