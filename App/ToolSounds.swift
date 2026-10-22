import AVFoundation

/// The short, soft sounds of the player's actions. Each one is made in code once (a few filtered noise bursts and
/// plucked tones), then played from a small pool of player nodes so quick actions can overlap.
enum ToolSound: CaseIterable {
    case water, fork, pull, pick, plant, feed, coin, spot

    /// Least time between two plays of the same sound, so a drag does not machine-gun it.
    var minInterval: TimeInterval {
        switch self {
        case .water: 0.32
        case .fork: 0.18
        case .feed: 0.12
        default: 0.04
        }
    }
}

/// Sounds that last as long as a drag keeps moving: a rake scraping through the soil, a can sprinkling.
enum ToolLoop: CaseIterable {
    case rake, sprinkle
}

@MainActor
final class ToolSounds {
    private static let sampleRate = 44_100.0
    private static let voices = 4

    private let audio = GardenAudio.shared
    private var engine: AVAudioEngine { audio.engine }
    /// Lets the shared engine pause a while after the last sound.
    private var releaseTask: Task<Void, Never>?
    /// Level of each sound before the player's effects volume, so the slider's middle sits under the music.
    private static let trim: Float = 0.7
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [ToolSound: AVAudioPCMBuffer] = [:]
    private var nextVoice = 0
    private var lastPlayed: [ToolSound: Date] = [:]
    private var ready = false

    /// One looping player per drag sound, each through its own mixer so it can fade.
    private struct LoopVoice {
        let player: AVAudioPlayerNode
        let mixer: AVAudioMixerNode
        let buffer: AVAudioPCMBuffer
        var playing = false
        var heldUntil = Date.distantPast
        var fade: Task<Void, Never>?
    }
    private var loops: [ToolLoop: LoopVoice] = [:]
    /// How long a loop keeps going after the last drag step, so a slow drag does not stutter.
    private static let loopHold: TimeInterval = 0.25

    /// Plays `sound` unless it was played too recently. Silent if the audio engine cannot start.
    func play(_ sound: ToolSound) {
        let now = Date()
        if let last = lastPlayed[sound], now.timeIntervalSince(last) < sound.minInterval { return }
        guard prepare(), let buffer = buffers[sound] else { return }
        lastPlayed[sound] = now
        let player = players[nextVoice]
        nextVoice = (nextVoice + 1) % players.count
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.play()
    }

    /// Keeps `loop` playing for a moment longer: it fades in on the first call and fades out once the calls stop.
    func sustain(_ loop: ToolLoop) {
        guard prepare(), var voice = loops[loop] else { return }
        voice.heldUntil = Date().addingTimeInterval(Self.loopHold)
        if !voice.playing {
            voice.playing = true
            voice.player.stop()
            voice.player.scheduleBuffer(voice.buffer, at: nil, options: .loops, completionHandler: nil)
            voice.player.play()
            voice.fade?.cancel()
            voice.fade = Task { [weak self] in await self?.runLoop(loop) }
        }
        loops[loop] = voice
    }

    /// Fades the loop in, waits while it is held, then fades it out and stops it.
    private func runLoop(_ loop: ToolLoop) async {
        guard let mixer = loops[loop]?.mixer else { return }
        let step = 0.015
        while mixer.outputVolume < 1 {
            mixer.outputVolume = min(1, mixer.outputVolume + Float(step / 0.08))
            try? await Task.sleep(for: .seconds(step))
        }
        while let held = loops[loop]?.heldUntil, held > Date() {
            try? await Task.sleep(for: .seconds(0.03))
        }
        while mixer.outputVolume > 0 {
            if let held = loops[loop]?.heldUntil, held > Date() {
                // Picked up again while fading: go back up and keep holding.
                await runLoop(loop)
                return
            }
            mixer.outputVolume = max(0, mixer.outputVolume - Float(step / 0.22))
            try? await Task.sleep(for: .seconds(step))
        }
        loops[loop]?.player.stop()
        loops[loop]?.playing = false
    }

