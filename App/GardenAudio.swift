import AVFoundation

/// The one audio engine the garden plays through. Music, ambience and tool sounds each get their own bus (a mixer
/// node into the main mixer), so their levels are set in one place and they share a single output. The engine
/// runs while any part wants sound and pauses when none does. When the output device changes (headphones,
/// AirPods) the engine is restarted once and each part is told, so it can pick up where it was.
@MainActor
final class GardenAudio {
    static let shared = GardenAudio()

    enum Part: CaseIterable {
        case music, ambient, effects
    }

    let engine = AVAudioEngine()
    private var buses: [Part: AVAudioMixerNode] = [:]
    /// The player's slider level for each part, and a temporary gain on top of it (see `setDuck`).
    private var levels: [Part: Float] = [:]
    private var ducks: [Part: Float] = [:]
    private var wanting: Set<Part> = []
    private var configurationHandlers: [Part: () -> Void] = [:]
    private var configObserver: NSObjectProtocol?

    private init() {
        for part in Part.allCases {
            let bus = AVAudioMixerNode()
            engine.attach(bus)
            engine.connect(bus, to: engine.mainMixerNode, format: nil)
            buses[part] = bus
        }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.configurationChanged() }
        }
    }

    /// The mixer a part connects its nodes to.
    func bus(_ part: Part) -> AVAudioMixerNode { buses[part]! }

    /// A part's level, 0...1 (the player's volume slider for it).
    func setVolume(_ volume: Double, for part: Part) {
        levels[part] = Float(min(max(volume, 0), 1))
        applyLevel(part)
    }

    /// A temporary gain (1 = none) that sits under a part's level without changing the slider's value. The music
    /// uses it to lower the ambience a little while a piece plays.
    func setDuck(_ gain: Float, for part: Part) {
        ducks[part] = min(max(gain, 0), 1)
        applyLevel(part)
    }

    private func applyLevel(_ part: Part) {
        bus(part).outputVolume = (levels[part] ?? 1) * (ducks[part] ?? 1)
    }

    /// Called after the output device changed and the engine was restarted (if anything wanted sound).
    func onConfigurationChange(_ part: Part, _ handler: @escaping () -> Void) {
        configurationHandlers[part] = handler
    }

    var isRunning: Bool { engine.isRunning }

    /// Starts the engine for `part`. False when there is no usable output, so the part stays quiet.
    @discardableResult
    func start(for part: Part) -> Bool {
        wanting.insert(part)
        if engine.isRunning { return true }
        engine.prepare()
        do { try engine.start() } catch { return false }
        return true
    }

    /// `part` no longer needs sound. The engine pauses once no part does.
    func release(_ part: Part) {
        wanting.remove(part)
        if wanting.isEmpty, engine.isRunning { engine.pause() }
    }

    private func configurationChanged() {
        if !wanting.isEmpty, !engine.isRunning {
            engine.prepare()
            try? engine.start()
        }
        for part in Part.allCases { configurationHandlers[part]?() }
    }
}
