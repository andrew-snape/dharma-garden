import Foundation

/// The small set of building blocks the kalimba, felt piano, music box and tines share: ringing modes,
/// a soft strike pulse and a puff of filtered noise. The handpan keeps its own copy of the same idea in
/// `ModalInstrument` so that its sound can never change by accident.
enum ModalKit {
    /// A smooth, one-sided-click-free strike: a Gaussian pulse of unit area. A Gaussian has no spectral nulls,
    /// so it only ever rolls the top off (wider pulse, duller strike) and never carves a hole in the partials.
    /// A touch of low-passed noise rides on it so that two hits are never identical.
    static func strikePulse(sigmaMs: Double, jitter: Double = 0.2, sampleRate: Double,
                            rng: inout SplitMix) -> [Float] {
        let sigma = max(0.02, sigmaMs) * 0.001 * sampleRate
        let half = max(3, Int((5 * sigma).rounded(.up)))
        var out = [Double](repeating: 0, count: 2 * half + 1)
        var lp = 0.0
        var area = 0.0
        for i in 0..<out.count {
            let x = Double(i - half) / sigma
            lp += 0.3 * (rng.signed() - lp)
            out[i] = exp(-0.5 * x * x) * (1 + jitter * lp)
            area += out[i]
        }
        return out.map { Float($0 / area) }
    }

    /// Where the left and right outputs are, and how long they are.
    struct Sink {
        var left: UnsafeMutableBufferPointer<Float>
        var right: UnsafeMutableBufferPointer<Float>
        var total: Int
        var sampleRate: Double

        /// One decaying sinusoid, struck by `excitation`, placed at `pan` (-1...1).
        /// `floor` limits how much the designed level is protected from the strike's own spectrum:
        /// 1 means "let the strike roll the top off naturally", smaller values divide that roll-off back out
        /// (never by more than 1/floor), so a mode at a table level of -24 dB really is near -24 dB.
        func mode(freq: Double, amp: Double, t60: Double, pan: Double, excitation: [Float], floor: Double,
                  start: Int) {
            guard freq > 10, freq < sampleRate * 0.45, start >= 0, start < total, amp > 0 else { return }
            let length = min(total - start, Int(t60 * 1.3 * sampleRate))
            guard length > 0 else { return }
            let p = min(0.95, max(-0.95, pan))
            let gl = Float(cos((p + 1) * Double.pi / 4)), gr = Float(sin((p + 1) * Double.pi / 4))
            ModalKit.resonate(freq: freq, amp: amp, t60: t60, excitation: excitation, floor: floor,
                              sampleRate: sampleRate, length: length,
                              left: left.baseAddress! + start, gl: gl,
                              right: right.baseAddress! + start, gr: gr)
        }

        /// A mode as two resonators `beat` Hz apart, one leaning left and one right: the slow shimmer of two
        /// strings (or a tine and its bar) that are almost, but not quite, the same pitch.
        func pair(freq: Double, beat: Double, amp: Double, t60: Double, pan: Double, spread: Double,
                  excitation: [Float], floor: Double, start: Int) {
            mode(freq: freq - beat / 2, amp: amp * 0.58, t60: t60, pan: pan - spread, excitation: excitation,
                 floor: floor, start: start)
            mode(freq: freq + beat / 2, amp: amp * 0.42, t60: t60, pan: pan + spread, excitation: excitation,
                 floor: floor, start: start)
        }

