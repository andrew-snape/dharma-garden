import Foundation

/// One strike of the handpan: when, which note (MIDI number) and how hard (0...1).
public struct HandpanEvent: Sendable, Equatable {
    public var time: Double
    public var midi: Int
    public var velocity: Double

    public init(time: Double, midi: Int, velocity: Double) {
        self.time = time
        self.midi = midi
        self.velocity = velocity
    }
}

/// Plain stereo audio, kept free of AVFoundation so it can be tested and reused live.
public struct StereoBuffer: Sendable {
    public var left: [Float]
    public var right: [Float]
    public var sampleRate: Double

    public init(left: [Float], right: [Float], sampleRate: Double) {
        self.left = left
        self.right = right
        self.sampleRate = sampleRate
    }
}

/// A modal-synthesis handpan in D Kurd.
///
/// A real handpan note is a few ringing partials, not a waveform: the fundamental, an octave and a compound
/// fifth are tuned on purpose, and a handful of weak untuned shell modes die away in a fraction of a second.
/// We model each partial as a pair of slightly detuned two-pole resonators (the beating between them is the
/// slow shimmer you hear on a real instrument) and strike them with a few milliseconds of soft burst, so there
/// is no click and no harsh edge. Everything is deterministic for a seed.
public enum ModalInstrument {
    public static let defaultSampleRate = 48_000.0

    /// D3 A3 Bb3 C4 D4 E4 F4 G4 A4 as MIDI numbers, ding first.
    public static let scale: [Int] = [50, 57, 58, 60, 62, 64, 65, 67, 69]

    public static func frequency(midi: Int) -> Double {
        440.0 * pow(2.0, Double(midi - 69) / 12.0)
    }

    // MARK: Mode table

    struct Mode {
        var ratio: Double
        var db: Double
        var t60: Double
        /// How many dB quieter this mode gets on a gentle strike (brightness rises with velocity).
        var softPenalty: Double
        var tuned: Bool
    }

    /// The modes of one note. Lower notes ring longer, as on a real handpan.
    static func modes(midi: Int, rng: inout SplitMix) -> [Mode] {
        let t = max(5.0, 8.0 - Double(midi - 50) * 0.13)
        var shell1 = 1.41 * (1 + rng.signed() * 0.015)
        var shell2 = 2.63 * (1 + rng.signed() * 0.015)
        var shell3 = 4.17 * (1 + rng.signed() * 0.015)
        var shell4 = 5.4 * (1 + rng.signed() * 0.015)
        shell1 = max(shell1, 1.3); shell2 = max(shell2, 2.5); shell3 = max(shell3, 4.0); shell4 = max(shell4, 5.2)
        return [
            Mode(ratio: 1, db: 0, t60: t, softPenalty: 0, tuned: true),
            Mode(ratio: 2, db: -8, t60: t * 0.55, softPenalty: 4, tuned: true),
            Mode(ratio: 3, db: -15, t60: t * 0.32, softPenalty: 8, tuned: true),
            Mode(ratio: shell1, db: -30, t60: 1.1, softPenalty: 14, tuned: false),
            Mode(ratio: shell2, db: -33, t60: 0.7, softPenalty: 14, tuned: false),
            Mode(ratio: shell3, db: -37, t60: 0.4, softPenalty: 14, tuned: false),
            Mode(ratio: shell4, db: -40, t60: 0.25, softPenalty: 14, tuned: false),
        ]
    }

    /// The instrument is physically fixed, so each note's detune is a function of the seed and the note only.
    /// Hits then shimmer the same way every time, as a real handpan does.
    static func noteRng(seed: UInt64, midi: Int) -> SplitMix {
        SplitMix(seed: seed &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(midi) &* 0x1000_0000_01B3)
    }

    // MARK: Rendering

