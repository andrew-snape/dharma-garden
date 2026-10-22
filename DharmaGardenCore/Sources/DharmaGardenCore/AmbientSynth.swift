import Foundation
import os

/// Pure Swift synthesis of the garden's ambience, made live like `GardenSynth` (no AVFoundation, no allocation
/// while rendering): soft filtered-noise rain, a few crickets chirping in bursts, and bird calls (short gliding
/// whistles at random times). The levels follow a target set from any thread, smoothed over a couple of seconds
/// so weather and the time of day change without a cut. Output is stereo interleaved, soft-clipped, never NaN.
public final class AmbientSynth: @unchecked Sendable {
    public let sampleRate: Double

    private struct Targets {
        var birds: Float = 0
        var crickets: Float = 0
        var rain: Float = 0
        /// Overall level, for the fade in and out and the player's volume.
        var master: Float = 0
    }
    private let targets = OSAllocatedUnfairLock(initialState: Targets())

    // Smoothed levels (audio thread only).
    private var birds: Float = 0, crickets: Float = 0, rain: Float = 0, master: Float = 0
    private var smoothing: Float
    private var masterSmoothing: Float

    private var rng: UInt64 = 0x9E37_79B9_7F4A_7C15
    private var tick = 0

    // Rain: two noise streams (left, right), each through two low-pass stages and a high-pass.
    private var rainLP1: (Float, Float) = (0, 0), rainLP2: (Float, Float) = (0, 0), rainHP: (Float, Float) = (0, 0)
    private let rainLowCoef: Float, rainHighCoef: Float

    private struct Cricket {
        var freq: Double
        var phase: Double = 0
        var cycle: Double       // position in the burst cycle, seconds
        var period: Double      // seconds between bursts
        var left: Float
        var right: Float
    }
    private var crickets3: [Cricket]

    private struct Bird {
        var active = false
        var notesLeft = 0
        var base = 3000.0
        var glide = 0.3
        var noteSamples = 0
        var gapSamples = 0
        var position = 0        // samples into the current note or gap
        var phase = 0.0
        var left: Float = 0.7
        var right: Float = 0.7
    }
    private var birdVoices = [Bird](repeating: Bird(), count: 4)
    private var nextChirpIn: Int

    private var outLP: (Float, Float) = (0, 0)
    private let outCoef: Float

    public init(sampleRate: Double, seed: UInt64 = 0xA11CE) {
        self.sampleRate = sampleRate
        smoothing = Float(1 - exp(-1 / (sampleRate * 2.5)))
        masterSmoothing = Float(1 - exp(-1 / (sampleRate * 1.5)))
        rainLowCoef = Float(1 - exp(-2 * .pi * 2200 / sampleRate))
        rainHighCoef = Float(1 - exp(-2 * .pi * 180 / sampleRate))
        outCoef = Float(1 - exp(-2 * .pi * 3200 / sampleRate))
        rng = rng ^ seed
        crickets3 = [
            Cricket(freq: 2700, cycle: 0.0, period: 1.37, left: 0.9, right: 0.4),
            Cricket(freq: 2950, cycle: 0.45, period: 1.61, left: 0.5, right: 0.8),
            Cricket(freq: 3200, cycle: 0.8, period: 1.23, left: 0.7, right: 0.7),
        ]
        nextChirpIn = Int(0.3 * sampleRate)
    }

    /// Sets what the sound should become. `level` is the overall volume (0 fades it out).
    public func setTarget(_ mix: AmbientMix, level: Double) {
        targets.withLock {
            $0.birds = Float(min(max(mix.birds, 0), 1))
            $0.crickets = Float(min(max(mix.crickets, 0), 1))
            $0.rain = Float(min(max(mix.rain, 0), 1))
            $0.master = Float(min(max(level, 0), 1))
        }
    }

    /// Jumps the levels straight to the target (for tests and the first start, so nothing fades in from before).
    public func settle() {
        let t = targets.withLock { $0 }
        birds = t.birds; crickets = t.crickets; rain = t.rain; master = t.master
    }

    // MARK: Random

    private func nextUnit() -> Double {
        rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
        return Double(rng >> 11) / Double(1 << 53)
    }

    private func nextNoise() -> Float { Float(nextUnit() * 2 - 1) }

