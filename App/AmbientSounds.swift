import AVFoundation
import Foundation
import WeedsCore

/// The garden's ambience on the Mac's speakers: birds by day, crickets at night, rain with the weather. WeedsCore's
/// `AmbientSynth` makes the sound inside an `AVAudioSourceNode`; this class owns the engine, the fades and the levels.
/// It fades in and out over a couple of seconds and keeps playing while the app is in the background, like the music.
@MainActor
final class AmbientSounds {
    /// Where the player's ambient volume sits relative to full scale. Kept low so it sits under the music.
    private static let baseLevel = 0.7
    private static let fadeSeconds = 2.5
    private static let maxBlockFrames = 4096

    private let engine = AVAudioEngine()
    private var synth: AmbientSynth?
    private var scratch: UnsafeMutablePointer<Float>?
    private var mix = AmbientMix.silent
    private var wantsSound = false
    private var pauseTask: Task<Void, Never>?
    private var configObserver: NSObjectProtocol?

    init() {
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.configurationChanged() }
        }
    }

    deinit { scratch?.deallocate() }

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
        if !engine.isRunning {
            guard buildGraphIfNeeded() else { return }
            do { try engine.start() } catch { return }
        }
        applyTarget()
    }

    private func applyTarget() {
        synth?.setTarget(mix, level: wantsSound ? Self.baseLevel : 0)
    }

    private func fadeOutAndPause() {
        guard engine.isRunning else { return }
        applyTarget()
        pauseTask?.cancel()
        pauseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.fadeSeconds + 1.5))
            guard !Task.isCancelled, let self, !self.wantsSound else { return }
            self.engine.pause()
        }
    }

    private func configurationChanged() {
        guard wantsSound else { return }
        if !engine.isRunning { begin() } else { applyTarget() }
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
        reverb.wetDryMix = 22
        engine.attach(source)
        engine.attach(reverb)
        engine.connect(source, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        engine.prepare()
        self.synth = synth
        self.scratch = scratch
        return true
    }
}
