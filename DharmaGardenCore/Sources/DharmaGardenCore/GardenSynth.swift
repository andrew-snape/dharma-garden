import Foundation
import os

/// Pure Swift synthesis of the garden's music, mixed through a gentle limiter. No AVFoundation, so it is testable
/// and can run inside a render callback. Voices:
/// - koto, pluck (guitar) and bass: Karplus-Strong strings with a soft body resonance, differing in brightness,
///   decay and body mix;
/// - flute: sine with vibrato and filtered breath noise; drone: sines with a slow swell;
/// - piano: a few slightly inharmonic partials with their own decays and a soft hammer attack;
/// - epiano: FM tine (decaying modulation index) with a short bell partial and a gentle tremolo;
/// - pad: slowly swelling detuned sines.
///
/// Events are scheduled from any thread. `renderInterleaved` runs on the audio thread, takes a lock once per call,
/// and uses pre-allocated voices, so it does not allocate while rendering. Output never exceeds +/-1 and is never NaN.
public final class GardenSynth: @unchecked Sendable {
    public let sampleRate: Double
    /// 1 (mono) or 2 (stereo, interleaved).
    public let channels: Int

    private struct Scheduled {
        let sample: Int
        let event: NoteEvent
    }

    private struct Koto {
        var ring: [Float]
        var length = 2
        var index = 0
        var loopGain: Float = 0
        var age = 0
        var stopAt = 0
        var amplitude: Float = 0
        var left: Float = 0.7
        var right: Float = 0.7
        var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0
        /// How much of the string and of the body resonance reach the output.
        var stringMix: Float = 0.75
        var bodyMix: Float = 0.5
        var active = false
    }

    private struct Flute {
        var phase = 0.0
        var step = 0.0
        var vibrato = 0.0
        var breath: Float = 0
        var age = 0
        var length = 1
        var amplitude: Float = 0
        var left: Float = 0.7
        var right: Float = 0.7
        var active = false
    }

    private struct Drone {
        var phase = 0.0
        var step = 0.0
        var age = 0
        var length = 1
        var amplitude: Float = 0
        var left: Float = 0.7
        var right: Float = 0.7
        var active = false
    }

    /// Up to eight modal partials as vector lanes, each a rotating phasor (no `sin` per sample).
    private struct Piano {
        var cosine = SIMD8<Float>(repeating: 1)
        var sine = SIMD8<Float>(repeating: 0)
        var stepCosine = SIMD8<Float>(repeating: 1)
        var stepSine = SIMD8<Float>(repeating: 0)
        var amplitudes = SIMD8<Float>(repeating: 0)
        var decays = SIMD8<Float>(repeating: 1)
        var age = 0
        var stopAt = 0
        var amplitude: Float = 0
        var left: Float = 0.7
        var right: Float = 0.7
        var active = false
    }

    private struct EPiano {
        var carrier = 0.0
        var modulator = 0.0
        var step = 0.0
        var tremolo = 0.0
        /// Level of the short bell partial, lower for high notes.
        var bellLevel = 0.0
        var age = 0
        var stopAt = 0
        var amplitude: Float = 0
        var left: Float = 0.7
        var right: Float = 0.7
        var active = false
    }

    private struct Pad {
        var phase = 0.0
        var step = 0.0
        var swell = 0.0
        var age = 0
        var length = 1
        var amplitude: Float = 0
        var left: Float = 0.7
        var right: Float = 0.7
        var active = false
    }

    private static let kotoVoices = 16
    private static let pianoVoices = 10
    private static let epianoVoices = 8
    private static let padVoices = 12
    private static let fluteVoices = 3
    private static let droneVoices = 6