    private func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * nextUnit() }

    // MARK: Rendering

    /// Fills `out` with `frames` stereo frames (left, right, left, right, ...).
    public func render(into out: UnsafeMutablePointer<Float>, frames: Int) {
        let t = targets.withLock { $0 }
        let step = 1 / sampleRate
        for i in 0..<frames {
            birds += (t.birds - birds) * smoothing
            crickets += (t.crickets - crickets) * smoothing
            rain += (t.rain - rain) * smoothing
            master += (t.master - master) * masterSmoothing
            var l: Float = 0, r: Float = 0

            if master > 0.0005 {
                if rain > 0.002 { addRain(&l, &r, level: rain) }
                if crickets > 0.002 { addCrickets(&l, &r, level: crickets, step: step) }
                addBirds(&l, &r, level: birds)
            }

            l *= master; r *= master
            outLP.0 += outCoef * (l - outLP.0)
            outLP.1 += outCoef * (r - outLP.1)
            out[2 * i] = Float(tanh(Double(outLP.0)))
            out[2 * i + 1] = Float(tanh(Double(outLP.1)))
            tick &+= 1
        }
    }

    private func addRain(_ l: inout Float, _ r: inout Float, level: Float) {
        let time = Double(tick) / sampleRate
        // Slow gusts: the shower swells and eases a little.
        let gust = Float(1 + 0.15 * sin(2 * .pi * 0.13 * time) + 0.1 * sin(2 * .pi * 0.31 * time + 1))
        func channel(_ noise: Float, _ lp1: inout Float, _ lp2: inout Float, _ hp: inout Float) -> Float {
            lp1 += rainLowCoef * (noise - lp1)
            lp2 += rainLowCoef * (lp1 - lp2)
            hp += rainHighCoef * (lp2 - hp)
            return lp2 - hp
        }
        let n1 = nextNoise(), n2 = nextNoise()
        l += channel(n1, &rainLP1.0, &rainLP2.0, &rainHP.0) * level * gust * 0.35
        r += channel(n2, &rainLP1.1, &rainLP2.1, &rainHP.1) * level * gust * 0.35
    }

    private func addCrickets(_ l: inout Float, _ r: inout Float, level: Float, step: Double) {
        let pulseRate = 25.0           // pulses per second inside a burst
        let burstLength = 0.12         // three pulses
        for k in crickets3.indices {
            var c = crickets3[k]
            c.cycle += step
            if c.cycle >= c.period { c.cycle -= c.period }
            if c.cycle < burstLength {
                let pulse = (c.cycle * pulseRate).truncatingRemainder(dividingBy: 1)
                let s = sin(.pi * pulse)
                let env = Float(s * s)
                c.phase += 2 * .pi * c.freq * step
                if c.phase > 2 * .pi { c.phase -= 2 * .pi }
                let tone = Float(sin(c.phase)) * env * level * 0.01
                l += tone * c.left
                r += tone * c.right
            }
            crickets3[k] = c
        }
    }

    private func addBirds(_ l: inout Float, _ r: inout Float, level: Float) {
        nextChirpIn -= 1
        if nextChirpIn <= 0 {
            // Busier when the birds are louder: about one call every 4 to 25 seconds, so they stay in the distance.
            nextChirpIn = Int(range(4, 9) / Double(max(0.35, level)) * sampleRate)
            if level > 0.02, let free = birdVoices.firstIndex(where: { !$0.active }) { startBird(free) }
        }
        for k in birdVoices.indices where birdVoices[k].active {
            var b = birdVoices[k]
            if b.position < b.noteSamples {
                let p = Double(b.position) / Double(b.noteSamples)
                let vibrato = 1 + 0.01 * sin(2 * .pi * 28 * Double(b.position) / sampleRate)
                let freq = b.base * (1 + b.glide * (p - 0.5)) * vibrato
                b.phase += 2 * .pi * freq / sampleRate
                if b.phase > 2 * .pi { b.phase -= 2 * .pi }
                let env = pow(sin(.pi * p), 1.5)
                let tone = Float(sin(b.phase) * env) * 0.012
                l += tone * b.left
                r += tone * b.right
            }
            b.position += 1
            if b.position >= b.noteSamples + b.gapSamples {
                b.position = 0
                b.notesLeft -= 1
                if b.notesLeft <= 0 {
                    b.active = false
                } else {
                    nextNote(&b)
                }
            }
            birdVoices[k] = b
        }
    }

    private func startBird(_ index: Int) {
        var b = Bird()
        b.active = true
        b.notesLeft = Int(range(2, 4))
        b.base = range(1700, 2600)
        let pan = Float(nextUnit())
        b.left = 0.4 + 0.5 * (1 - pan)
        b.right = 0.4 + 0.5 * pan
        nextNote(&b)
        birdVoices[index] = b
    }

    /// Picks the next note of a call: near the call's pitch, gliding up or down, short, then a short gap.
    private func nextNote(_ b: inout Bird) {
        b.glide = (nextUnit() < 0.5 ? -1 : 1) * range(0.08, 0.25)
        b.base *= 1 + (nextUnit() - 0.5) * 0.2
        b.base = min(max(b.base, 1500), 2800)
        b.noteSamples = Int(range(0.08, 0.16) * sampleRate)
        b.gapSamples = Int(range(0.03, 0.08) * sampleRate)
    }
}
