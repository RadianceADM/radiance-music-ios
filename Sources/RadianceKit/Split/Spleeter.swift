import Foundation

/** An in-place complex FFT (radix 2), as Android's play/Effects.kt Fft. */
public final class Fft {
    let n: Int
    private let cosT: [Float]
    private let sinT: [Float]
    private let rev: [Int]

    public init(_ n: Int) {
        self.n = n
        cosT = (0..<n / 2).map { Float(cos(2 * Double.pi * Double($0) / Double(n))) }
        sinT = (0..<n / 2).map { Float(sin(2 * Double.pi * Double($0) / Double(n))) }
        var r = [Int](repeating: 0, count: n)
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 { j ^= bit; bit >>= 1 }
            j ^= bit
            r[i] = j
        }
        rev = r
    }

    public func run(_ re: inout [Float], _ im: inout [Float], inverse: Bool) {
        re.withUnsafeMutableBufferPointer { re in
            im.withUnsafeMutableBufferPointer { im in
                for i in 1..<n {
                    let j = rev[i]
                    if i < j { re.swapAt(i, j); im.swapAt(i, j) }
                }
                var len = 2
                while len <= n {
                    let step = n / len
                    let half = len / 2
                    var i = 0
                    while i < n {
                        for k in 0..<half {
                            let c = cosT[k * step]
                            let s = inverse ? sinT[k * step] : -sinT[k * step]
                            let a = i + k, b = a + half
                            let tr = re[b] * c - im[b] * s
                            let ti = re[b] * s + im[b] * c
                            re[b] = re[a] - tr; im[b] = im[a] - ti
                            re[a] += tr; im[a] += ti
                        }
                        i += len
                    }
                    len <<= 1
                }
                if inverse {
                    let k = 1 / Float(n)
                    for i in 0..<n { re[i] *= k; im[i] *= k }
                }
            }
        }
    }
}

/**
 * A song in two: its vocals and its music (everything else), with Deezer's Spleeter (2 stems, MIT), the way Spleeter
 * itself does it (Android's split/Spleeter.kt, line by line). The song's spectrum (4096-sample frames, a frame every
 * 1024 samples, Hann window) goes to the two models (vocals, accompaniment) 512 frames at a time; each model says how
 * loud its part is in each of the lower 1024 bins (up to 11 kHz); each part keeps its share of the song's own sound
 * (ratio masks, squared), the bins above get each frame's average share, and the parts are turned back into sound.
 * The two parts add up to the song. The models run outside (ONNX Runtime on the iPhone): [models] gets their input.
 */
public enum Spleeter {
    /** The parts, in the order they're handed on. Named as the computer names a song's halves. */
    public static let parts = ["vocals", "music"]
    public static let n = 4096, h = 1024, f = 1024, t = 512
    static let bins = n / 2 + 1
    static let eps: Float = 1e-10