    // An unfair lock donates priority to the thread holding it, so the audio thread is not left waiting behind a
    // low-priority holder. Work done while holding it is kept short (see `schedule`).
    private let lock = OSAllocatedUnfairLock()
    private var queue: [Scheduled] = []
    private var head = 0
    private var clock = 0
    private var level: Float
    private var levelTarget: Float
    private var levelStep: Float = 0
    private var kotos: [Koto]
    private var flutes: [Flute]
    private var drones: [Drone]
    private var pianos: [Piano]
    private var epianos: [EPiano]
    private var pads: [Pad]
    private var noiseState: UInt32 = 0x2545_F491
    /// Gentle one-pole low-pass on the mix (about 5 kHz), so no voice sounds brittle or hissy.
    private let toneCoefficient: Float
    private var toneLeft: Float = 0
    private var toneRight: Float = 0

    // Body resonance: RBJ band-pass at 300 Hz, Q 2.5, shared by every koto voice.
    private let bodyB0: Float
    private let bodyA1: Float
    private let bodyA2: Float
    private let attackSamples: Int
    private let releaseSamples: Int

    /// `level` is the starting output gain (1 for offline rendering; the app starts at 0 and fades in).
    public init(sampleRate: Double, channels: Int = 2, level: Float = 0) {
        self.sampleRate = sampleRate
        self.channels = channels == 1 ? 1 : 2
        self.level = level
        self.levelTarget = level
        let ringSize = Int(sampleRate / 30) + 8
        kotos = (0..<Self.kotoVoices).map { _ in Koto(ring: [Float](repeating: 0, count: ringSize)) }
        flutes = Array(repeating: Flute(), count: Self.fluteVoices)
        drones = Array(repeating: Drone(), count: Self.droneVoices)
        pianos = Array(repeating: Piano(), count: Self.pianoVoices)
        epianos = Array(repeating: EPiano(), count: Self.epianoVoices)
        pads = Array(repeating: Pad(), count: Self.padVoices)

        let w0 = 2 * Double.pi * 300 / sampleRate
        let alpha = sin(w0) / (2 * 2.5)
        let a0 = 1 + alpha
        bodyB0 = Float(alpha / a0)
        bodyA1 = Float(-2 * cos(w0) / a0)
        bodyA2 = Float((1 - alpha) / a0)
        attackSamples = max(1, Int(0.012 * sampleRate))
        toneCoefficient = Float(1 - exp(-2 * Double.pi * 5000 / sampleRate))
        releaseSamples = max(1, Int(0.25 * sampleRate))
    }

    /// Seconds of audio rendered since the last `reset`. Event times are measured on this clock.
    public var renderedSeconds: Double {
        lock.lock()
        defer { lock.unlock() }
        return Double(clock) / sampleRate
    }

    /// Adds notes to the queue. Times are seconds on the synth clock; past times play at once.
    public func schedule(_ events: [NoteEvent]) {
        // Converted and sorted before taking the lock, which the audio thread also needs.
        let incoming = events.map { Scheduled(sample: Int(($0.time * sampleRate).rounded()), event: $0) }
            .sorted { $0.sample < $1.sample }
        guard !incoming.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        if head > 0 {
            queue.removeFirst(head)
            head = 0
        }
        let needsSort = (queue.last?.sample ?? .min) > incoming[0].sample
        queue.append(contentsOf: incoming)
        if needsSort { queue.sort { $0.sample < $1.sample } }
    }

