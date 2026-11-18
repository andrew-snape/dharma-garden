import Foundation

/// A modal-synthesis kalimba (thumb piano) in D major pentatonic.
///
/// Metal tines clamped over a wooden box. Each note is a near-pure fundamental that rings a few seconds (a
/// pair of resonators a fraction of a hertz apart, because a tine wobbles in two planes), two weak and quick
/// tine partials that sit well above the octave and are not harmonics at all (that is the "plink"), a short
/// woody box resonance in the low hundreds of hertz that every note excites (that is the warmth), and a soft
/// thumb: a rounded pulse, a puff of low-passed noise and the faintest buzz of the tine against its bridge.
/// Everything is deterministic for a seed.
public enum KalimbaInstrument {
    /// A3 B3 D4 E4 F#4 A4 B4 D5 E5: nine tines, low to high.
    public static let scale: [Int] = [57, 59, 62, 64, 66, 69, 71, 74, 76]

    /// How the improviser should use these nine tines. The lowest A is the anchor, D4 is home.
    public static let pieceScale = PieceScale(
        notes: scale, anchor: 0, ring: 1...8, home: 2, lowFifth: 0, high: 5, questions: [4, 3],
        registerOffset: -1)

    /// Low tines ring longer, 3.6 s down to about 2.3 s at the top.
    static func fundamentalT60(midi: Int) -> Double { max(1.8, 3.6 - Double(midi - 57) * 0.07) }

    public static func render(
        events: [HandpanEvent],
        duration: Double,
        seed: UInt64 = 1,
        sampleRate: Double = ModalInstrument.defaultSampleRate
    ) -> StereoBuffer {
        let total = max(0, Int(duration * sampleRate))
        var left = [Float](repeating: 0, count: total)
        var right = [Float](repeating: 0, count: total)

        // The box belongs to the instrument, not to a note: two resonances, fixed for the seed.
        var boxRng = SplitMix(seed: seed &* 0xC2B2_AE3D_27D4_EB4F &+ 17)
        let boxA = 240 * (1 + 0.06 * boxRng.signed())
        let boxB = 345 * (1 + 0.06 * boxRng.signed())

        left.withUnsafeMutableBufferPointer { lp in
            right.withUnsafeMutableBufferPointer { rp in
                guard total > 0 else { return }
                let sink = ModalKit.Sink(left: lp, right: rp, total: total, sampleRate: sampleRate)
                for (index, event) in events.enumerated() {
                    let start = Int((event.time * sampleRate).rounded())
                    guard start >= 0, start < total else { continue }
                    let v = min(1, max(0, event.velocity))
                    let f0 = ModalInstrument.frequency(midi: event.midi)
                    var nr = ModalKit.noteRng(seed: seed, midi: event.midi, salt: 0x4B41)
                    let tineA = 5.4 + 0.4 * nr.unit()           // 5.4...5.8 x the fundamental
                    let tineB = 5.9 + 0.4 * nr.unit()           // 5.9...6.3 x
                    let beat = 0.3 + 0.9 * nr.unit()
                    let buzzHz = 1800 + 500 * nr.unit()
                    let pan = ModalKit.panFor(midi: event.midi, seed: seed, width: 0.3)
                    var rng = ModalKit.hitRng(seed: seed, index: index, salt: 0x4B41)
                    let velGain = 0.32 * pow(v, 0.9)
                    let hitJitter = pow(10, rng.signed() * 0.7 / 20)
                    let soft = 1 - v

                    // A rounded thumb, the fleshy pad rather than the nail: softer plucks are rounder still.
                    let pulse = ModalKit.strikePulse(sigmaMs: 0.75 - 0.2 * v, sampleRate: sampleRate, rng: &rng)
                    func level(_ db: Double) -> Double { velGain * hitJitter * pow(10, db / 20) }
                    // Tine partials of the top notes would sit at 3-4 kHz; let them fade as the pitch rises, so
                    // the high notes plink softly rather than glassily.
                    func airy(_ hz: Double) -> Double { 1 / (1 + pow(hz / 1800, 2)) }
                    let t60 = fundamentalT60(midi: event.midi)

                    sink.pair(freq: f0, beat: beat, amp: level(0), t60: t60, pan: pan, spread: 0.10,
                              excitation: pulse, floor: 0.3, start: start)
                    // The tine's own non-harmonic partials: weak, and gone in a third of a second.
                    sink.mode(freq: f0 * tineA, amp: level(-33 - 9 * soft) * airy(f0 * tineA), t60: 0.30, pan: pan,
                              excitation: pulse, floor: 0.3, start: start)
                    sink.mode(freq: f0 * tineB, amp: level(-38 - 9 * soft) * airy(f0 * tineB), t60: 0.18, pan: pan,
                              excitation: pulse, floor: 0.3, start: start)
                    // The wooden box: short and low, the same whichever note was plucked.
                    sink.mode(freq: boxA, amp: level(-15), t60: 0.16, pan: -0.1, excitation: pulse,
                              floor: 0.3, start: start)
                    sink.mode(freq: boxB, amp: level(-19), t60: 0.11, pan: 0.1, excitation: pulse,
                              floor: 0.3, start: start)
                    // The tine touching its bridge: a faint, fast buzz.
                    sink.mode(freq: buzzHz, amp: level(-52 - 10 * soft), t60: 0.09, pan: pan,
                              excitation: pulse, floor: 0.3, start: start)
                    // The thumb itself: a soft puff of noise.
                    sink.noise(start: start, ms: 30, t60: 0.02, lowPassHz: 1000, amp: level(-42),
                               fadeInMs: 2, pan: pan, rng: &rng)
                }
            }
        }
        ModalKit.clampOutput(&left, &right)
        return StereoBuffer(left: left, right: right, sampleRate: sampleRate)
    }
}
