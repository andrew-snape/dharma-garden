import AVFoundation
import DharmaGardenCore

/// Plays the garden's notes through the GeneralUser GS soundfont (App/Sounds) instead of DharmaGardenCore's synth.
/// The composer's `NoteEvent`s keep their times, measured from the last `reset()`. A timer starts and stops each note
/// on its own MIDI channel about 50 times a second, so the timing is accurate to a few milliseconds.
@MainActor
final class GardenSampler {
    /// The General MIDI program and MIDI channel for each garden voice.
    private static let voices: [MusicVoice: (program: UInt8, channel: UInt8)] = [
        .koto: (107, 0), .flute: (73, 1), .drone: (89, 2), .pluck: (24, 3),
        .bass: (32, 4), .piano: (0, 5), .epiano: (4, 6), .pad: (89, 7),
    ]
    private static let tick: Duration = .milliseconds(20)
    private static let rampStep: Duration = .milliseconds(50)
    private static let melodicBankMSB = UInt8(kAUSampler_DefaultMelodicBankMSB)
    private static let bankLSB = UInt8(kAUSampler_DefaultBankLSB)

    private let sampler = AVAudioUnitSampler()
    /// The sampler's output. Its volume is the music's level; the music effects chain connects to it.
    let output = AVAudioMixerNode()
    private var origin = Date()
    private var pending: [NoteEvent] = []
    private var sounding: [(end: Double, note: UInt8, channel: UInt8)] = []
    private var ticker: Task<Void, Never>?
    private var rampTask: Task<Void, Never>?

    /// Attaches the sampler to `engine` and loads the bank. Nil when the bank is missing or will not load.
    init?(engine: AVAudioEngine, format: AVAudioFormat) {
        guard let url = Bundle.main.url(forResource: "GeneralUser-GS", withExtension: "sf2") else { return nil }
        for voice in Self.voices.values {
            do {
                try sampler.loadSoundBankInstrument(at: url, program: voice.program,
                                                    bankMSB: Self.melodicBankMSB, bankLSB: Self.bankLSB)
            } catch {
                return nil
            }
            sampler.sendProgramChange(voice.program, bankMSB: Self.melodicBankMSB, bankLSB: Self.bankLSB,
                                      onChannel: voice.channel)
        }
        engine.attach(sampler)
        engine.attach(output)
        engine.connect(sampler, to: output, format: format)
    }

    /// The composer's clock: seconds since the last `reset()`.
    var renderedSeconds: Double { Date().timeIntervalSince(origin) }

    /// Queues notes. Times in the past play at once.
    func schedule(_ events: [NoteEvent]) {
        pending.append(contentsOf: events)
        pending.sort { $0.time < $1.time }
        if ticker == nil { startTicker() }
    }

    /// Silences every note, drops the queue, restarts the clock at zero and the level at silence.
    func reset() {
        stopAll()
        origin = Date()
        rampTask?.cancel()
        output.outputVolume = 0
    }

    /// Ramps the output to `target` (0...1) over `seconds`.
    func setLevel(_ target: Float, over seconds: Double) {
        rampTask?.cancel()
        let start = output.outputVolume
        let steps = max(1, Int((seconds / 0.05).rounded()))
        rampTask = Task { [weak self] in
            for step in 1...steps {
                try? await Task.sleep(for: Self.rampStep)
                guard !Task.isCancelled, let self else { return }
                self.output.outputVolume = start + (target - start) * Float(step) / Float(steps)
            }
        }
    }

    private func startTicker() {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.dispatch()
                try? await Task.sleep(for: Self.tick)
            }
        }
    }

    /// Starts the notes that are due and stops the ones that have finished.
    private func dispatch() {
        let now = renderedSeconds
        while let next = pending.first, next.time <= now {
            pending.removeFirst()
            guard let voice = Self.voices[next.voice] else { continue }
            let note = UInt8(min(max(next.midiNote, 0), 127))
            let velocity = UInt8(min(max(Int((next.velocity * 127).rounded()), 1), 127))
            sampler.startNote(note, withVelocity: velocity, onChannel: voice.channel)
            sounding.append((next.time + next.duration, note, voice.channel))
        }
        var stillSounding: [(end: Double, note: UInt8, channel: UInt8)] = []
        for note in sounding {
            if note.end <= now {
                sampler.stopNote(note.note, onChannel: note.channel)
            } else {
                stillSounding.append(note)
            }
        }
        sounding = stillSounding
    }

    private func stopAll() {
        for note in sounding {
            sampler.stopNote(note.note, onChannel: note.channel)
        }
        sounding.removeAll()
        pending.removeAll()
    }
}