    /// Stops every voice, clears the queue, returns the clock to zero and the gain to silence.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        queue.removeAll()
        head = 0
        clock = 0
        level = 0
        levelTarget = 0
        levelStep = 0
        toneLeft = 0
        toneRight = 0
        for i in kotos.indices { kotos[i].active = false; kotos[i].x1 = 0; kotos[i].x2 = 0; kotos[i].y1 = 0; kotos[i].y2 = 0 }
        for i in flutes.indices { flutes[i].active = false }
        for i in drones.indices { drones[i].active = false }
        for i in pianos.indices { pianos[i].active = false }
        for i in epianos.indices { epianos[i].active = false }
        for i in pads.indices { pads[i].active = false }
    }

    /// Ramps the output gain (0...1 times the music's own level) to `target` over `seconds`.
    public func setLevel(_ target: Float, over seconds: Double) {
        lock.lock()
        defer { lock.unlock() }
        let t = min(1, max(0, target))
        levelTarget = t
        let frames = max(1, seconds * sampleRate)
        levelStep = (t - level) / Float(frames)
    }

    /// Renders `frames` frames into `out` (interleaved if stereo; `frames * channels` floats).
    public func renderInterleaved(into out: UnsafeMutablePointer<Float>, frames: Int) {
        lock.lock()
        defer { lock.unlock() }
        for f in 0..<frames {
            while head < queue.count, queue[head].sample <= clock {
                trigger(queue[head].event)
                head += 1
            }
            var l: Float = 0
            var r: Float = 0
            for i in kotos.indices where kotos[i].active {
                let (a, b) = tickKoto(i)
                l += a
                r += b
            }
            for i in flutes.indices where flutes[i].active {
                let (a, b) = tickFlute(i)
                l += a
                r += b
            }
            for i in drones.indices where drones[i].active {
                let (a, b) = tickDrone(i)
                l += a
                r += b
            }
            for i in pianos.indices where pianos[i].active {
                let (a, b) = tickPiano(i)
                l += a
                r += b
            }
            for i in epianos.indices where epianos[i].active {
                let (a, b) = tickEPiano(i)
                l += a
                r += b
            }
            for i in pads.indices where pads[i].active {
                let (a, b) = tickPad(i)
                l += a
                r += b
            }
            if levelStep != 0 {
                level += levelStep
                if (levelStep > 0 && level >= levelTarget) || (levelStep < 0 && level <= levelTarget) {
                    level = levelTarget
                    levelStep = 0
                }
            }
            toneLeft += toneCoefficient * (l - toneLeft)
            toneRight += toneCoefficient * (r - toneRight)
            let left = Self.limit(toneLeft * level)
            let right = Self.limit(toneRight * level)
            if channels == 2 {
                out[2 * f] = left
                out[2 * f + 1] = right
            } else {
                out[f] = 0.5 * (left + right)
            }
            clock += 1
        }
    }

    /// Offline rendering: `frames` frames of `events` at full level, interleaved.
    public static func render(events: [NoteEvent], frames: Int, sampleRate: Double, channels: Int = 2) -> [Float] {
        let synth = GardenSynth(sampleRate: sampleRate, channels: channels, level: 1)
        synth.schedule(events)
        var out = [Float](repeating: 0, count: frames * synth.channels)
        if frames > 0 {
            out.withUnsafeMutableBufferPointer { buffer in
                synth.renderInterleaved(into: buffer.baseAddress!, frames: frames)
            }
        }
        return out
    }

    // MARK: Voices

    private func trigger(_ e: NoteEvent) {
        let amplitude = Float(min(max(e.velocity, 0), 1))
        let stopAt = max(1, Int(e.duration * sampleRate))
        let frequency = Self.frequency(e.midiNote)
        let pan = sin(Double(e.midiNote) * 1.7) * 0.5

        switch e.voice {
        case .koto:
            // Excitation low-passed by six averaging passes, so the pluck is soft rather than hissy.
            startString(frequency: frequency, pan: pan, stopAt: stopAt, amplitude: 1.1 * amplitude,
                        passes: 6, decaySeconds: 2.4, stringMix: 0.75, bodyMix: 0.5)
        case .pluck:
            // Guitar: brighter excitation, longer ring, a lighter body.
            startString(frequency: frequency, pan: pan, stopAt: stopAt, amplitude: 2.1 * amplitude,
                        passes: 24, decaySeconds: 3.2, stringMix: 0.8, bodyMix: 0.4, circular: true)
        case .bass:
            // Soft thumb: dark excitation, a rounded low note.
            startString(frequency: frequency, pan: 0, stopAt: stopAt, amplitude: 1.6 * amplitude,
                        passes: 30, decaySeconds: 2.0, stringMix: 0.95, bodyMix: 0.2, circular: true)

        case .flute:
            let slot = flutes.firstIndex { !$0.active } ?? (flutes.indices.max { flutes[$0].age < flutes[$1].age } ?? 0)
            flutes[slot].phase = 0
            flutes[slot].vibrato = 0
            flutes[slot].breath = 0
            flutes[slot].step = 2 * Double.pi * frequency / sampleRate
            flutes[slot].age = 0
            flutes[slot].length = stopAt
            flutes[slot].amplitude = 0.3 * amplitude
            flutes[slot].left = Float(cos((pan * 0.2 + 0.5) * Double.pi / 2))
            flutes[slot].right = Float(sin((pan * 0.2 + 0.5) * Double.pi / 2))
            flutes[slot].active = true

        case .drone:
            let slot = drones.firstIndex { !$0.active } ?? (drones.indices.max { drones[$0].age < drones[$1].age } ?? 0)
            drones[slot].phase = 0
            drones[slot].step = 2 * Double.pi * frequency / sampleRate
            drones[slot].age = 0
            drones[slot].length = stopAt
            drones[slot].amplitude = 0.06 * amplitude
            drones[slot].left = 0.7
            drones[slot].right = 0.7
            drones[slot].active = true

        case .piano:
            startPiano(frequency: frequency, pan: pan, stopAt: stopAt, velocity: amplitude)

        case .epiano:
            let slot = epianos.firstIndex { !$0.active } ?? (epianos.indices.max { epianos[$0].age < epianos[$1].age } ?? 0)
            epianos[slot].carrier = 0
            epianos[slot].modulator = 0
            epianos[slot].step = 2 * Double.pi * frequency / sampleRate
            epianos[slot].tremolo = Double(slot) * 1.3
            epianos[slot].bellLevel = 0.05 * min(1, 2500 / (7 * frequency))
            epianos[slot].age = 0
            epianos[slot].stopAt = stopAt
            epianos[slot].amplitude = 0.23 * amplitude
            epianos[slot].left = Float(cos((pan * 0.6 + 0.5) * Double.pi / 2))
            epianos[slot].right = Float(sin((pan * 0.6 + 0.5) * Double.pi / 2))
            epianos[slot].active = true

        case .pad:
            let slot = pads.firstIndex { !$0.active } ?? (pads.indices.max { pads[$0].age < pads[$1].age } ?? 0)
            pads[slot].phase = 0
            pads[slot].step = 2 * Double.pi * frequency / sampleRate
            pads[slot].swell = Double(e.midiNote % 7)
            pads[slot].age = 0
            pads[slot].length = stopAt
            pads[slot].amplitude = 0.05 * amplitude
            pads[slot].left = Float(cos((pan * 0.5 + 0.5) * Double.pi / 2))
            pads[slot].right = Float(sin((pan * 0.5 + 0.5) * Double.pi / 2))
            pads[slot].active = true
        }
    }

    /// Starts a Karplus-Strong string in the shared string pool. `decaySeconds` sets the loop gain, `passes` how
    /// smooth (dark) the noise excitation is.
    private func startString(frequency: Double, pan: Double, stopAt: Int, amplitude: Float, passes: Int,
                             decaySeconds: Double, stringMix: Float, bodyMix: Float, circular: Bool = false) {
        let slot = kotos.firstIndex { !$0.active } ?? (kotos.indices.max { kotos[$0].age < kotos[$1].age } ?? 0)
        let length = max(2, Int((sampleRate / frequency - 0.5).rounded()))
        for j in 0..<length { kotos[slot].ring[j] = nextNoise() }
        for _ in 0..<passes {
            // The koto smooths from silence (as it always has); the other strings smooth around the loop, so the
            // excitation has no jump where it wraps (a click on every period).
            var previous: Float = circular ? kotos[slot].ring[length - 1] : 0
            for j in 0..<length {
                let current = kotos[slot].ring[j]
                kotos[slot].ring[j] = 0.5 * (current + previous)
                previous = current
            }
        }
        if circular {
            var mean: Float = 0
            for j in 0..<length { mean += kotos[slot].ring[j] }
            mean /= Float(length)
            for j in 0..<length { kotos[slot].ring[j] -= mean }
        }
        kotos[slot].length = length
        kotos[slot].index = 0
        kotos[slot].loopGain = Float(pow(10, -3 / (decaySeconds * frequency)))
        kotos[slot].age = 0
        kotos[slot].stopAt = stopAt
        kotos[slot].amplitude = amplitude
        kotos[slot].left = Float(cos((pan + 0.5) * Double.pi / 2))
        kotos[slot].right = Float(sin((pan + 0.5) * Double.pi / 2))
        kotos[slot].stringMix = stringMix
        kotos[slot].bodyMix = bodyMix
        kotos[slot].x1 = 0; kotos[slot].x2 = 0; kotos[slot].y1 = 0; kotos[slot].y2 = 0
        kotos[slot].active = true
    }

    /// Piano partials: slightly stretched harmonics, higher ones quieter and shorter-lived; harder notes are brighter.
    private func startPiano(frequency: Double, pan: Double, stopAt: Int, velocity: Float) {
        let slot = pianos.firstIndex { !$0.active } ?? (pianos.indices.max { pianos[$0].age < pianos[$1].age } ?? 0)
        let weights: [Double] = [1.0, 0.5, 0.3, 0.16, 0.1, 0.05, 0.03, 0.015]
        // Fundamental decay time (60 dB): longer for low notes.
        let decay1 = min(9.0, max(2.5, 5.0 * pow(220 / frequency, 0.4)))
        var cosine = SIMD8<Float>(repeating: 1)
        var sine = SIMD8<Float>(repeating: 0)
        var amplitudes = SIMD8<Float>(repeating: 0)
        var decays = SIMD8<Float>(repeating: 1)
        for k in 0..<8 {
            let n = Double(k + 1)
            let f = frequency * n * (1 + 0.0004 * n * n).squareRoot()
            guard f < sampleRate * 0.45 else { continue }
            let w = 2 * Double.pi * f / sampleRate
            cosine[k] = Float(cos(w))
            sine[k] = Float(sin(w))
            amplitudes[k] = Float(weights[k] * pow(Double(velocity), 0.35 * Double(k)))
            decays[k] = Float(pow(10, -3 / (decay1 / (1 + 0.9 * Double(k)) * sampleRate)))
        }
        pianos[slot].stepCosine = cosine
        pianos[slot].stepSine = sine
        pianos[slot].cosine = SIMD8<Float>(repeating: 1)
        pianos[slot].sine = SIMD8<Float>(repeating: 0)
        pianos[slot].amplitudes = amplitudes
        pianos[slot].decays = decays
        pianos[slot].age = 0
        pianos[slot].stopAt = stopAt
        pianos[slot].amplitude = 0.28 * velocity
        pianos[slot].left = Float(cos((pan * 0.7 + 0.5) * Double.pi / 2))
        pianos[slot].right = Float(sin((pan * 0.7 + 0.5) * Double.pi / 2))
        pianos[slot].active = true
    }

    private func tickKoto(_ i: Int) -> (Float, Float) {
        let n = kotos[i].length
        let y = kotos[i].ring[kotos[i].index]
        var next = kotos[i].index + 1
        if next == n { next = 0 }
        // Karplus-Strong: average with the next sample, scaled by the loop gain (sets the decay).
        kotos[i].ring[kotos[i].index] = kotos[i].loopGain * 0.5 * (y + kotos[i].ring[next])
        kotos[i].index = next

        let body = bodyB0 * (y - kotos[i].x2) - bodyA1 * kotos[i].y1 - bodyA2 * kotos[i].y2
        kotos[i].x2 = kotos[i].x1
        kotos[i].x1 = y
        kotos[i].y2 = kotos[i].y1
        kotos[i].y1 = body

        let age = kotos[i].age
        var env: Float = 1
        if age < attackSamples { env = Self.smooth(Float(age) / Float(attackSamples)) }
        if age >= kotos[i].stopAt {
            env *= max(0, 1 - Float(age - kotos[i].stopAt) / Float(releaseSamples))
        }
        kotos[i].age = age + 1
        if kotos[i].age >= kotos[i].stopAt + releaseSamples { kotos[i].active = false }
        let s = (kotos[i].stringMix * y + kotos[i].bodyMix * body) * env * kotos[i].amplitude
        return (s * kotos[i].left, s * kotos[i].right)
    }

    private func tickFlute(_ i: Int) -> (Float, Float) {
        let seconds = Double(flutes[i].age) / sampleRate
        let total = Double(flutes[i].length) / sampleRate
        var env = Float(Self.smooth(min(1, seconds / 0.35)))
        let tail = total - seconds
        if tail < 0.6 { env *= Float(Self.smooth(max(0, tail / 0.6))) }

        flutes[i].vibrato += 2 * Double.pi * 5.0 / sampleRate
        if flutes[i].vibrato > 2 * Double.pi { flutes[i].vibrato -= 2 * Double.pi }
        flutes[i].phase += flutes[i].step * (1 + 0.004 * sin(flutes[i].vibrato))
        if flutes[i].phase > 2 * Double.pi { flutes[i].phase -= 2 * Double.pi }

        let tone = Float(sin(flutes[i].phase) + 0.12 * sin(2 * flutes[i].phase))
        // Breath: white noise low-passed near 1.5 kHz.
        let alpha: Float = 0.18
        flutes[i].breath += alpha * (nextNoise() - flutes[i].breath)

        flutes[i].age += 1
        if flutes[i].age >= flutes[i].length { flutes[i].active = false }
        let mixed: Float = 0.8 * tone + 0.25 * flutes[i].breath
        let s: Float = mixed * env * flutes[i].amplitude
        return (s * flutes[i].left, s * flutes[i].right)
    }

    private func tickDrone(_ i: Int) -> (Float, Float) {
        let seconds = Double(drones[i].age) / sampleRate
        let total = Double(drones[i].length) / sampleRate
        var env = Float(Self.smooth(min(1, seconds / 3.0)))
        let tail = total - seconds
        if tail < 3.0 { env *= Float(Self.smooth(max(0, tail / 3.0))) }
        // A very slow swell on top of the fades.
        env *= Float(0.9 + 0.1 * sin(2 * Double.pi * 0.07 * seconds))

        drones[i].phase += drones[i].step
        if drones[i].phase > 2 * Double.pi { drones[i].phase -= 2 * Double.pi }
        drones[i].age += 1
        if drones[i].age >= drones[i].length { drones[i].active = false }
        let s = Float(sin(drones[i].phase)) * env * drones[i].amplitude
        return (s * drones[i].left, s * drones[i].right)
    }

    private func tickPiano(_ i: Int) -> (Float, Float) {
        let age = pianos[i].age
        // Soft hammer: a slow 18 ms attack; after the note's end the damper brings it down in 0.6 s.
        var env: Float = 1
        let attack = Int(0.018 * sampleRate)
        if age < attack { env = Self.smooth(Float(age) / Float(attack)) }
        let releaseFrames = Int(0.6 * sampleRate)
        if age >= pianos[i].stopAt {
            env *= max(0, 1 - Float(age - pianos[i].stopAt) / Float(releaseFrames))
        }

        let c = pianos[i].cosine, s = pianos[i].sine
        let mixed = (s * pianos[i].amplitudes).sum()
        pianos[i].cosine = c * pianos[i].stepCosine - s * pianos[i].stepSine
        pianos[i].sine = s * pianos[i].stepCosine + c * pianos[i].stepSine
        pianos[i].amplitudes *= pianos[i].decays

        pianos[i].age = age + 1
        if pianos[i].age >= pianos[i].stopAt + releaseFrames { pianos[i].active = false }
        let out = mixed * env * pianos[i].amplitude
        return (out * pianos[i].left, out * pianos[i].right)
    }

    private func tickEPiano(_ i: Int) -> (Float, Float) {
        let seconds = Double(epianos[i].age) / sampleRate
        // A 15 ms onset: shorter ones click and sound hard on every note.
        let attack = 0.015
        var env = Float(Self.smooth(min(1, seconds / attack))) * Float(exp(-seconds / 1.4))
        if epianos[i].age >= epianos[i].stopAt {
            env *= max(0, 1 - Float(epianos[i].age - epianos[i].stopAt) / Float(releaseSamples * 2))
        }
        // Tine: carrier and modulator at the same pitch, modulation index falling from warm to mellow. A low peak
        // index keeps the attack round; higher ones make every note bark.
        let index = 0.25 + 0.7 * exp(-seconds / 0.25)
        epianos[i].modulator += epianos[i].step
        epianos[i].carrier += epianos[i].step
        let tine = sin(epianos[i].carrier + index * sin(epianos[i].modulator))
        // Bell: a short, very quiet partial at 7 times the pitch, fading out for high notes so it never pings.
        let bell = epianos[i].bellLevel * exp(-seconds / 0.04) * sin(7 * epianos[i].carrier)
        // Gentle tremolo, about 4.5 Hz.
        epianos[i].tremolo += 2 * Double.pi * 4.5 / sampleRate
        if epianos[i].tremolo > 2 * Double.pi { epianos[i].tremolo -= 2 * Double.pi }
        if epianos[i].carrier > 2 * Double.pi * 64 {
            epianos[i].carrier -= 2 * Double.pi * 64
            epianos[i].modulator -= 2 * Double.pi * 64
        }
        let trem = Float(1 - 0.12 * (0.5 + 0.5 * sin(epianos[i].tremolo)))

        epianos[i].age += 1
        if epianos[i].age >= epianos[i].stopAt + releaseSamples * 2 { epianos[i].active = false }
        let out = Float(tine + bell) * env * trem * epianos[i].amplitude
        return (out * epianos[i].left, out * epianos[i].right)
    }

    private func tickPad(_ i: Int) -> (Float, Float) {
        let seconds = Double(pads[i].age) / sampleRate
        let total = Double(pads[i].length) / sampleRate
        var env = Float(Self.smooth(min(1, seconds / 4.0)))
        let tail = total - seconds
        if tail < 5.0 { env *= Float(Self.smooth(max(0, tail / 5.0))) }
        env *= Float(0.88 + 0.12 * sin(2 * Double.pi * 0.06 * seconds + pads[i].swell))

        pads[i].phase += pads[i].step
        let p = pads[i].phase
        // Two slightly detuned sines and a soft octave: a warm, slowly beating tone.
        let tone = Float(sin(p) + 0.8 * sin(p * 1.0035) + 0.25 * sin(2 * p * 0.9985))
        pads[i].age += 1
        if pads[i].age >= pads[i].length { pads[i].active = false }
        let out = tone * env * pads[i].amplitude
        return (out * pads[i].left, out * pads[i].right)
    }

    // MARK: Helpers

    private func nextNoise() -> Float {
        noiseState ^= noiseState << 13
        noiseState ^= noiseState >> 17
        noiseState ^= noiseState << 5
        return Float(Int32(bitPattern: noiseState)) / Float(Int32.max)
    }

    /// Smooth 0...1 curve with zero slope at both ends.
    private static func smooth(_ x: Double) -> Double {
        let c = min(1, max(0, x))
        return c * c * (3 - 2 * c)
    }

    private static func smooth(_ x: Float) -> Float {
        let c = min(1, max(0, x))
        return c * c * (3 - 2 * c)
    }

    private static func frequency(_ midi: Int) -> Double {
        440 * pow(2, Double(midi - 69) / 12)
    }

    /// Soft limiter: linear below 0.6, then a smooth curve that never reaches 1.
    private static func limit(_ x: Float) -> Float {
        guard x.isFinite else { return 0 }
        let a = abs(x)
        if a <= 0.6 { return x }
        let y = 0.6 + 0.39 * tanh((a - 0.6) / 0.39)
        return x < 0 ? -y : y
    }
}
