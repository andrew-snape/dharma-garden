import Foundation

/// A modal-synthesis music box, in D dorian. This is the fallback for the Rural UK theme if the felt piano does
/// not convince; it is cheap to keep because it shares the kit.
///
/// A steel comb tine: a strong fundamental that rings a few seconds, two inharmonic upper modes near 2.9 and
/// 5.4 times the pitch that fade quickly (the "tinkle"), and a bright but soft pluck from the cylinder pin,
/// which is a very short rounded pulse. A little cabinet resonance lends it a box. Deterministic for a seed.
public enum MusicBoxInstrument {
    /// D4 E4 F4 G4 A4 B4 C5 D5 E5 F5 G5 A5.
    public static let scale: [Int] = [62, 64, 65, 67, 69, 71, 72, 74, 76, 77, 79, 81]

    public static let pieceScale = PieceScale(
        notes: scale, anchor: 0, ring: 1...11, home: 7, lowFifth: 4, high: 11, questions: [9, 6],
        registerOffset: 3)

    static func fundamentalT60(midi: Int) -> Double { min(4.0, max(2.0, 4.0 - Double(midi - 62) * 0.1)) }

    public static func render(
        events: [HandpanEvent],
        duration: Double,
        seed: UInt64 = 1,
        sampleRate: Double = ModalInstrument.defaultSampleRate
    ) -> StereoBuffer {
        let total = max(0, Int(duration * sampleRate))
        var left = [Float](repeating: 0, count: total)
        var right = [Float](repeating: 0, count: total)
        var cabRng = SplitMix(seed: seed &* 0xC2B2_AE3D_27D4_EB4F &+ 43)
        let cabinet = 420 * (1 + 0.06 * cabRng.signed())

        left.withUnsafeMutableBufferPointer { lp in
            right.withUnsafeMutableBufferPointer { rp in
                guard total > 0 else { return }
                let sink = ModalKit.Sink(left: lp, right: rp, total: total, sampleRate: sampleRate)
                for (index, event) in events.enumerated() {
                    let start = Int((event.time * sampleRate).rounded())
                    guard start >= 0, start < total else { continue }
                    let v = min(1, max(0, event.velocity))
                    let f0 = ModalInstrument.frequency(midi: event.midi)
                    var nr = ModalKit.noteRng(seed: seed, midi: event.midi, salt: 0x4D42)
                    let modeA = 2.8 + 0.2 * nr.unit()
                    let modeB = 5.4 * (1 + 0.02 * nr.signed())
                    let beat = 0.2 + 0.6 * nr.unit()
                    let pan = ModalKit.panFor(midi: event.midi, seed: seed, width: 0.3)
                    var rng = ModalKit.hitRng(seed: seed, index: index, salt: 0x4D42)
                    let velGain = 0.3 * pow(v, 1.15)
                    let hitJitter = pow(10, rng.signed() * 0.7 / 20)
                    let soft = 1 - v
                    let pulse = ModalKit.strikePulse(sigmaMs: 0.2 - 0.06 * v, sampleRate: sampleRate, rng: &rng)
                    func level(_ db: Double) -> Double { velGain * hitJitter * pow(10, db / 20) }
                    let t60 = fundamentalT60(midi: event.midi)

                    sink.pair(freq: f0, beat: beat, amp: level(0), t60: t60, pan: pan, spread: 0.08,
                              excitation: pulse, floor: 0.3, start: start)
                    sink.mode(freq: f0 * modeA, amp: level(-17 - 8 * soft), t60: 0.7, pan: pan,
                              excitation: pulse, floor: 0.3, start: start)
                    sink.mode(freq: f0 * modeB, amp: level(-24 - 8 * soft), t60: 0.35, pan: pan,
                              excitation: pulse, floor: 0.3, start: start)
                    sink.mode(freq: cabinet, amp: level(-22), t60: 0.12, pan: 0, excitation: pulse,
                              floor: 0.3, start: start)
                    sink.noise(start: start, ms: 14, t60: 0.008, lowPassHz: 3000, amp: level(-30),
                               fadeInMs: 0.6, pan: pan, rng: &rng)
                }
            }
        }
        ModalKit.clampOutput(&left, &right)
        return StereoBuffer(left: left, right: right, sampleRate: sampleRate)
    }
}
