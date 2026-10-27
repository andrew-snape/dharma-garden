import Foundation

/// A modal-synthesis felt piano in D dorian: a small upright with the mute felt down.
///
/// Each note is a stack of string partials, slightly stretched sharp as real stiff strings are (the stretch grows
/// with pitch), struck by a soft Gaussian hammer so the upper partials are rolled off before they start.
/// Every partial has two stages, as a piano does: a prompt sound that fades in about a second, then a quieter
/// after-sound from two or three strings that are not quite in unison, so it beats slowly. A few short, low
/// soundboard resonances give the wood, and the attack carries a very soft low-passed felt thump and a whisper
/// of key noise. Most of the energy sits below about 2 kHz. Deterministic for a seed.
public enum FeltPianoInstrument {
    /// A2 B2 C3 D3 E3 F3 G3 A3 B3 C4 D4 E4 F4 G4 A4 B4 C5 D5.
    public static let scale: [Int] = [45, 47, 48, 50, 52, 53, 55, 57, 59, 60, 62, 64, 65, 67, 69, 71, 72, 74]

    /// The improviser plays the middle of the keyboard (G3 up to D5); D3 is the anchor and the low A2 or D3 is
    /// sometimes sounded softly under a phrase, like a left hand.
    public static let pieceScale = PieceScale(
        notes: scale, anchor: 3, ring: 6...17, home: 10, lowFifth: 7, high: 14, questions: [12, 9],
        registerOffset: 6, underlay: .init(indices: [0, 3], chance: 0.30))

    /// Stiffness of the string: a little stretch that grows toward the treble.
    static func inharmonicity(midi: Int) -> Double {
        0.0002 + 0.0003 * min(1, max(0, Double(midi - 45) / 29))
    }

    public static func render(
        events: [HandpanEvent],
        duration: Double,
        seed: UInt64 = 1,
        sampleRate: Double = ModalInstrument.defaultSampleRate
    ) -> StereoBuffer {
        let total = max(0, Int(duration * sampleRate))
        var left = [Float](repeating: 0, count: total)
        var right = [Float](repeating: 0, count: total)

        // The soundboard belongs to the instrument: three broad low resonances, fixed for the seed.
        var boardRng = SplitMix(seed: seed &* 0xC2B2_AE3D_27D4_EB4F &+ 29)
        let board: [(hz: Double, db: Double, t60: Double)] = [
            (95 * (1 + 0.08 * boardRng.signed()), -24, 0.35),
            (150 * (1 + 0.08 * boardRng.signed()), -27, 0.22),
            (240 * (1 + 0.08 * boardRng.signed()), -30, 0.18),
        ]

        left.withUnsafeMutableBufferPointer { lp in
            right.withUnsafeMutableBufferPointer { rp in
                guard total > 0 else { return }
                let sink = ModalKit.Sink(left: lp, right: rp, total: total, sampleRate: sampleRate)
                for (index, event) in events.enumerated() {
                    let start = Int((event.time * sampleRate).rounded())
                    guard start >= 0, start < total else { continue }
                    let v = min(1, max(0, event.velocity))
                    let midi = event.midi
                    let f0 = ModalInstrument.frequency(midi: midi)
                    var nr = ModalKit.noteRng(seed: seed, midi: midi, salt: 0x5049)
                    let basePan = ModalKit.panFor(midi: midi, seed: seed, width: 0.28)
                    let beatBase = 0.25 + 0.6 * nr.unit()
                    var rng = ModalKit.hitRng(seed: seed, index: index, salt: 0x5049)
                    let velGain = 0.34 * pow(v, 0.9)
                    let hitJitter = pow(10, rng.signed() * 0.6 / 20)
                    let soft = 1 - v
                    let b = inharmonicity(midi: midi)

                    // The felt hammer: a Gaussian about half a millisecond wide. No floor, so it rolls off the top.
                    let pulse = ModalKit.strikePulse(sigmaMs: 0.6 - 0.12 * v, sampleRate: sampleRate, rng: &rng)

                    // Prompt sound lasts about a second; the after-sound is longer in the bass.
                    let promptBase = min(1.6, max(0.7, 1.6 - 0.02 * Double(midi - 45)))
                    let slowBase = min(7.0, max(2.2, 7.0 * pow(0.5, Double(midi - 45) / 30)))

                    var n = 1
                    while true {
                        let nd = Double(n)
                        let freq = f0 * nd * (1 + b * nd * nd).squareRoot()
                        if freq > 6000 || freq > sampleRate * 0.45 { break }
                        // Felt-muted spectrum: steep, steeper still when played softly, with the comb of a hammer
                        // that meets the string an eighth of the way along.
                        let comb = max(0.3, abs(sin(Double.pi * nd * 0.125)) / sin(Double.pi * 0.125))
                        let db = -5.0 * (nd - 1) - 0.45 * (nd - 1) * (nd - 1) - soft * 1.2 * (nd - 1)
                            + 20 * log10(min(1.0, comb))
                        if db < -62 { n += 1; if n > 16 { break }; continue }

                        let promptT60 = promptBase / (1 + 0.3 * (nd - 1))
                        let slowT60 = max(0.3, slowBase / (1 + 0.45 * (nd - 1)))
                        let amp = velGain * hitJitter * pow(10, db / 20)
                        // Slight random leaning per partial keeps the stereo image from collapsing to a point.
                        let pan = basePan + 0.04 * nr.signed()
                        sink.mode(freq: freq, amp: amp, t60: promptT60, pan: pan, excitation: pulse, floor: 1,
                                  start: start)
                        // The after-sound: two strings in near-unison, a third of the loudness (-9 dB) at the root,
                        // and proportionally less in the upper partials.
                        let slowDb = -9.0 - 1.5 * (nd - 1)
                        let beat = beatBase * (0.6 + 0.4 * nd.squareRoot())
                        sink.pair(freq: freq, beat: beat, amp: amp * pow(10, slowDb / 20), t60: slowT60, pan: pan,
                                  spread: 0.10, excitation: pulse, floor: 1, start: start)
                        n += 1
                        if n > 16 { break }
                    }

                    // Soundboard wood: short and low.
                    for mode in board {
                        sink.mode(freq: mode.hz, amp: velGain * hitJitter * pow(10, mode.db / 20), t60: mode.t60,
                                  pan: 0, excitation: pulse, floor: 1, start: start)
                    }
                    // Felt thump (low, soft, rounded start) and a whisper of key noise.
                    sink.noise(start: start, ms: 90, t60: 0.06, lowPassHz: 180, amp: velGain * pow(10, -23.0 / 20),
                               fadeInMs: 3, pan: basePan * 0.5, rng: &rng)
                    sink.noise(start: max(0, start - Int(0.004 * sampleRate)), ms: 18, t60: 0.012, lowPassHz: 900,
                               amp: velGain * pow(10, -50.0 / 20), fadeInMs: 3, pan: basePan, rng: &rng)
                }
            }
        }
        ModalKit.clampOutput(&left, &right)
        return StereoBuffer(left: left, right: right, sampleRate: sampleRate)
    }
}
