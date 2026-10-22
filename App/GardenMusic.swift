import AVFoundation
import Foundation
import DharmaGardenCore

/// The garden's music on the Mac's speakers. DharmaGardenCore's `GardenSynth` makes the sound inside an
/// `AVAudioSourceNode`; the composer feeds it phrases a few seconds ahead. A large hall reverb and a very subtle
/// delay sit after it. Music fades in and out over about three seconds, and keeps playing while the app is in the background.
/// Changing the garden theme crossfades: the music fades down, the synth is reset, the new theme's music begins.
@MainActor
final class GardenMusic: ObservableObject {
    static let fadeSeconds = 3.0
    /// Each half of a theme change (fade down, then fade up).
    static let themeFadeSeconds = 1.5
    /// How far ahead of the playhead the composer keeps notes queued.
    private static let lookAhead = 8.0
    /// The largest render block the source node handles; bigger blocks are played as silence.
    private static let maxBlockFrames = 4096

    private let audio = GardenAudio.shared
    private var engine: AVAudioEngine { audio.engine }
    /// The music's part of the shared engine is playing (the engine itself may run for other sounds too).
    private var running = false
    private var synth: GardenSynth?
    private var composer: MusicComposer?
    private var mood = GardenMood.plainDay(season: .spring)
    private var volume = AppSettings.defaultMusicVolume
    private var feeder: Task<Void, Never>?
    private var pauseTask: Task<Void, Never>?
    /// Set while the music fades down to swap the theme.
    private var themeTask: Task<Void, Never>?

    /// The user wants music (set by start and stop).
    private var wantsMusic = false
    /// The app is in the foreground (set by pause and resume).
    private var appActive = true
    init() {
        // Output device changes (headphones plugged in, AirPods connecting) stop the engine.
        audio.onConfigurationChange(.music) { [weak self] in self?.engineConfigurationChanged() }
    }

    /// The output changed and the engine stopped itself. Start again on the new output if music should be playing.
    /// If the engine is still running, only the feeder needs restarting, or the music would dry up.
    private func engineConfigurationChanged() {
        feeder?.cancel()
        feeder = nil
        themeTask?.cancel()
        themeTask = nil
        guard wantsMusic else { return }
        if running, audio.isRunning {
            startFeeder()
            applyLevel(fade: 0.2)
        } else {
            running = false
            begin()
        }
    }

    /// Starts the music (fading in) if the app is active. Safe to call repeatedly.
    func start() {
        wantsMusic = true
        guard appActive else { return }
        begin()
    }

    /// Fades the music out and stops the engine a moment later.
    func stop() {
        wantsMusic = false
        fadeOutAndPause()
    }

    /// Called when the app resigns active: fades out and pauses the engine.
    func pause() {
        appActive = false
        fadeOutAndPause()
    }

    /// Called when the app becomes active: resumes if the user wants music.
    func resume() {
        appActive = true
        if wantsMusic { begin() }
    }

    /// Master volume, 0...1. Applied straight away while music plays.
    func setVolume(_ value: Double) {
        volume = min(max(value, 0), 1)
        // During a theme change the fade up picks the new volume up itself.
        if running, themeTask == nil { applyLevel(fade: 0.2) }
    }

    /// The mood the composer uses for the next phrase, so changes arrive without a cut. A different theme
    /// crossfades instead; the first call (before anything plays) just sets the mood.
    func setMood(_ newMood: GardenMood) {
        let themeChanged = newMood.theme != mood.theme
        mood = newMood
        if themeChanged, running, synth != nil { crossfadeTheme() }
    }