    /// Builds the graph and the buffers on first use, and starts the shared engine if it is not running.
    private func prepare() -> Bool {
        if !ready {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1) else { return false }
            for _ in 0..<Self.voices {
                let player = AVAudioPlayerNode()
                engine.attach(player)
                engine.connect(player, to: audio.bus(.effects), format: format)
                player.volume = Self.trim
                players.append(player)
            }
            for sound in ToolSound.allCases {
                buffers[sound] = Self.makeBuffer(for: sound, format: format)
            }
            for loop in ToolLoop.allCases {
                guard let buffer = Self.makeBuffer(Self.renderLoop(loop), format: format) else { continue }
                let player = AVAudioPlayerNode()
                let mixer = AVAudioMixerNode()
                engine.attach(player)
                engine.attach(mixer)
                engine.connect(player, to: mixer, format: format)
                engine.connect(mixer, to: audio.bus(.effects), format: format)
                player.volume = Self.trim
                mixer.outputVolume = 0
                loops[loop] = LoopVoice(player: player, mixer: mixer, buffer: buffer)
            }
            ready = true
        }
        guard audio.start(for: .effects) else { return false }
        releaseTask?.cancel()
        releaseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, !self.loops.values.contains(where: \.playing) else { return }
            self.audio.release(.effects)
        }
        return true
    }

    // MARK: Making the sounds

    private static func makeBuffer(for sound: ToolSound, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        makeBuffer(render(sound), format: format)
    }

    private static func makeBuffer(_ samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (i, v) in samples.enumerated() { channel[i] = v }
        return buffer
    }

    /// Small deterministic noise source, so a sound is the same every time it is made.
    private struct Noise {
        var state: UInt64 = 0x2545_F491_4F6C_DD1D
        mutating func next() -> Float {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return Float(Double(state >> 11) / Double(1 << 53)) * 2 - 1
        }
    }

    /// A soft, rounded tone: a sine with a faint octave, a gentle attack and an exponential decay.
    private static func pluck(_ out: inout [Float], at start: Double, freq: Double, decay: Double, gain: Float) {
        let first = Int(start * sampleRate)
        let length = Int(decay * 6 * sampleRate)
        for i in 0..<length where first + i < out.count {
            let t = Double(i) / sampleRate
            let env = Float(exp(-t / decay)) * Float(min(1, t / 0.02))
            let tone = Float(sin(2 * .pi * freq * t)) + 0.08 * Float(sin(4 * .pi * freq * t))
            out[first + i] += tone * env * gain
        }
    }

    /// A short rounded "pop": a sine that drops quickly in pitch, like a stem snapping free.
    private static func pop(_ out: inout [Float], at start: Double, from: Double, to: Double, length: Double, gain: Float) {
        let first = Int(start * sampleRate)
        let count = Int(length * sampleRate)
        var phase = 0.0
        for i in 0..<count where first + i < out.count {
            let p = Double(i) / Double(count)
            phase += 2 * .pi * (from + (to - from) * p) / sampleRate
            let env = Float(min(1, p / 0.08)) * Float(pow(1 - p, 2))
            out[first + i] += Float(sin(phase)) * env * gain
        }
    }

    /// Noise through a two-stage low-pass whose cutoff moves from `from` to `to`, with a smooth rise and fall.
    private static func noiseBurst(_ out: inout [Float], at start: Double, length: Double, from: Double, to: Double,
                                   gain: Float, attack: Double = 0.02, noise: inout Noise) {
        let first = Int(start * sampleRate)
        let count = Int(length * sampleRate)
        var y: Float = 0
        var z: Float = 0
        for i in 0..<count where first + i < out.count {
            let p = Double(i) / Double(count)
            let cutoff = from + (to - from) * p
            let a = Float(1 - exp(-2 * .pi * cutoff / sampleRate))
            y += a * (noise.next() - y)
            z += a * (y - z)
            let t = Double(i) / sampleRate
            let rise = Float(min(1, t / attack))
            let env = rise * rise * (3 - 2 * rise) * Float(pow(1 - p, 1.5))
            out[first + i] += z * env * gain * 1.8
        }
    }

    /// A water bubble: a sine that rises a little in pitch as it rings out (the sound of an air pocket closing).
    private static func bubble(_ out: inout [Float], at start: Double, freq: Double, decay: Double, gain: Float) {
        let first = Int(start * sampleRate)
        let count = Int(decay * 5 * sampleRate)
        var phase = 0.0
        for i in 0..<count where first + i < out.count {
            let t = Double(i) / sampleRate
            phase += 2 * .pi * freq * (1 + 6 * t) / sampleRate
            let env = Float(exp(-t / decay)) * Float(min(1, t / 0.002))
            out[first + i] += Float(sin(phase)) * env * gain
        }
    }

    /// A scatter of bubbles between `from` and `to` seconds, `perSecond` of them, low ones louder than high ones.
    private static func bubbles(_ out: inout [Float], from: Double, to: Double, perSecond: Double,
                                low: Double, high: Double, gain: Float, noise: inout Noise) {
        let count = Int((to - from) * perSecond)
        for _ in 0..<count {
            let u = Double(noise.next() + 1) / 2
            let at = from + (to - from) * Double(noise.next() + 1) / 2
            let freq = low * pow(high / low, u)
            let decay = 0.006 + 0.02 * (1 - u)
            bubble(&out, at: at, freq: freq, decay: decay, gain: gain * Float(0.4 + 0.6 * (1 - u)))
        }
    }

    /// A one-pole low-pass over the whole sound, to take any remaining edge off.
    private static func soften(_ out: inout [Float], cutoff: Double) {
        let a = Float(1 - exp(-2 * .pi * cutoff / sampleRate))
        var y: Float = 0
        var z: Float = 0
        for i in out.indices {
            y += a * (out[i] - y)
            z += a * (y - z)
            out[i] = z
        }
    }

    private static func render(_ sound: ToolSound) -> [Float] {
        var noise = Noise()
        var out = [Float](repeating: 0, count: Int(sampleRate * 0.9))
        switch sound {
        case .water:
            // Water from the can landing on the soil: a quiet wash under a run of small bubbles and drips.
            noiseBurst(&out, at: 0, length: 0.75, from: 250, to: 500, gain: 0.5, attack: 0.1, noise: &noise)
            bubbles(&out, from: 0.02, to: 0.65, perSecond: 70, low: 450, high: 1500, gain: 0.22, noise: &noise)
            let tail = Int(sampleRate * 0.65)
            for i in tail..<out.count { out[i] *= Float(exp(-Double(i - tail) / (sampleRate * 0.08))) }
        case .fork:
            // The tines going in: a dull thud and a crunch of soil.
            pluck(&out, at: 0, freq: 90, decay: 0.09, gain: 0.35)
            noiseBurst(&out, at: 0.02, length: 0.22, from: 700, to: 300, gain: 1.0, attack: 0.02, noise: &noise)
        case .pull:
            // A weed coming out of the ground: a short rip that rises then stops.
            noiseBurst(&out, at: 0, length: 0.3, from: 300, to: 1100, gain: 1.0, attack: 0.08, noise: &noise)
        case .pick:
            // The pop of the stem coming free, then the bloom landing in the basket.
            pop(&out, at: 0, from: 520, to: 190, length: 0.07, gain: 0.5)
            pluck(&out, at: 0.07, freq: 523, decay: 0.12, gain: 0.3)
            pluck(&out, at: 0.15, freq: 659, decay: 0.14, gain: 0.25)
        case .plant:
            pluck(&out, at: 0, freq: 110, decay: 0.1, gain: 0.5)
            noiseBurst(&out, at: 0, length: 0.12, from: 600, to: 250, gain: 0.7, attack: 0.02, noise: &noise)
        case .feed:
            // Granules pattering onto the soil.
            for i in 0..<14 {
                let at = Double(i) * 0.028 + Double(noise.next() + 1) * 0.01
                noiseBurst(&out, at: at, length: 0.04, from: 1100, to: 500, gain: 0.6, attack: 0.012, noise: &noise)
            }
        case .coin:
            pluck(&out, at: 0, freq: 784, decay: 0.12, gain: 0.3)
            pluck(&out, at: 0.09, freq: 988, decay: 0.16, gain: 0.3)
        case .spot:
            pluck(&out, at: 0, freq: 523, decay: 0.14, gain: 0.28)
            pluck(&out, at: 0.11, freq: 659, decay: 0.14, gain: 0.3)
            pluck(&out, at: 0.22, freq: 784, decay: 0.2, gain: 0.3)
        }
        soften(&out, cutoff: 1800)
        // Short fade-out so nothing ends on a click.
        let fade = Int(sampleRate * 0.05)
        for i in 0..<fade { out[out.count - 1 - i] *= Float(i) / Float(fade) }
        // Keep clear of clipping whatever was layered.
        let peak = out.map { abs($0) }.max() ?? 0
        if peak > 0.9 { out = out.map { $0 * 0.9 / peak } }
        return out
    }

    /// A seamless loop for a drag sound: rendered a little long, with the end crossfaded into the start.
    private static func renderLoop(_ loop: ToolLoop) -> [Float] {
        var noise = Noise(state: loop == .rake ? 0x51_7CC1_B727_220A : 0x94D0_49BB_1331_11EB)
        let length = 2.4, overlap = 0.3
        var out = [Float](repeating: 0, count: Int(sampleRate * (length + overlap)))
        switch loop {
        case .rake:
            // Tines drawn through loose soil: a low brushing bed that swells with each pull, and the patter of
            // crumbs and little stones catching on the tines.
            var y: Float = 0, z: Float = 0
            let a = Float(1 - exp(-2 * .pi * 450 / sampleRate))
            for i in out.indices {
                y += a * (noise.next() - y)
                z += a * (y - z)
                let t = Double(i) / sampleRate
                let stroke = Float(0.55 + 0.45 * sin(2 * .pi * 1.6 * t))
                out[i] += z * stroke * 1.6
            }
            var t = 0.0
            while t < length + overlap {
                let cutoff = 700 + 700 * Double(noise.next() + 1) / 2
                let gain = 0.12 + 0.18 * Float(noise.next() + 1) / 2
                noiseBurst(&out, at: t, length: 0.012 + 0.012 * Double(noise.next() + 1) / 2,
                           from: cutoff, to: cutoff * 0.6, gain: gain, attack: 0.002, noise: &noise)
                t += 0.008 + 0.03 * Double(noise.next() + 1) / 2
            }
        case .sprinkle:
            // A rose on the can: a soft patter of drops and bubbles over a gentle wash.
            var y: Float = 0, z: Float = 0
            let a = Float(1 - exp(-2 * .pi * 600 / sampleRate))
            for i in out.indices {
                y += a * (noise.next() - y)
                z += a * (y - z)
                out[i] += z * 0.5
            }
            bubbles(&out, from: 0, to: length + overlap, perSecond: 90, low: 500, high: 1700, gain: 0.2, noise: &noise)
        }
        soften(&out, cutoff: 1800)
        let n = Int(sampleRate * length), o = Int(sampleRate * overlap)
        for i in 0..<o {
            let f = Float(i) / Float(o)
            out[i] = out[i] * f + out[n + i] * (1 - f)
        }
        out.removeLast(out.count - n)
        let peak = out.map { abs($0) }.max() ?? 0
        if peak > 0 { out = out.map { $0 * 0.45 / peak } }
        return out
    }
}