    static let win: [Float] = (0..<n).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(n))) } // periodic Hann
    /** The overlap-add's window sum (four frames over every sample). */
    static let wsum: [Float] = (0..<h).map { j in (0..<(n / h)).reduce(Float(0)) { $0 + win[j + $1 * h] * win[j + $1 * h] } }

    /** What the two models said for one block: each [2, 1, T, F], as flat floats. */
    public typealias Models = (_ input: [Float], _ shape: [Int]) throws -> (vocals: [Float], music: [Float])

    /**
     * [x]: [total] stereo frames (interleaved) at 44.1 kHz. [part] gets each part's next [frames] frames (interleaved,
     * from 0), in order, part 0 then part 1; [block] how many blocks are done of how many.
     */
    public static func run(_ x: UnsafeBufferPointer<Float>, total: Int, models: Models,
                           part: (_ index: Int, _ buf: [Float], _ frames: Int) throws -> Void,
                           block: (_ done: Int, _ of: Int) -> Void = { _, _ in },
                           beforeBlock: () throws -> Void = {}) throws {
        let n = Spleeter.n, h = Spleeter.h, f = Spleeter.f, tt = Spleeter.t, bins = Spleeter.bins
        // the song padded with N samples before and N + H after (as the bench does), in frames of N every H
        let padded = total + 2 * n + h
        let frames = 1 + (padded - n) / h
        let blocks = (frames + tt - 1) / tt
        @inline(__always) func sample(_ s: Int, _ ch: Int) -> Float { let i = s - n; return i >= 0 && i < total ? x[2 * i + ch] : 0 }

        let fft = Fft(n)
        var re = [Float](repeating: 0, count: n)
        var im = [Float](repeating: 0, count: n)
        // this block's spectrum, both channels: [ch][frame * bins + bin]
        var sRe = [[Float]](repeating: [Float](repeating: 0, count: tt * bins), count: 2)
        var sIm = [[Float]](repeating: [Float](repeating: 0, count: tt * bins), count: 2)
        var input = [Float](repeating: 0, count: 2 * tt * f)
        let shape = [2, 1, tt, f]
        var maskL = [[Float]](repeating: [Float](repeating: 0, count: bins), count: 2) // [part][bin], left channel
        var maskR = [[Float]](repeating: [Float](repeating: 0, count: bins), count: 2)
        // each part's sound being added up: a block's worth plus one frame's overlap, interleaved
        let span = tt * h + n
        var acc = [[Float]](repeating: [Float](repeating: 0, count: 2 * span), count: 2)
        var out = [Float](repeating: 0, count: 2 * tt * h)
        var emitted = n // the next padded sample to hand on

        for b in 0..<blocks {
            try beforeBlock() // waits while the phone needs a rest (Guard), or stops
            let t0 = b * tt
            let count = min(tt, frames - t0)
            for ch in 0..<2 { for j in (count * f)..<(tt * f) { input[ch * tt * f + j] = 0 } } // past the song's end
            for tl in 0..<count {
                let at = (t0 + tl) * h
                for i in 0..<n { re[i] = sample(at + i, 0) * win[i]; im[i] = sample(at + i, 1) * win[i] }
                fft.run(&re, &im, inverse: false)
                let o = tl * bins
                for k in 0..<bins {
                    let m = (n - k) % n
                    sRe[0][o + k] = 0.5 * (re[k] + re[m]); sIm[0][o + k] = 0.5 * (im[k] - im[m])
                    sRe[1][o + k] = 0.5 * (im[k] + im[m]); sIm[1][o + k] = -0.5 * (re[k] - re[m])
                }
                for ch in 0..<2 {
                    let base = (ch * tt + tl) * f
                    for k in 0..<f {
                        let r = sRe[ch][o + k], i = sIm[ch][o + k]
                        input[base + k] = (r * r + i * i).squareRoot()
                    }
                }
            }
            let (yv, ya) = try models(input, shape)

            // each part: its share of each bin, back to sound, added up in place
            for tl in 0..<count {
                let o = tl * bins
                for ch in 0..<2 {
                    let base = (ch * tt + tl) * f
                    var sumV: Float = 0, sumA: Float = 0
                    for k in 0..<f {
                        let v = yv[base + k], a = ya[base + k]
                        let den = v * v + a * a + eps
                        let mv = (v * v + eps / 2) / den, ma = (a * a + eps / 2) / den
                        if ch == 0 { maskL[0][k] = mv; maskL[1][k] = ma } else { maskR[0][k] = mv; maskR[1][k] = ma }
                        sumV += mv; sumA += ma
                    }
                    // above the models' bins: each frame's average share
                    let avgV = sumV / Float(f), avgA = sumA / Float(f)
                    for k in f..<bins {
                        if ch == 0 { maskL[0][k] = avgV; maskL[1][k] = avgA } else { maskR[0][k] = avgV; maskR[1][k] = avgA }
                    }
                }
                for p in 0..<2 {
                    // both channels in one inverse FFT: left + i·right, both real
                    for k in 0..<bins {
                        let ml = maskL[p][k], mr = maskR[p][k]
                        let ar = sRe[0][o + k] * ml, ai = sIm[0][o + k] * ml // left's bin
                        let br = sRe[1][o + k] * mr, bi = sIm[1][o + k] * mr // right's bin
                        // Z[k] = A + iB; Z[N-k] = conj(A) + i·conj(B)
                        re[k] = ar - bi; im[k] = ai + br
                        if k >= 1 && k < n / 2 { re[n - k] = ar + bi; im[n - k] = -ai + br }
                    }
                    // as numpy's irfft: the DC and middle bins' imaginary parts don't count
                    re[0] = sRe[0][o] * maskL[p][0]; im[0] = sRe[1][o] * maskR[p][0]
                    re[n / 2] = sRe[0][o + n / 2] * maskL[p][n / 2]; im[n / 2] = sRe[1][o + n / 2] * maskR[p][n / 2]
                    fft.run(&re, &im, inverse: true)
                    let off = tl * h
                    acc[p].withUnsafeMutableBufferPointer { a in
                        for i in 0..<n {
                            a[2 * (off + i)] += re[i] * win[i]
                            a[2 * (off + i) + 1] += im[i] * win[i]
                        }
                    }
                }
            }

            // done: everything before where the next block's first frame begins (all of it, after the last)
            let last = b == blocks - 1
            let doneUpTo = last ? n + total : min(n + total, (t0 + tt) * h)
            let from = b * tt * h // acc[p][0] is this padded sample
            for p in 0..<2 {
                var count = 0
                if doneUpTo > emitted {
                    for s in emitted..<doneUpTo {
                        let k = s - from
                        let w = wsum[s % h]
                        out[2 * count] = acc[p][2 * k] / w
                        out[2 * count + 1] = acc[p][2 * k + 1] / w
                        count += 1
                    }
                }
                if count > 0 { try part(p, out, count) }
                // the overlap moves to the front for the next block
                let keep = 2 * (span - tt * h)
                acc[p].withUnsafeMutableBufferPointer { a in
                    for i in 0..<keep { a[i] = a[2 * tt * h + i] }
                    for i in keep..<(2 * span) { a[i] = 0 }
                }
            }
            emitted = max(emitted, doneUpTo)
            block(b + 1, blocks)
        }
    }
}