    /// Fades down, then resets the synth (silent by then, so no click) and starts a fresh composer for the new
    /// theme, then fades up again. A second change during the fade restarts it.
    private func crossfadeTheme() {
        themeTask?.cancel()
        synth?.setLevel(0, over: Self.themeFadeSeconds)
        themeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.themeFadeSeconds + 0.1))
            guard !Task.isCancelled, let self else { return }
            self.themeTask = nil
            guard self.running, let synth = self.synth else { return }
            synth.reset()
            self.composer = MusicComposer(seed: UInt64.random(in: 0...UInt64.max))
            self.applyLevel(fade: Self.themeFadeSeconds)
        }
    }

    // MARK: Engine

    private func begin() {
        pauseTask?.cancel()
        pauseTask = nil
        if !running {
            themeTask?.cancel()
            themeTask = nil
            guard buildGraphIfNeeded(), let synth else { return }
            synth.reset()
            composer = MusicComposer(seed: UInt64.random(in: 0...UInt64.max))
            // No usable audio output: the garden stays quiet.
            guard audio.start(for: .music) else { return }
            running = true
            startFeeder()
        }
        applyLevel(fade: Self.fadeSeconds)
    }

    private func fadeOutAndPause() {
        guard running else { return }
        themeTask?.cancel()
        themeTask = nil
        applyLevel(fade: Self.fadeSeconds)
        pauseTask?.cancel()
        pauseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.fadeSeconds + 0.3))
            guard !Task.isCancelled, let self else { return }
            if !(self.wantsMusic && self.appActive) {
                self.pauseEngine()
            }
        }
    }

    private func pauseEngine() {
        feeder?.cancel()
        feeder = nil
        running = false
        audio.release(.music)
    }

    private func applyLevel(fade: Double) {
        let target: Float = wantsMusic ? Float(volume) : 0
        synth?.setLevel(target, over: fade)
    }

    /// The render block runs on the real-time audio thread. It is built in a nonisolated function so it does not
    /// inherit this class's main-actor isolation (which made Swift trap when the audio thread called it).
    private nonisolated static func makeRenderBlock(
        synth: GardenSynth, scratch: UnsafeMutablePointer<Float>, maxFrames: Int
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
            synth.renderInterleaved(into: scratch, frames: frames)
            let left = leftData.assumingMemoryBound(to: Float.self)
            let right = rightData.assumingMemoryBound(to: Float.self)
            for i in 0..<frames {
                left[i] = scratch[2 * i]
                right[i] = scratch[2 * i + 1]
            }
            return noErr
        }
    }

    /// Builds the audio graph once: source node, delay, reverb, then the music bus.
    private func buildGraphIfNeeded() -> Bool {
        if synth != nil { return true }
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        guard rate > 0, let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else {
            return false
        }
        let synth = GardenSynth(sampleRate: rate, channels: 2)
        let scratch = UnsafeMutablePointer<Float>.allocate(capacity: Self.maxBlockFrames * 2)
        scratch.initialize(repeating: 0, count: Self.maxBlockFrames * 2)

        let source = AVAudioSourceNode(
            format: format,
            renderBlock: Self.makeRenderBlock(synth: synth, scratch: scratch, maxFrames: Self.maxBlockFrames))

        let delay = AVAudioUnitDelay()
        delay.delayTime = 0.33
        delay.feedback = 12
        delay.lowPassCutoff = 4500
        delay.wetDryMix = 8

        let reverb = AVAudioUnitReverb()
        reverb.loadFactoryPreset(.largeHall)
        reverb.wetDryMix = 35

        engine.attach(source)
        engine.attach(delay)
        engine.attach(reverb)
        engine.connect(source, to: delay, format: format)
        engine.connect(delay, to: reverb, format: format)
        engine.connect(reverb, to: audio.bus(.music), format: format)

        self.synth = synth
        return true
    }

    // MARK: Feeding the composer

    private func startFeeder() {
        feeder?.cancel()
        feeder = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.feed()
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    /// Adds phrases until the queue reaches a few seconds past the playhead.
    private func feed() {
        guard let synth, var next = composer else { return }
        let horizon = synth.renderedSeconds + Self.lookAhead
        while next.cursor < horizon {
            synth.schedule(next.nextPhrase(mood: mood))
        }
        composer = next
    }
}
