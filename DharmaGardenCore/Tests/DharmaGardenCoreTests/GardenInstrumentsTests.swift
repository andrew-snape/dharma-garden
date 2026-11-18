import Foundation
import Testing
@testable import DharmaGardenCore

/// Kalimba, felt piano, music box and tines, plus the proof that teaching the improviser other scales left the
/// handpan's pieces exactly as they were.
struct GardenInstrumentsTests {
    // MARK: Helpers

    static func fingerprint(_ events: [HandpanEvent]) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ x: UInt64) { h = (h ^ x) &* 0x0000_0100_0000_01B3 }
        for e in events { mix(e.time.bitPattern); mix(UInt64(e.midi)); mix(e.velocity.bitPattern) }
        return h
    }

    private func rms(_ x: ArraySlice<Float>) -> Double {
        (x.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(1, x.count))).squareRoot()
    }

    /// Amplitude of one frequency, by the Goertzel recurrence (one multiply-add a sample, so it stays quick in debug).
    private func amplitude(_ x: ArraySlice<Float>, at hz: Double, sampleRate: Double) -> Double {
        let coeff = 2 * cos(2 * Double.pi * hz / sampleRate)
        var s1 = 0.0, s2 = 0.0
        for v in x {
            let s = Double(v) + coeff * s1 - s2
            s2 = s1; s1 = s
        }
        let power = s1 * s1 + s2 * s2 - coeff * s1 * s2
        return max(0, power).squareRoot() * 2 / Double(max(1, x.count))
    }

    /// Strongest frequency between 0.8f and 1.2f, found with a Goertzel sweep.
    private func peakFrequency(_ x: ArraySlice<Float>, near f: Double, sampleRate: Double) -> Double {
        var best = 0.0, bestPower = -1.0
        var hz = f * 0.8
        let step = max(0.5, f * 0.002)
        while hz < f * 1.2 {
            let a = amplitude(x, at: hz, sampleRate: sampleRate)
            if a > bestPower { bestPower = a; best = hz }
            hz += step
        }
        return best
    }

    private func one(_ instrument: GardenInstrument, midi: Int, velocity: Double = 0.6, seconds: Double = 4,
                     seed: UInt64 = 3) -> StereoBuffer {
        instrument.render(events: [HandpanEvent(time: 0.1, midi: midi, velocity: velocity)], duration: seconds,
                          seed: seed)
    }

    // MARK: The handpan is untouched

    /// Fingerprints of `Improviser.piece` captured from the code as it was before the improviser learned about
    /// scales. If one of these changes, the approved handpan pieces have changed.
    static let handpanFingerprints: [(PieceMood, UInt64, Double, Int, UInt64)] = [
        (.day, 1, 4, 119, 0x6576e0e79346225c),
        (.dusk, 3, 4, 101, 0xc116fc545e5e2532),
        (.night, 2, 3, 46, 0x0227c426588cfed7),
        (.dawn, 5, 4, 110, 0x1355c0cd8f0bab03),
        (.rain, 4, 4, 89, 0xeac0c7867301729b),
    ]

    @Test func handpanImproviserOutputIsUnchanged() {
        for (mood, seed, minutes, count, hash) in Self.handpanFingerprints {
            let events = Improviser.piece(mood: mood, seed: seed, minutes: minutes)
            #expect(events.count == count, "\(mood) \(seed)")
            #expect(Self.fingerprint(events) == hash, "\(mood) \(seed)")
            // The explicit handpan scale is the default, not a second behaviour.
            let explicit = Improviser.piece(mood: mood, seed: seed, minutes: minutes, scale: .handpan)
            #expect(explicit == events)
        }
    }

    @Test func handpanThroughTheSwitchIsTheSameRender() {
        let events = Improviser.piece(mood: .day, seed: 1, minutes: 0.5)
        let a = ModalInstrument.render(events: events, duration: 30, seed: 42)
        let b = GardenInstrument.handpan.render(events: events, duration: 30, seed: 42)
        #expect(a.left == b.left && a.right == b.right)
    }

    // MARK: The improviser in other scales

    @Test(arguments: [GardenInstrument.kalimba, .piano, .musicbox, .tines])
    func piecesStayInTheScaleAndAreDeterministic(_ instrument: GardenInstrument) {
        let scale = instrument.pieceScale
        for mood in PieceMood.allCases {
            let a = Improviser.piece(mood: mood, seed: 7, minutes: 4, scale: scale)
            #expect(a == Improviser.piece(mood: mood, seed: 7, minutes: 4, scale: scale))
            #expect(a != Improviser.piece(mood: mood, seed: 8, minutes: 4, scale: scale))
            #expect(a.allSatisfy { instrument.notes.contains($0.midi) })
            #expect(a.allSatisfy { $0.time >= 0 && $0.time < 240 && (0.1...0.6).contains($0.velocity) })
            let m = PieceMetrics(events: a, duration: 240)
            #expect(m.notesPerMinute < 40, "\(instrument) \(mood): \(m.notesPerMinute) notes/min")
            #expect(m.notesPerMinute > 4)
            // Sparse: nothing like a wall of notes, and silences stay silences.
            #expect(m.maxIn10s <= 12, "\(instrument) \(mood)")
        }
    }

    @Test func eachScaleHasItsHomeAndCadenceNotesInD() {
        for instrument in GardenInstrument.allCases {
            let s = instrument.pieceScale
            #expect(s.notes[s.home] % 12 == 2, "\(instrument) home should be a D")
            #expect([2, 9].contains(s.notes[s.lowFifth] % 12))
            #expect([2, 9].contains(s.notes[s.high] % 12))
            #expect(s.ring.upperBound < s.notes.count)
        }
        #expect(KalimbaInstrument.scale.map { $0 % 12 }.allSatisfy { [2, 4, 6, 9, 11].contains($0) }, "D major pentatonic")
        let dorian: Set<Int> = [2, 4, 5, 7, 9, 11, 0]
        #expect(FeltPianoInstrument.scale.allSatisfy { dorian.contains($0 % 12) })
        #expect(TinesInstrument.scale.allSatisfy { dorian.contains($0 % 12) })
        #expect(KalimbaInstrument.scale.count == 9)
        #expect(FeltPianoInstrument.scale.first == 45 && FeltPianoInstrument.scale.last == 74)
        #expect(TinesInstrument.scale.first == 50 && TinesInstrument.scale.last == 69)
    }

    @Test func onlyThePianoPlaysALeftHand() {
        // The piano sometimes sounds a soft low note together with the start of a phrase; nobody else does.
        func lowUnderlays(_ instrument: GardenInstrument) -> Int {
            var count = 0
            for seed in 1...6 {
                let piece = Improviser.compose(mood: .day, seed: UInt64(seed), minutes: 4, scale: instrument.pieceScale)
                for phrase in piece.phrases where phrase.events.count > 1 {
                    let first = phrase.events[0]
                    if phrase.events.dropFirst().contains(where: { $0.midi < first.midi - 7 && $0.time - first.time < 0.05 }) {
                        count += 1
                    }
                }
            }
            return count
        }
        #expect(lowUnderlays(.piano) > 0)
        #expect(lowUnderlays(.tines) == 0)
        #expect(lowUnderlays(.kalimba) == 0)
    }

    // MARK: The instruments

    @Test(arguments: [GardenInstrument.kalimba, .piano, .musicbox, .tines])
    func fundamentalIsInTune(_ instrument: GardenInstrument) {
        let notes = instrument.notes
        // Skip the very lowest keys of the piano, whose fundamental is weak by design.
        let picks = [notes[notes.count / 3], notes[notes.count / 2], notes[notes.count - 2]]
        for midi in picks {
            let buf = one(instrument, midi: midi)
            let window = buf.left[12_000..<36_000] // 0.5 s, after the attack
            let f = ModalInstrument.frequency(midi: midi)
            let found = peakFrequency(window, near: f, sampleRate: buf.sampleRate)
            #expect(abs(found - f) / f < 0.01, "\(instrument) midi \(midi): expected \(f), found \(found)")
        }
    }

    @Test(arguments: [GardenInstrument.kalimba, .piano, .musicbox, .tines])
    func outputIsFiniteBoundedAndDeterministic(_ instrument: GardenInstrument) {
        let events = (0..<8).map {
            HandpanEvent(time: Double($0) * 0.25, midi: instrument.notes[$0 * 3 % instrument.notes.count], velocity: 1.0)
        }
        let a = instrument.render(events: events, duration: 4, seed: 1)
        #expect(a.left.allSatisfy { $0.isFinite && abs($0) <= 1 })
        #expect(a.right.allSatisfy { $0.isFinite && abs($0) <= 1 })
        #expect(a.left.contains { abs($0) > 0.05 })
        let b = instrument.render(events: events, duration: 4, seed: 1)
        #expect(a.left == b.left && a.right == b.right)
        let c = instrument.render(events: events, duration: 4, seed: 2)
        #expect(a.left != c.left)
        // Notes after the end, or before the start, are ignored rather than crashing.
        let odd = instrument.render(events: [HandpanEvent(time: 99, midi: 62, velocity: 0.5),
                                             HandpanEvent(time: -1, midi: 62, velocity: 0.5)], duration: 2)
        #expect(odd.left.allSatisfy { $0 == 0 })
    }

    @Test(arguments: [GardenInstrument.kalimba, .piano, .musicbox, .tines])
    func noteDecaysAndStartsWithoutAClick(_ instrument: GardenInstrument) {
        let midi = instrument.notes[instrument.notes.count / 2]
        let buf = one(instrument, midi: midi, seconds: 8)
        let early = rms(buf.left[7_000..<14_000])
        let late = rms(buf.left[(48_000 * 4)..<(48_000 * 4 + 7_000)])
        let tail = rms(buf.left[(48_000 * 7)..<(48_000 * 7 + 7_000)])
        #expect(early > 0)
        #expect(late < early * 0.3, "\(instrument): still \(late / early) of the opening after 4 s")
        #expect(tail <= late)
        // Silence before the note (the piano's key noise may lead it by a few milliseconds), no step at the first
        // sample, no jump between neighbouring samples in the first millisecond, and a tail faded to nothing.
        let start = 4_800
        let peak = buf.left.map(abs).max() ?? 1
        #expect(buf.left[0..<(start - 480)].allSatisfy { $0 == 0 })
        #expect(abs(buf.left[start]) < peak * 0.005)
        let jumps = (start + 1..<start + 48).map { abs(buf.left[$0] - buf.left[$0 - 1]) }
        #expect(jumps.max()! < peak * 0.1)
        #expect(tail < Double(peak) * 0.01)
    }

    @Test func kalimbaRingsForSeconds() {
        // Fundamental T60 is 2-4 s (about 3.2 s here): at 2 s it is still audible, after 6 s long gone.
        let buf = one(.kalimba, midi: 62, seconds: 8)
        let a = rms(buf.left[7_000..<14_000])
        #expect(rms(buf.left[(48_000 * 2)..<(48_000 * 2 + 7_000)]) > a * 0.005)
        #expect(rms(buf.left[(48_000 * 6)..<(48_000 * 6 + 7_000)]) < a * 0.003)
    }

    @Test func tinesBellIsVeryQuietAndTransient() {
        let midi = 57
        let f = ModalInstrument.frequency(midi: midi)
        let buf = one(.tines, midi: midi, velocity: 0.55, seconds: 6)
        let sr = buf.sampleRate
        // Compare against the actual bell (7x, within a percent) and the fundamental, in the first 150 ms.
        let attack = buf.left[4_800..<(4_800 + 7_200)]
        let fundamental = amplitude(attack, at: f, sampleRate: sr)
        var bell = 0.0
        var r = 6.9
        while r < 7.1 { bell = max(bell, amplitude(attack, at: f * r, sampleRate: sr)); r += 0.005 }
        #expect(20 * log10(bell / fundamental) < -28, "bell at \(20 * log10(bell / fundamental)) dB")
        // And by 1.5 s it has gone.
        let later = buf.left[(48_000 * 3 / 2)..<(48_000 * 3 / 2 + 7_200)]
        var bellLate = 0.0
        r = 6.9
        while r < 7.1 { bellLate = max(bellLate, amplitude(later, at: f * r, sampleRate: sr)); r += 0.005 }
        #expect(bellLate < bell * 0.1)
    }

    @Test func tinesTremoloCanBeTurnedOffAndStaysGentle() {
        let events = [HandpanEvent(time: 0.1, midi: 57, velocity: 0.5)]
        let off = TinesInstrument.render(events: events, duration: 4, seed: 1, tremolo: 0)
        let on = TinesInstrument.render(events: events, duration: 4, seed: 1, tremolo: 0.15)
        let silly = TinesInstrument.render(events: events, duration: 4, seed: 1, tremolo: 5)  // capped at 0.15
        #expect(off.left != on.left)
        #expect(on.left == silly.left)
        // With it off the two ears carry the same note (just panned); with it on they differ over time.
        let ratio = { (b: StereoBuffer, a: Int, z: Int) in rms(b.left[a..<z]) / rms(b.right[a..<z]) }
        #expect(abs(ratio(off, 10_000, 17_000) - ratio(off, 100_000, 107_000)) < 0.02)
        #expect(abs(ratio(on, 10_000, 17_000) - ratio(on, 100_000, 107_000)) > 0.01)
        // A tremolo whose average gain is 1 does not change the loudness.
        let loudOn = rms(on.left[0..<192_000]) + rms(on.right[0..<192_000])
        let loudOff = rms(off.left[0..<192_000]) + rms(off.right[0..<192_000])
        #expect(abs(loudOn / loudOff - 1) < 0.05)
    }

    @Test func pianoPartialsAreStretchedMoreInTheTreble() {
        #expect(FeltPianoInstrument.inharmonicity(midi: 45) >= 0.0002)
        #expect(FeltPianoInstrument.inharmonicity(midi: 74) <= 0.0005 + 1e-9)
        #expect(FeltPianoInstrument.inharmonicity(midi: 74) > FeltPianoInstrument.inharmonicity(midi: 45))
    }

    @Test func pianoIsMellowMostEnergyBelowTwoKilohertz() {
        let buf = one(.piano, midi: 60, velocity: 0.55, seconds: 4)
        let x = buf.left[0..<(48_000 * 2)]
        var low = 0.0, high = 0.0
        var hz = 100.0
        while hz < 6000 {
            let a = amplitude(x, at: hz, sampleRate: buf.sampleRate)
            if hz < 2000 { low += a * a } else { high += a * a }
            hz += 25
        }
        #expect(high < low * 0.01, "energy above 2 kHz is \(high / low) of the rest")
    }
}
