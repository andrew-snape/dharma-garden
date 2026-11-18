import AVFoundation
import Foundation
import DharmaGardenCore

/// The garden's ambience on the Mac's speakers: birds by day, crickets at night, rain with the weather. Each layer is a
/// recorded loop (App/Sounds, CC0 field recordings from BigSoundBank) whose volume follows the mix. A layer whose
/// recording cannot be loaded falls back to DharmaGardenCore's `AmbientSynth`, which makes it in code. It fades in and
/// out over a couple of seconds and keeps playing while the app is in the background, like the music.
@MainActor
final class AmbientSounds {
    /// The ambience's level before the player's ambience volume, kept low so it sits under the music.
    private static let baseLevel = 0.55
    private static let fadeSeconds = 2.5
    private static let maxBlockFrames = 4096

    private let audio = GardenAudio.shared
    private var engine: AVAudioEngine { audio.engine }
    /// The ambience's part of the shared engine is playing.
    private var running = false
    private var synth: AmbientSynth?
    private var mix = AmbientMix.silent
    private var wantsSound = false
    private var pauseTask: Task<Void, Never>?

    enum Layer: String, CaseIterable {
        case birds, crickets, rain
    }

    /// Each recording's level at full mix, before the player's ambience volume. The loops are all evened out to
    /// the same loudness, so this sets the balance: crickets drone all night, so they sit lowest.
    private static let trims: [Layer: Float] = [.birds: 0.4, .crickets: 0.22, .rain: 0.45]

    private struct Recording {
        let player: AVAudioPlayerNode
        let buffer: AVAudioPCMBuffer
    }
    private var recordings: [Layer: Recording] = [:]
    private var rampTask: Task<Void, Never>?

    init() {
        audio.onConfigurationChange(.ambient) { [weak self] in self?.configurationChanged() }
    }

    /// Starts (fading in) or stops (fading out) the ambience. Safe to call repeatedly.
    func setEnabled(_ on: Bool) {
        wantsSound = on
        if on { begin() } else { fadeOutAndPause() }
    }

    /// What the weather and time of day call for. Applied smoothly while the sound plays.
    func setMix(_ newMix: AmbientMix) {
        mix = newMix
        applyTarget()
    }

    private func begin() {
        pauseTask?.cancel()
        pauseTask = nil
        if !running {
            guard buildGraphIfNeeded(), audio.start(for: .ambient) else { return }
            running = true
        }
        applyTarget()
    }

    private func applyTarget() {
        // The synth makes only the layers that have no recording.
        let synthMix = AmbientMix(birds: recordings[.birds] == nil ? mix.birds : 0,
                                  crickets: recordings[.crickets] == nil ? mix.crickets : 0,
                                  rain: recordings[.rain] == nil ? mix.rain : 0)
        synth?.setTarget(synthMix, level: wantsSound ? Self.baseLevel : 0)
        startRecordings()
        if rampTask == nil { rampTask = Task { [weak self] in await self?.rampRecordings() } }
    }

    private func level(of layer: Layer) -> Float {
        guard wantsSound else { return 0 }
        let amount = switch layer { case .birds: mix.birds; case .crickets: mix.crickets; case .rain: mix.rain }
        return Float(min(max(amount, 0), 1)) * (Self.trims[layer] ?? 0)
    }

    /// Starts any loop that is not playing. They all run while the ambience does, silent when their layer is off.
    private func startRecordings() {
        guard running else { return }
        for recording in recordings.values where !recording.player.isPlaying {
            recording.player.scheduleBuffer(recording.buffer, at: nil, options: .loops, completionHandler: nil)
            recording.player.play()
        }
    }

    /// Eases each loop's volume toward its level (about 2.5 s to get most of the way), then stops when all are there.
    private func rampRecordings() async {
        let step = 0.05
        let ease = Float(1 - exp(-step / (Self.fadeSeconds / 2.5)))
        while !Task.isCancelled {
            var settled = true
            for (layer, recording) in recordings {
                let target = level(of: layer)
                let now = recording.player.volume
                if abs(target - now) < 0.002 {
                    recording.player.volume = target
                } else {
                    recording.player.volume = now + (target - now) * ease
                    settled = false
                }
            }
            if settled { break }
            try? await Task.sleep(for: .seconds(step))
        }
        rampTask = nil
    }

    private func fadeOutAndPause() {
        guard running else { return }
        applyTarget()
        pauseTask?.cancel()
        pauseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.fadeSeconds + 1.5))
            guard !Task.isCancelled, let self, !self.wantsSound else { return }
            self.running = false
            for recording in self.recordings.values { recording.player.stop() }
            self.audio.release(.ambient)
        }
    }

    private func configurationChanged() {
        guard wantsSound else { return }
        if !audio.isRunning { running = false }
        // The engine stopping also stops the loops' players; schedule them again.
        for recording in recordings.values { recording.player.stop() }
        if !running { begin() } else { applyTarget() }
    }

    /// Built in a nonisolated function so the audio thread does not inherit main-actor isolation (see GardenMusic).
    private nonisolated static func makeRenderBlock(
        synth: AmbientSynth, scratch: UnsafeMutablePointer<Float>, maxFrames: Int
    ) -> AVAudioSourceNodeRenderBlock {
        return { _, _, frameCount, audioBufferList in
            let frames = Int(frameCount)
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard frames <= maxFrames, buffers.count == 2,
                  let leftData = buffers[0].mData, let rightData = buffers[1].mData else {
                for buffer in buffers {
                    if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
                }
                return noErr
            }
            synth.render(into: scratch, frames: frames)
            let left = leftData.assumingMemoryBound(to: Float.self)
            let right = rightData.assumingMemoryBound(to: Float.self)
            for i in 0..<frames {
                left[i] = scratch[2 * i]
                right[i] = scratch[2 * i + 1]
            }
            return noErr
        }
    }

    private func buildGraphIfNeeded() -> Bool {
        if synth != nil { return true }
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        guard rate > 0, let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { return false }
        let synth = AmbientSynth(sampleRate: rate, seed: UInt64.random(in: 1...UInt64.max))
        let scratch = UnsafeMutablePointer<Float>.allocate(capacity: Self.maxBlockFrames * 2)
        scratch.initialize(repeating: 0, count: Self.maxBlockFrames * 2)
        let source = AVAudioSourceNode(
            format: format,
            renderBlock: Self.makeRenderBlock(synth: synth, scratch: scratch, maxFrames: Self.maxBlockFrames))
        let reverb = AVAudioUnitReverb()
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 35
        engine.attach(source)
        engine.attach(reverb)
        engine.connect(source, to: reverb, format: format)
        engine.connect(reverb, to: audio.bus(.ambient), format: format)
        self.synth = synth
        loadRecordings()
        return true
    }

    /// Loads each layer's loop into memory (about a megabyte each as AAC, decoded once) and wires it to the ambience
    /// bus. The recordings carry their own space, so they skip the synth's reverb.
    private func loadRecordings() {
        for layer in Layer.allCases {
            guard let url = Bundle.main.url(forResource: "ambient-\(layer.rawValue)", withExtension: "m4a"),
                  let file = try? AVAudioFile(forReading: url),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: buffer)) != nil else { continue }
            let player = AVAudioPlayerNode()
            player.volume = 0
            engine.attach(player)
            engine.connect(player, to: audio.bus(.ambient), format: buffer.format)
            recordings[layer] = Recording(player: player, buffer: buffer)
        }
    }
}
