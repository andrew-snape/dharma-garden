import AVFoundation
import DharmaGardenCore

/// Plays the garden's single handpan notes: 18 short recordings (9 notes, each soft and medium, made by
/// `GardenRender notes`) through a pool of six voices on the music bus, so they share the music volume. The
/// recordings load on first use. If all six voices are busy the oldest is faded out quickly and reused.
@MainActor
final class GardenNotesPlayer {
    static let voiceCount = 6
    /// The strike strengths the recordings were made at (see `GardenRender notes`).
    private static let softVelocity = 0.25
    private static let mediumVelocity = 0.5
    /// From this velocity up the medium recording is used (it is rendered with a harder strike, so brighter).
    private static let mediumFrom = 0.28
    /// Time a stolen voice takes to fade out before it is reused, so a cut never clicks.
    private static let stealFade = 0.08

    private struct Voice {
        let player: AVAudioPlayerNode
        let mixer: AVAudioMixerNode
        var busyUntil = Date.distantPast
        var startedAt = Date.distantPast
        var generation = 0
    }

    private let audio = GardenAudio.shared
    private var engine: AVAudioEngine { audio.engine }
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var voices: [Voice] = []
    private var loading: Task<Bool, Never>?

    /// Bytes of decoded audio kept in memory once the notes are loaded (reported in the debug drawer).
    var residentBytes: Int {
        buffers.values.reduce(0) { $0 + Int($1.frameLength) * Int($1.format.channelCount) * 4 }
    }

    /// Plays note `index` (0...8 on the handpan's ring) at `velocity` 0...1 and `pan` -1...1. The caller has
    /// started the engine.
    func play(index: Int, velocity: Double, pan: Double) {
        Task { [weak self] in
            guard let self, await self.ensureLoaded() else { return }
            self.start(index: index, velocity: velocity, pan: pan)
        }
    }

    private func ensureLoaded() async -> Bool {
        if !voices.isEmpty { return true }
        if let loading { return await loading.value }
        let task = Task { [weak self] () -> Bool in
            // Decoding 18 small files is quick, but not on the main thread: the first note should not hitch the garden.
            guard let loaded = await Task.detached(priority: .utility, operation: { Self.loadBuffers() }).value,
                  let self else { return false }
            self.buffers = loaded.buffers
            self.buildVoices(format: loaded.format)
            return !self.voices.isEmpty
        }
        loading = task
        return await task.value
    }

    private struct Loaded: @unchecked Sendable {
        var buffers: [String: AVAudioPCMBuffer]
        var format: AVAudioFormat
    }

    private nonisolated static func loadBuffers() -> Loaded? {
        var buffers: [String: AVAudioPCMBuffer] = [:]
        var format: AVAudioFormat?
        for index in 0..<GardenNotes.scaleCount {
            for strength in ["soft", "medium"] {
                let name = "note-\(index)-\(strength)"
                guard let url = GardenMusic.resourceURL(name, folder: "Music/notes"),
                      let file = try? AVAudioFile(forReading: url),
                      let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                    frameCapacity: AVAudioFrameCount(file.length)),
                      (try? file.read(into: buffer)) != nil else { continue }
                buffers[name] = buffer
                format = format ?? file.processingFormat
            }
        }
        guard let format, !buffers.isEmpty else { return nil }
        return Loaded(buffers: buffers, format: format)
    }

    private func buildVoices(format: AVAudioFormat) {
        for _ in 0..<Self.voiceCount {
            let player = AVAudioPlayerNode()
            let mixer = AVAudioMixerNode()
            engine.attach(player)
            engine.attach(mixer)
            engine.connect(player, to: mixer, format: format)
            engine.connect(mixer, to: audio.bus(.music), format: format)
            voices.append(Voice(player: player, mixer: mixer))
        }
    }

    private func start(index: Int, velocity: Double, pan: Double) {
        let medium = velocity >= Self.mediumFrom
        let name = "note-\(index)-\(medium ? "medium" : "soft")"
        guard let buffer = buffers[name] else { return }
        // Recorded levels follow the strike, so a note played softer than its recording is turned down to match.
        let reference = medium ? Self.mediumVelocity : Self.softVelocity
        let gain = Float(min(1, pow(max(velocity, 0.01) / reference, 1.2)))
        let length = Double(buffer.frameLength) / buffer.format.sampleRate
        let now = Date()

        let slot: Int
        var stolen = false
        if let free = voices.indices.first(where: { voices[$0].busyUntil <= now }) {
            slot = free
        } else {
            slot = voices.indices.min { voices[$0].startedAt < voices[$1].startedAt } ?? 0
            stolen = true
        }
        voices[slot].generation += 1
        voices[slot].startedAt = now
        voices[slot].busyUntil = now.addingTimeInterval(length)
        let generation = voices[slot].generation
        let voice = voices[slot]

        func sound() {
            voice.player.stop()
            voice.mixer.outputVolume = 1
            voice.player.volume = gain
            voice.player.pan = Float(min(max(pan, -1), 1))
            voice.player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            voice.player.play()
        }
        if stolen {
            // Fade the old note out, then strike the new one. The ramp is kept alive by its own task.
            let ramp = LevelRamp(initial: 1) { voice.mixer.outputVolume = $0 }
            ramp.ramp(to: 0, over: Self.stealFade) { [weak self] in
                _ = ramp
                // Another note took the voice in the meantime: let that one play.
                guard let self, self.voices[slot].generation == generation else { return }
                sound()
            }
        } else {
            sound()
        }
    }
}
