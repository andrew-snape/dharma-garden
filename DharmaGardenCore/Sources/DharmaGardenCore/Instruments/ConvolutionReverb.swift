import Accelerate
import Foundation

/// A room made of nothing but noise: a handful of early reflections, then a decorrelated stereo tail that
/// loses its high frequencies faster than its lows, as air and soft surfaces do. Convolving with it gives the
/// handpan space to bloom without any recorded impulse response to download.
public enum ConvolutionReverb {
    public static func impulseResponse(
        sampleRate: Double = ModalInstrument.defaultSampleRate,
        rt60: Double = 2.8,
        seed: UInt64 = 7
    ) -> (left: [Float], right: [Float]) {
        let length = Int(rt60 * 1.25 * sampleRate)
        var channels: [[Float]] = []
        for channel in 0..<2 {
            var rng = SplitMix(seed: seed &+ UInt64(channel) &* 7919)
            var ir = [Float](repeating: 0, count: length)
            var lp = 0.0
            let predelay = Int(0.008 * sampleRate)
            for n in predelay..<length {
                let t = Double(n - predelay) / sampleRate
                let decay = pow(10, -3 * t / rt60)
                // Cutoff slides from ~9 kHz down to ~1.2 kHz over the tail.
                let cutoff = 1200 + 7800 * exp(-t / 0.9)
                let alpha = 1 - exp(-2 * Double.pi * cutoff / sampleRate)
                lp += alpha * (rng.signed() - lp)
                let fadeIn = min(1, t / 0.012)
                ir[n] = Float(lp * decay * fadeIn)
            }
            // Early reflections, different for each ear.
            for _ in 0..<7 {
                let at = Int((0.010 + 0.030 * rng.unit()) * sampleRate)
                let gain = Float(0.25 + 0.35 * rng.unit()) * (rng.signed() > 0 ? 1 : -1)
                if at < length { ir[at] += gain * 0.5 }
            }
            channels.append(ir)
        }
        // Unit energy per channel so the wet level is predictable.
        for c in 0..<2 {
            var energy: Float = 0
            vDSP_svesq(channels[c], 1, &energy, vDSP_Length(channels[c].count))
            var scale = 1 / max(energy.squareRoot(), 1e-9)
            channels[c].withUnsafeMutableBufferPointer { p in
                vDSP_vsmul(p.baseAddress!, 1, &scale, p.baseAddress!, 1, vDSP_Length(p.count))
            }
        }
        return (channels[0], channels[1])
    }

    /// Full-length FFT convolution; the output is `x.count` long (the tail past the end is dropped).
    public static func convolve(_ x: [Float], with h: [Float]) -> [Float] {
        guard !x.isEmpty, !h.isEmpty else { return x }
        let needed = x.count + h.count - 1
        var log2n = 1
        while (1 << log2n) < needed { log2n += 1 }
        let n = 1 << log2n
        guard let setup = vDSP_create_fftsetup(vDSP_Length(log2n), FFTRadix(kFFTRadix2)) else { return x }
        defer { vDSP_destroy_fftsetup(setup) }

        func forward(_ signal: [Float]) -> ([Float], [Float]) {
            var padded = [Float](repeating: 0, count: n)
            padded.replaceSubrange(0..<signal.count, with: signal)
            var re = [Float](repeating: 0, count: n / 2)
            var im = [Float](repeating: 0, count: n / 2)
            re.withUnsafeMutableBufferPointer { rp in
                im.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    padded.withUnsafeBufferPointer { src in
                        src.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, vDSP_Length(log2n), FFTDirection(kFFTDirection_Forward))
                }
            }
            return (re, im)
        }

        var (xr, xi) = forward(x)
        let (hr, hi) = forward(h)
        // Packed format keeps DC in realp[0] and Nyquist in imagp[0]; both are purely real, multiply separately.
        let dc = xr[0] * hr[0], nyq = xi[0] * hi[0]
        xr.withUnsafeMutableBufferPointer { xrp in
            xi.withUnsafeMutableBufferPointer { xip in
                hr.withUnsafeBufferPointer { hrp in
                    hi.withUnsafeBufferPointer { hip in
                        var a = DSPSplitComplex(realp: xrp.baseAddress!, imagp: xip.baseAddress!)
                        var b = DSPSplitComplex(realp: UnsafeMutablePointer(mutating: hrp.baseAddress!),
                                                imagp: UnsafeMutablePointer(mutating: hip.baseAddress!))
                        vDSP_zvmul(&b, 1, &a, 1, &a, 1, vDSP_Length(n / 2), 1)
                        xrp[0] = dc
                        xip[0] = nyq
                        vDSP_fft_zrip(setup, &a, 1, vDSP_Length(log2n), FFTDirection(kFFTDirection_Inverse))
                    }
                }
            }
        }
        var out = [Float](repeating: 0, count: n)
        xr.withUnsafeMutableBufferPointer { rp in
            xi.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                out.withUnsafeMutableBufferPointer { dst in
                    dst.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                        vDSP_ztoc(&split, 1, $0, 2, vDSP_Length(n / 2))
                    }
                }
            }
        }
        // Forward transforms each carry a factor 2 and the inverse a factor n/... : 1/(4n) restores unit gain.
        var scale = 1 / Float(4 * n)
        out.withUnsafeMutableBufferPointer { p in
            vDSP_vsmul(p.baseAddress!, 1, &scale, p.baseAddress!, 1, vDSP_Length(p.count))
        }
        return Array(out[0..<x.count])
    }

    /// Mixes the room in, rolls off the top, and normalises so the peak sits at `peakDb` dBFS.
    public static func finish(
        _ dry: StereoBuffer,
        wet: Double = 0.3,
        lowPassHz: Double = 7000,
        peakDb: Double = -3,
        seed: UInt64 = 7
    ) -> StereoBuffer {
        let ir = impulseResponse(sampleRate: dry.sampleRate, seed: seed)
        let wl = convolve(dry.left, with: ir.left)
        let wr = convolve(dry.right, with: ir.right)
        let w = Float(wet), d = Float(1 - wet)
        var l = [Float](repeating: 0, count: dry.left.count)
        var r = l
        for i in 0..<l.count {
            l[i] = d * dry.left[i] + w * wl[i]
            r[i] = d * dry.right[i] + w * wr[i]
        }
        l = lowPass(l, hz: lowPassHz, sampleRate: dry.sampleRate)
        r = lowPass(r, hz: lowPassHz, sampleRate: dry.sampleRate)

        var peak: Float = 0
        for i in 0..<l.count { peak = max(peak, abs(l[i]), abs(r[i])) }
        let gain = peak > 0 ? Float(pow(10, peakDb / 20)) / peak : 1
        for i in 0..<l.count { l[i] *= gain; r[i] *= gain }
        return StereoBuffer(left: l, right: r, sampleRate: dry.sampleRate)
    }

    /// Gentle second-order low-pass (Butterworth-ish, Q 0.707).
    static func lowPass(_ x: [Float], hz: Double, sampleRate: Double) -> [Float] {
        let w0 = 2 * Double.pi * hz / sampleRate
        let alpha = sin(w0) / (2 * 0.707)
        let cw = cos(w0)
        let a0 = 1 + alpha
        let b0 = Float((1 - cw) / 2 / a0), b1 = Float((1 - cw) / a0), b2 = b0
        let a1 = Float(-2 * cw / a0), a2 = Float((1 - alpha) / a0)
        var out = [Float](repeating: 0, count: x.count)
        var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0
        for i in 0..<x.count {
            let y = b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x[i]; y2 = y1; y1 = y
            out[i] = y
        }
        return out
    }
}