        /// A short burst of low-passed noise with a soft raised-cosine start and an exponential decay: the
        /// felt thump of a hammer, the nail of a thumb, a key bottoming out. `amp` is the RMS level.
        func noise(start: Int, ms: Double, t60: Double, lowPassHz: Double, amp: Double, fadeInMs: Double,
                   pan: Double, rng: inout SplitMix) {
            let n = min(total - start, Int(ms * 0.001 * sampleRate))
            guard n > 8, start >= 0, amp > 0 else { return }
            let alpha = 1 - exp(-2 * Double.pi * lowPassHz / sampleRate)
            var x = [Double](repeating: 0, count: n)
            var a = 0.0, b = 0.0, sumSq = 0.0
            for i in 0..<n {
                a += alpha * (rng.signed() - a)
                b += alpha * (a - b)
                x[i] = b
                sumSq += b * b
            }
            let rms = max(1e-12, (sumSq / Double(n)).squareRoot())
            let fadeIn = max(2, Int(fadeInMs * 0.001 * sampleRate))
            let fadeOut = max(2, n / 6)
            let p = min(0.95, max(-0.95, pan))
            let gl = cos((p + 1) * Double.pi / 4), gr = sin((p + 1) * Double.pi / 4)
            for i in 0..<n {
                var env = pow(10.0, -3.0 * Double(i) / (t60 * sampleRate))
                if i < fadeIn { env *= 0.5 - 0.5 * cos(Double.pi * Double(i) / Double(fadeIn)) }
                if i >= n - fadeOut { env *= 0.5 + 0.5 * cos(Double.pi * Double(i - (n - fadeOut)) / Double(fadeOut)) }
                let v = x[i] / rms * amp * env
                left[start + i] += Float(v * gl)
                right[start + i] += Float(v * gr)
            }
        }
    }

    /// The two-pole resonator at the heart of every mode here. Writes into one or two channels.
    static func resonate(freq: Double, amp: Double, t60: Double, excitation: [Float], floor: Double,
                         sampleRate: Double, length: Int,
                         left: UnsafeMutablePointer<Float>, gl: Float,
                         right: UnsafeMutablePointer<Float>?, gr: Float) {
        let w = 2 * Double.pi * freq / sampleRate
        let r = pow(10.0, -3.0 / (t60 * sampleRate))
        let c1 = Float(2 * r * cos(w)), c2 = Float(-r * r)
        var re = 0.0, im = 0.0
        for (i, x) in excitation.enumerated() {
            re += Double(x) * cos(w * Double(i))
            im -= Double(x) * sin(w * Double(i))
        }
        let response = max(floor, (re * re + im * im).squareRoot())
        let drive = Float(amp * sin(w) / response)
        var y1: Float = 0, y2: Float = 0
        for n in 0..<length {
            let x: Float = n < excitation.count ? excitation[n] * drive : 0
            let y = c1 * y1 + c2 * y2 + x
            y2 = y1; y1 = y
            left[n] += y * gl
            if let right { right[n] += y * gr }
        }
    }

    /// One-pole low-pass over a whole channel, in place.
    static func onePole(_ x: inout [Float], hz: Double, sampleRate: Double) {
        let a = Float(1 - exp(-2 * Double.pi * hz / sampleRate))
        var y: Float = 0
        for i in 0..<x.count {
            y += a * (x[i] - y)
            x[i] = y
        }
    }

    static func panFor(midi: Int, seed: UInt64, width: Double) -> Double {
        width * sin(Double(midi) * 0.83 + Double(seed % 11))
    }

    /// Per-note fixed character, a function of the seed and the note only, like a physical instrument.
    static func noteRng(seed: UInt64, midi: Int, salt: UInt64) -> SplitMix {
        SplitMix(seed: seed &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(midi) &* 0x1000_0000_01B3 &+ salt)
    }

    /// Per-hit randomness, a function of the seed and the position of the event in the list.
    static func hitRng(seed: UInt64, index: Int, salt: UInt64) -> SplitMix {
        SplitMix(seed: seed ^ (UInt64(index + 1) &* 0xD1B5_4A32_D192_ED03) ^ salt)
    }

    static func clampOutput(_ l: inout [Float], _ r: inout [Float]) {
        for i in 0..<l.count {
            l[i] = min(1, max(-1, l[i]))
            r[i] = min(1, max(-1, r[i]))
        }
    }
}
