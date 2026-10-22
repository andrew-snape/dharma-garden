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

@MainActor
final class ToolSounds {
    private static let sampleRate = 44_100.0
    private static let voices = 4

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [ToolSound: AVAudioPCMBuffer] = [:]
    private var nextVoice = 0
    private var lastPlayed: [ToolSound: Date] = [:]
    private var ready = false

    /// Overall level, 0...1. Kept low so the sounds sit under the music.
    var volume: Float = 0.5 {
        didSet { engine.mainMixerNode.outputVolume = volume }
    }

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

    /// Builds the graph and the buffers on first use, and restarts the engine if the output device changed.
    private func prepare() -> Bool {
        if !ready {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1) else { return false }
            for _ in 0..<Self.voices {
                let player = AVAudioPlayerNode()
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
                players.append(player)
            }
            for sound in ToolSound.allCases {
                buffers[sound] = Self.makeBuffer(for: sound, format: format)
            }
            engine.mainMixerNode.outputVolume = volume
            ready = true
        }
        if !engine.isRunning {
            engine.prepare()
            do { try engine.start() } catch { return false }
        }
        return true
    }

    // MARK: Making the sounds

    private static func makeBuffer(for sound: ToolSound, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let samples = render(sound)
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
            // A soft pour: low-passed noise that brightens a little as it falls.
            noiseBurst(&out, at: 0, length: 0.7, from: 350, to: 900, gain: 1.4, attack: 0.12, noise: &noise)
        case .fork:
            // The tines going in: a dull thud and a crunch of soil.
            pluck(&out, at: 0, freq: 90, decay: 0.09, gain: 0.6)
            noiseBurst(&out, at: 0.02, length: 0.22, from: 700, to: 300, gain: 1.0, attack: 0.02, noise: &noise)
        case .pull:
            // A weed coming out of the ground: a short rip that rises then stops.
            noiseBurst(&out, at: 0, length: 0.3, from: 300, to: 1100, gain: 1.0, attack: 0.08, noise: &noise)
        case .pick:
            pluck(&out, at: 0, freq: 523, decay: 0.12, gain: 0.3)
            pluck(&out, at: 0.08, freq: 659, decay: 0.14, gain: 0.25)
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
}
