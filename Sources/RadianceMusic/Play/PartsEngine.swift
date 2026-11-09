import AVFoundation
import RadianceKit

/**
 * A split song played as one sound (Android's play/PartsEngine.kt): its own file (when it's on the iPhone) and its
 * parts, all started on the same clock, so a switch between the whole song, karaoke and the singing only just glides
 * the volumes. The player keeps playing the song silently and drives everything (the lock screen, the buttons,
 * seeking, the next song); this follows it. Low cut, high cut and the room reverb are on its way out.
 */
@MainActor
final class PartsEngine {
    private let engine = AVAudioEngine()
    private let eq = AVAudioUnitEQ(numberOfBands: 2)
    private let reverb = AVAudioUnitReverb()
    private var nodes: [String: (AVAudioPlayerNode, AVAudioFile)] = [:]
    private var gains: [String: Float] = [:]
    private var glide: Task<Void, Never>?
    /** Where in the song the nodes started from (seconds), and when (the engine's host time). */
    private var startedAt: Double = 0
    private(set) var running = false
    /** The song's own file is one of the nodes ("song"). */
    var hasSong: Bool { nodes["song"] != nil }

    /** [parts]: name to file; [song]: the song's own file (nil: the parts alone). */
    init(parts: [String: URL], song: URL?) throws {
        var all = parts
        if let song { all["song"] = song }
        engine.attach(eq)
        engine.attach(reverb)
        let out = engine.mainMixerNode
        for (name, url) in all {
            let file = try AVAudioFile(forReading: url)
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: out, format: file.processingFormat)
            node.volume = 0
            nodes[name] = (node, file)
        }
        // the mix → low cut, high cut → the room → the speaker
        engine.disconnectNodeOutput(out)
        engine.connect(out, to: eq, format: nil)
        engine.connect(eq, to: reverb, format: nil)
        engine.connect(reverb, to: engine.outputNode, format: nil)
        eq.bands[0].filterType = .highPass
        eq.bands[1].filterType = .lowPass
        for b in eq.bands { b.bandwidth = 1.0; b.bypass = false }
        reverb.loadFactoryPreset(.mediumRoom)
        apply(Effects.shared)
        engine.prepare()
        try engine.start()
    }

    /** Each node's volume, glided there over [seconds] (a switch never clicks). */
    func set(_ g: [String: Float], seconds: Double = 0.3) {
        gains = g
        glide?.cancel()
        let from = nodes.mapValues { $0.0.volume }
        glide = Task { @MainActor [weak self] in
            let steps = max(1, Int(seconds / 0.02))
            for i in 1...steps {
                guard let self, !Task.isCancelled else { return }
                let k = Float(i) / Float(steps)
                for (name, (node, _)) in self.nodes {
                    let a = from[name] ?? 0, b = g[name] ?? 0
                    node.volume = a + (b - a) * k
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    /** Plays from [at] seconds into the song, every node on the same moment, [lead] from now. */
    func play(from at: Double, lead: Double = 0.12) {
        for (node, _) in nodes.values { node.stop() }
        if !engine.isRunning { try? engine.start() }
        let start = at + lead
        var last: AVAudioFramePosition = 0
        for (node, file) in nodes.values {
            let rate = file.processingFormat.sampleRate
            let first = AVAudioFramePosition(start * rate)
            guard first < file.length else { continue }
            node.scheduleSegment(file, startingFrame: first, frameCount: AVAudioFrameCount(file.length - first), at: nil)
            last = max(last, first)
        }
        let when = AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: lead))
        for (node, _) in nodes.values { node.play(at: when) }
        startedAt = start
        running = true
    }

    func pause() {
        for (node, _) in nodes.values { node.pause() }
        running = false
    }

    /** Where it is in the song now (seconds), by the song's or the first part's own clock. */
    var position: Double? {
        guard running, let (node, file) = nodes["song"] ?? nodes.values.first,
              let render = node.lastRenderTime, let t = node.playerTime(forNodeTime: render), t.sampleTime >= 0 else { return nil }
        return startedAt + Double(t.sampleTime) / file.processingFormat.sampleRate
    }

    func apply(_ e: Effects) {
        eq.bands[0].frequency = Float(e.lowCut)
        eq.bands[0].bypass = e.lowCut <= Effects.lowOff + 0.5
        eq.bands[1].frequency = Float(min(e.highCut, 20000))
        eq.bands[1].bypass = e.highCut >= Effects.highOff - 0.5
        reverb.wetDryMix = Float(e.reverb * 60)
        reverb.bypass = e.reverb < 0.005
    }

    func stop() {
        glide?.cancel()
        for (node, _) in nodes.values { node.stop() }
        engine.stop()
        running = false
    }
}

/**
 * Low cut, High cut, Reverb (Android's play/Effects.kt): as the computer's Mixer and Speaker EQ make them, off at the
 * left of each slider. Kept.
 */
@MainActor
@Observable
final class Effects {
    static let shared = Effects()
    static let lowOff = 20.0, lowMost = 500.0, highOff = 20000.0, highMost = 1500.0

    var lowCut: Double { didSet { save() } }
    var highCut: Double { didSet { save() } }
    var reverb: Double { didSet { save() } }

    private init() {
        let d = UserDefaults.standard
        lowCut = d.object(forKey: "fx.low") as? Double ?? Effects.lowOff
        highCut = d.object(forKey: "fx.high") as? Double ?? Effects.highOff
        reverb = d.object(forKey: "fx.reverb") as? Double ?? 0
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(lowCut, forKey: "fx.low")
        d.set(highCut, forKey: "fx.high")
        d.set(reverb, forKey: "fx.reverb")
    }

    var neutral: Bool { lowCut <= Effects.lowOff + 0.5 && highCut >= Effects.highOff - 0.5 && reverb < 0.005 }

    /** The sliders run 0…1 on a log scale, as Android's. */
    var lowSlider: Double {
        get { log(lowCut / Effects.lowOff) / log(Effects.lowMost / Effects.lowOff) }
        set { lowCut = Effects.lowOff * pow(Effects.lowMost / Effects.lowOff, min(max(newValue, 0), 1)) }
    }

    var highSlider: Double {
        get { log(highCut / Effects.highOff) / log(Effects.highMost / Effects.highOff) }
        set { highCut = Effects.highOff * pow(Effects.highMost / Effects.highOff, min(max(newValue, 0), 1)) }
    }
}
