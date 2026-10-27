import Foundation
import Testing
@testable import DharmaGardenCore

struct ModalInstrumentTests {
    private func rms(_ x: ArraySlice<Float>) -> Double {
        (x.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(1, x.count))).squareRoot()
    }

    /// Strongest frequency between 0.7f and 1.3f in a one-second window, found with a Goertzel sweep.
    private func peakFrequency(_ x: [Float], near f: Double, sampleRate: Double) -> Double {
        var best = 0.0, bestPower = -1.0
        var hz = f * 0.7
        while hz < f * 1.3 {
            let w = 2 * Double.pi * hz / sampleRate
            var re = 0.0, im = 0.0
            for (i, s) in x.enumerated() {
                re += Double(s) * cos(w * Double(i))
                im += Double(s) * sin(w * Double(i))
            }
            let p = re * re + im * im
            if p > bestPower { bestPower = p; best = hz }
            hz += 0.5
        }
        return best
    }

    @Test func fundamentalIsInTune() {
        for midi in [50, 62, 69] {
            let buf = ModalInstrument.render(
                events: [HandpanEvent(time: 0, midi: midi, velocity: 0.6)], duration: 1.5, seed: 3)
            let window = Array(buf.left[12_000..<60_000]) // ~1 s, after the attack
            let f = ModalInstrument.frequency(midi: midi)
            let found = peakFrequency(window, near: f, sampleRate: buf.sampleRate)
            #expect(abs(found - f) / f < 0.01, "midi \(midi): expected \(f), found \(found)")
        }
    }

    @Test func outputIsFiniteAndBounded() {
        let events = (0..<12).map {
            HandpanEvent(time: Double($0) * 0.3, midi: ModalInstrument.scale[$0 % 9], velocity: 1.0)
        }
        let buf = ModalInstrument.render(events: events, duration: 6, seed: 1)
        #expect(buf.left.allSatisfy { $0.isFinite && abs($0) <= 1 })
        #expect(buf.right.allSatisfy { $0.isFinite && abs($0) <= 1 })
        #expect(buf.left.contains { abs($0) > 0.05 })
    }

    @Test func noteDecays() {
        let buf = ModalInstrument.render(
            events: [HandpanEvent(time: 0, midi: 50, velocity: 0.6)], duration: 6, seed: 1)
        let sr = Int(buf.sampleRate)
        let first = rms(buf.left[0..<(sr / 2)])
        let last = rms(buf.left[(buf.left.count - sr / 2)...])
        #expect(last < first * 0.5)
        #expect(last > 0) // still ringing: a handpan is long
    }

    @Test func deterministicForSeed() {
        let events = [HandpanEvent(time: 0.1, midi: 57, velocity: 0.4), HandpanEvent(time: 0.7, midi: 64, velocity: 0.5)]
        let a = ModalInstrument.render(events: events, duration: 2, seed: 9)
        let b = ModalInstrument.render(events: events, duration: 2, seed: 9)
        let c = ModalInstrument.render(events: events, duration: 2, seed: 10)
        #expect(a.left == b.left && a.right == b.right)
        #expect(a.left != c.left)
    }
}