    /// Renders events to stereo, dry. `duration` is in seconds; notes that ring past it are cut off.
    public static func render(
        events: [HandpanEvent],
        duration: Double,
        seed: UInt64 = 1,
        sampleRate: Double = defaultSampleRate
    ) -> StereoBuffer {
        let total = max(0, Int(duration * sampleRate))
        var left = [Float](repeating: 0, count: total)
        var right = [Float](repeating: 0, count: total)

        // Per-note fixed character (detune, shell ratios, pan).
        var perNote: [Int: NoteVoice] = [:]
        for (index, midi) in scale.enumerated() {
            var rng = noteRng(seed: seed, midi: midi)
            let modes = modes(midi: midi, rng: &rng)
            var beats: [Double] = []
            for mode in modes {
                let base = 0.3 + 1.2 * rng.unit()
                beats.append(min(1.5, base * (mode.tuned ? 1 : 0.8) * (mode.ratio > 2.5 ? 0.9 : 1)))
            }
            let pan = 0.3 * sin(2 * Double.pi * Double(index) / Double(scale.count) + 0.5)
            perNote[midi] = NoteVoice(modes: modes, beats: beats, pan: pan)
        }

        left.withUnsafeMutableBufferPointer { lp in
            right.withUnsafeMutableBufferPointer { rp in
                for (eventIndex, event) in events.enumerated() {
                    guard let voice = perNote[event.midi] else { continue }
                    let start = Int((event.time * sampleRate).rounded())
                    guard start >= 0, start < total else { continue }
                    let v = min(1, max(0, event.velocity))
                    var rng = SplitMix(seed: seed ^ (UInt64(eventIndex + 1) &* 0xD1B5_4A32_D192_ED03))
                    let burst = makeBurst(velocity: v, sampleRate: sampleRate, rng: &rng)
                    let velGain = 0.3 * pow(v, 1.2)
                    let f0 = frequency(midi: event.midi)
                    let hitJitter = pow(10, rng.signed() * 0.8 / 20)

                    let target = Target(left: lp, right: rp, total: total, sampleRate: sampleRate)

                    for (i, mode) in voice.modes.enumerated() {
                        let db = mode.db - (1 - v) * mode.softPenalty
                        let amp = velGain * hitJitter * pow(10, db / 20)
                        target.addPair(
                            freq: f0 * mode.ratio, beat: voice.beats[i], amp: amp, t60: mode.t60,
                            pan: voice.pan, spread: 0.12, burst: burst, start: start)
                    }

                    // Faint cavity hum: strong on the ding, barely there on the rest.
                    let humDb = event.midi == scale[0] ? -22.0 : -36.0
                    target.addPair(
                        freq: 95, beat: 0.4, amp: velGain * pow(10, humDb / 20), t60: 0.6,
                        pan: 0, spread: 0.05, burst: burst, start: start)

                    // Sympathetic ring: other notes whose tuned partials coincide with this one's.
                    // Fixed order, so float sums (and therefore renders) are identical run to run.
                    for otherMidi in scale where otherMidi != event.midi {
                        guard let other = perNote[otherMidi] else { continue }
                        let fo = frequency(midi: otherMidi)
                        for k in 1...3 {
                            for j in 1...3 {
                                let fa = f0 * Double(k), fb = fo * Double(j)
                                guard abs(fa - fb) / fb < 0.01 else { continue }
                                let sourceDb = voice.modes[k - 1].db - (1 - v) * voice.modes[k - 1].softPenalty
                                let amp = velGain * pow(10, (sourceDb - 36) / 20)
                                target.addPair(
                                    freq: fb, beat: 0.5, amp: amp, t60: other.modes[j - 1].t60,
                                    pan: other.pan, spread: 0.1, burst: burst,
                                    start: start + Int(0.008 * sampleRate))
                            }
                        }
                    }
                }
            }
        }

        // Safety only: the level design keeps ordinary playing well below this.
        for i in 0..<total {
            left[i] = min(1, max(-1, left[i]))
            right[i] = min(1, max(-1, right[i]))
        }
        return StereoBuffer(left: left, right: right, sampleRate: sampleRate)
    }

    struct NoteVoice {
        var modes: [Mode]
        var beats: [Double]
        var pan: Double
    }

    /// A soft finger or mallet contact: a raised-cosine pulse (harder strikes are shorter) with a little
    /// low-passed noise riding on it so repeated hits are not identical. Normalised to unit area.
    static func makeBurst(velocity v: Double, sampleRate: Double, rng: inout SplitMix) -> [Float] {
        let ms = 6.0 - 3.5 * v
        let n = max(8, Int(ms * 0.001 * sampleRate))
        var out = [Double](repeating: 0, count: n)
        var lp = 0.0
        let alpha = 0.15 + 0.5 * v
        var areaHann = 0.0
        for i in 0..<n {
            let hann = 0.5 - 0.5 * cos(2 * Double.pi * (Double(i) + 0.5) / Double(n))
            lp += alpha * (rng.signed() - lp)
            out[i] = hann * (1 + 0.5 * lp)
            areaHann += hann
        }
        return out.map { Float($0 / areaHann) }
    }

    /// Writes resonators straight into the shared output buffers.
    struct Target {
        var left: UnsafeMutableBufferPointer<Float>
        var right: UnsafeMutableBufferPointer<Float>
        var total: Int
        var sampleRate: Double

        /// A mode as two resonators detuned by `beat` Hz, one leaning left and one right of `pan`.
        func addPair(freq: Double, beat: Double, amp: Double, t60: Double, pan: Double, spread: Double,
                     burst: [Float], start: Int) {
            guard freq < sampleRate * 0.45, start < total else { return }
            let length = min(total - start, Int(t60 * 1.3 * sampleRate))
            let a = 0.6, b = 0.4
            run(freq: freq - beat / 2, amp: amp * a, t60: t60, pan: pan - spread, burst: burst, start: start, length: length)
            run(freq: freq + beat / 2, amp: amp * b, t60: t60, pan: pan + spread, burst: burst, start: start, length: length)
        }

        private func run(freq: Double, amp: Double, t60: Double, pan: Double, burst: [Float],
                         start: Int, length: Int) {
            let w = 2 * Double.pi * freq / sampleRate
            let r = pow(10.0, -3.0 / (t60 * sampleRate))
            let c1 = Float(2 * r * cos(w)), c2 = Float(-r * r)

            // Divide out the burst's own response at this frequency so the designed mode levels hold
            // whatever the burst length is; the burst then only shapes the attack, not the balance.
            var re = 0.0, im = 0.0
            for (i, x) in burst.enumerated() {
                re += Double(x) * cos(w * Double(i))
                im -= Double(x) * sin(w * Double(i))
            }
            let response = max(0.08, (re * re + im * im).squareRoot())
            let drive = Float(amp * sin(w) / response)

            let p = min(0.95, max(-0.95, pan))
            let gl = Float(cos((p + 1) * Double.pi / 4)), gr = Float(sin((p + 1) * Double.pi / 4))
            var y1: Float = 0, y2: Float = 0
            for n in 0..<length {
                let x: Float = n < burst.count ? burst[n] * drive : 0
                let y = c1 * y1 + c2 * y2 + x
                y2 = y1; y1 = y
                left[start + n] += y * gl
                right[start + n] += y * gr
            }
        }
    }
}

/// Small deterministic generator, so renders are repeatable for a seed.
public struct SplitMix: Sendable {
    var state: UInt64
    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0..<1
    public mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    /// -1..<1
    public mutating func signed() -> Double { unit() * 2 - 1 }
}
