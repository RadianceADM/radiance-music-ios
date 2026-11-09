import Foundation
import XCTest
@testable import RadianceKit

/** The splitter's sound work, with pretend models (the real ones run on the iPhone). */
final class SplitTests: XCTestCase {
    func testTheFFTGoesThereAndBack() {
        let fft = Fft(16)
        let x: [Float] = (0..<16).map { sin(Float($0) * 0.7) }
        var re = x, im = [Float](repeating: 0, count: 16)
        fft.run(&re, &im, inverse: false)
        // a real signal's spectrum mirrors itself
        XCTAssertEqual(re[3], re[13], accuracy: 1e-4)
        XCTAssertEqual(im[3], -im[13], accuracy: 1e-4)
        fft.run(&re, &im, inverse: true)
        for i in 0..<16 { XCTAssertEqual(re[i], x[i], accuracy: 1e-5); XCTAssertEqual(im[i], 0, accuracy: 1e-5) }
    }

    /** Two parts that each take half: each is half the song, and they add up to it (the overlap-add is exact). */
    func testThePartsAddUpToTheSong() throws {
        let total = 44100 * 3 + 777 // not a whole number of blocks
        var x = [Float](repeating: 0, count: 2 * total)
        var seed: UInt32 = 7
        for i in 0..<(2 * total) { seed = seed &* 1103515245 &+ 12345; x[i] = Float(Int(seed >> 16) % 2000 - 1000) / 1000 }
        var parts: [[Float]] = [[], []]
        var blocks = 0
        try x.withUnsafeBufferPointer { buf in
            try Spleeter.run(buf, total: total, models: { input, shape in
                XCTAssertEqual(shape, [2, 1, 512, 1024])
                return (input, input) // the same loudness for both: half each
            }, part: { p, b, frames in parts[p] += b[0..<(2 * frames)] }, block: { done, _ in blocks = done })
        }
        XCTAssertGreaterThan(blocks, 0)
        XCTAssertEqual(parts[0].count, 2 * total)
        XCTAssertEqual(parts[1].count, 2 * total)
        var worst: Float = 0
        for i in 0..<(2 * total) {
            worst = max(worst, abs(parts[0][i] + parts[1][i] - x[i]))
            XCTAssertEqual(parts[0][i], x[i] / 2, accuracy: 2e-3)
        }
        XCTAssertLessThan(worst, 2e-3)
    }

    /** A model that hears only singing: the vocals are the song, the music is silence. */
    func testAllSingingGoesToTheVocals() throws {
        let total = 20000
        let x: [Float] = (0..<(2 * total)).map { sin(Float($0) * 0.05) * 0.5 }
        var parts: [[Float]] = [[], []]
        try x.withUnsafeBufferPointer { buf in
            try Spleeter.run(buf, total: total, models: { input, _ in (input, [Float](repeating: 0, count: input.count)) },
                             part: { p, b, frames in parts[p] += b[0..<(2 * frames)] })
        }
        for i in stride(from: 0, to: 2 * total, by: 97) {
            XCTAssertEqual(parts[0][i], x[i], accuracy: 2e-3)
            XCTAssertEqual(parts[1][i], 0, accuracy: 2e-3)
        }
    }
}
