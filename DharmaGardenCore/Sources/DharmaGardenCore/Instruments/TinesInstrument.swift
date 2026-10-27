import Foundation

/// A modal-synthesis electric piano of the tine-and-tone-bar kind, in D dorian.
///
/// What makes the sound warm is how little there is: a near-sine fundamental (a tine and its bar, a hair apart,
/// so it swells and settles by itself), one very quiet bell partial near seven times the pitch that is gone in a
/// third of a second, and a gentle even-harmonic glow that comes from the pickup seeing the tine off-centre.
/// The glow is modelled as a soft, asymmetric saturation of the fundamental whose strength follows its own level,
/// so it blooms in the attack and clears as the note dies, as it does on the real thing. A soft hammer, a slow
/// decay, an optional very gentle stereo tremolo, and a one-pole roll-off near 3.8 kHz. Deterministic for a seed.
public enum TinesInstrument {
    /// D3 E3 F3 G3 A3 B3 C4 D4 E4 F4 G4 A4.
    public static let scale: [Int] = [50, 52, 53, 55, 57, 59, 60, 62, 64, 65, 67, 69]

    /// D3 is the anchor; the ring runs E3 to A4, and the silences are stretched because this is the sparsest
    /// of the instruments.
    public static let pieceScale = PieceScale(
        notes: scale, anchor: 0, ring: 1...11, home: 7, lowFifth: 4, high: 11, questions: [9, 6],
        registerOffset: 3, restScale: 1.2)

    static func fundamentalT60(midi: Int) -> Double { min(6.2, max(3.2, 6.2 - Double(midi - 50) * 0.13)) }

    /// Soft asymmetric saturation with unit small-signal gain. `bias` sets how lopsided it is; the lopsidedness is
    /// what turns a sine into a sine plus a second harmonic.
    static func saturate(_ u: Double, bias: Double = 0.5) -> Double {
        let slope = 1 - pow(tanh(bias), 2)
        return (tanh(u + bias) - tanh(bias)) / slope
    }

    /// - Parameters:
    ///   - tremolo: depth of the stereo tremolo, 0 (off) to 0.15. Left and right swing in opposite directions.
    ///   - tremoloRate: in hertz.
    public static func render(
        events: [HandpanEvent],
        duration: Double,
        seed: UInt64 = 1,
        sampleRate: Double = ModalInstrument.defaultSampleRate,
        tremolo: Double = 0.08,
        tremoloRate: Double = 4.0
    ) -> StereoBuffer {
        let total = max(0, Int(duration * sampleRate))
        var left = [Float](repeating: 0, count: total)
        var right = [Float](repeating: 0, count: total)

        left.withUnsafeMutableBufferPointer { lp in
            right.withUnsafeMutableBufferPointer { rp in
                guard total > 0 else { return }
                let sink = ModalKit.Sink(left: lp, right: rp, total: total, sampleRate: sampleRate)
                for (index, event) in events.enumerated() {
                    let start = Int((event.time * sampleRate).rounded())
                    guard start >= 0, start < total else { continue }
                    let v = min(1, max(0, event.velocity))
                    let f0 = ModalInstrument.frequency(midi: event.midi)
                    var nr = ModalKit.noteRng(seed: seed, midi: event.midi, salt: 0x5448)
                    let beat = 0.15 + 0.35 * nr.unit()
                    let bellRatio = 7.0 * (1 + 0.012 * nr.signed())
                    let pan = ModalKit.panFor(midi: event.midi, seed: seed, width: 0.25)
                    var rng = ModalKit.hitRng(seed: seed, index: index, salt: 0x5448)
                    let velGain = 0.3 * pow(v, 0.9)
                    let hitJitter = pow(10, rng.signed() * 0.6 / 20)
                    let soft = 1 - v
                    let t60 = fundamentalT60(midi: event.midi)

                    // A soft hammer: its width barely matters to the fundamental; the bell is set by table level.
                    let pulse = ModalKit.strikePulse(sigmaMs: 0.55, sampleRate: sampleRate, rng: &rng)

                    // The fundamental pair is rendered on its own so it can be saturated, then placed.
                    let length = min(total - start, Int(t60 * 1.3 * sampleRate))
                    guard length > 0 else { continue }
                    var scratch = [Float](repeating: 0, count: length)
                    scratch.withUnsafeMutableBufferPointer { s in
                        ModalKit.resonate(freq: f0 - beat / 2, amp: 0.58, t60: t60, excitation: pulse,
                                          floor: 0.3, sampleRate: sampleRate, length: length,
                                          left: s.baseAddress!, gl: 1, right: nil, gr: 0)
                        ModalKit.resonate(freq: f0 + beat / 2, amp: 0.42, t60: t60 * 0.92, excitation: pulse,
                                          floor: 0.3, sampleRate: sampleRate, length: length,
                                          left: s.baseAddress!, gl: 1, right: nil, gr: 0)
                    }
                    // Drive follows the strike; the signal's own level then decides how much glow there is.
                    let drive = 0.15 + 0.4 * v
                    var hp: Double = 0, prevIn: Double = 0
                    let gl = Float(cos((min(0.95, max(-0.95, pan)) + 1) * Double.pi / 4))
                    let gr = Float(sin((min(0.95, max(-0.95, pan)) + 1) * Double.pi / 4))
                    let level = velGain * hitJitter
                    for i in 0..<length {
                        let x = Double(scratch[i])
                        let y = saturate(x * drive) / drive
                        // Remove the DC that an asymmetric curve creates (one-pole high-pass, ~15 Hz).
                        hp = y - prevIn + 0.998 * hp
                        prevIn = y
                        let o = Float(hp * level)
                        lp[start + i] += o * gl
                        rp[start + i] += o * gr
                    }

                    // The bell: a very quiet inharmonic partial that is only there for the attack (<= -38 dB).
                    sink.mode(freq: f0 * bellRatio, amp: velGain * hitJitter * pow(10, (-40 - 8 * soft) / 20),
                              t60: 0.35, pan: pan, excitation: pulse, floor: 0.3, start: start)
                    // A soft hammer thud, low and rounded.
                    sink.noise(start: start, ms: 40, t60: 0.03, lowPassHz: 500, amp: velGain * pow(10, -30.0 / 20),
                               fadeInMs: 2.5, pan: pan * 0.5, rng: &rng)
                }
            }
        }

        // Stereo tremolo (opposite on the two sides, one continuous swing under the whole piece), then the
        // roll-off. The tremolo's average gain is 1, so it does not change the overall level.
        if tremolo > 0 {
            let depth = min(0.15, tremolo)
            for i in 0..<total {
                let s = Float(depth * sin(2 * Double.pi * tremoloRate * Double(i) / sampleRate))
                left[i] *= 1 + s
                right[i] *= 1 - s
            }
        }
        ModalKit.onePole(&left, hz: 3800, sampleRate: sampleRate)
        ModalKit.onePole(&right, hz: 3800, sampleRate: sampleRate)
        ModalKit.clampOutput(&left, &right)
        return StereoBuffer(left: left, right: right, sampleRate: sampleRate)
    }
}
