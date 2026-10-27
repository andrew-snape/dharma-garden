import AVFoundation
import Foundation
import DharmaGardenCore

/// The garden's music: long, quiet handpan pieces separated by long silences, and single notes when things
/// happen in the garden.
///
/// The pieces are recorded files made in-house by `GardenRender` (see the Sounds folder); `MusicDirector`
/// decides when one plays. A piece is played through an `AVAudioPlayerNode` on the shared engine's music bus,
/// fading in over 4 s and out over the last 8 s on top of the files' own fades. A piece in progress is never cut
/// short by a change of mood, only by switching the music off, muting, or changing the garden theme (3 s fade).
/// Garden notes are played by `GardenNotesPlayer`, whether or not a piece is playing.
///
/// Every garden theme uses the handpan library for now; Farm, Rural UK and Urban get their own instruments and
/// pieces later (the file names already carry the theme: `japanese-<mood>-<n>`).
///
/// Ambience is lowered by about 3 dB while a piece plays, so the two do not compete.
@MainActor
final class GardenMusic: ObservableObject {
    /// The fade at the start of a piece, on top of the file's own.
    static let fadeInSeconds = 4.0
    /// The fade at the end of a piece (it begins this long before the end).
    static let fadeOutSeconds = 8.0
    /// A theme change, switching the music off, or skipping.
    static let quickFadeSeconds = 3.0
    /// How much the ambience is lowered while a piece plays, and how quickly it goes down and comes back.
    static let duckGain = Float(pow(10.0, -3.0 / 20.0))
    static let duckDownSeconds = 2.0
    static let duckUpSeconds = 5.0
    /// How long the engine is kept running after the last piece or note, so a following note does not wait for it.
    private static let engineLinger = 15.0

    private let audio = GardenAudio.shared
    private var engine: AVAudioEngine { audio.engine }
    private let notesPlayer = GardenNotesPlayer()

    private var mood = GardenMood.plainDay(season: .spring)
    private var density = MusicDensity.subtle
    private var gardenNotesOn = true
    private var notes = GardenNotes()

    /// The user wants sound (set by start and stop: stop is the mute).
    private var wantsSound = false
    /// The app is in the foreground (set by pause and resume).
    private var appActive = true

    private var director: MusicDirector?
    /// Ids played so far, kept across stops so a mute does not make the last pieces eligible again.
    private var history: [String] = []
    private var catalogue: [PieceInfo]?
    private var clock: Task<Void, Never>?
    private var releaseTask: Task<Void, Never>?

    // The piece player. Built on the first piece.
    private var piecePlayer: AVAudioPlayerNode?
    private var pieceMixer: AVAudioMixerNode?
    private var pieceFade: LevelRamp?
    private var duck: LevelRamp?
    private var pieceInfo: PieceInfo?
    /// When frame 0 of the playing piece was (or would have been) played, so a restart can pick up where it was.
    private var pieceBegan = Date.distantPast
    private var pieceEndFadeStarted = false
    /// Invalidates the completion callbacks of pieces that were stopped.
    private var pieceToken = 0

    private var pieceActive: Bool { pieceInfo != nil }

    init() {
        // Output device changes (headphones plugged in, AirPods connecting) stop the engine.
        audio.onConfigurationChange(.music) { [weak self] in self?.engineConfigurationChanged() }
        duck = LevelRamp(initial: 1) { [audio] in audio.setDuck($0, for: .ambient) }
    }

    // MARK: Controls

    /// Lets the music and notes sound (the first tap in the garden, or the end of a mute). Safe to repeat.
    func start() {
        guard !wantsSound else { return }
        wantsSound = true
        guard appActive else { return }
        beginClock()
    }

    /// Fades the music out and goes silent until `start` is called again (the mute).
    func stop() {
        wantsSound = false
        clock?.cancel()
        clock = nil
        if let director { history = director.history }
        director = nil
        fadePieceOut(over: Self.quickFadeSeconds)
    }

    /// Called when the app resigns active, if the music should not play in the background.
    func pause() {
        appActive = false
        clock?.cancel()
        clock = nil
        fadePieceOut(over: Self.quickFadeSeconds)
        director?.goSilent(now: Date(), density: density)
    }

    /// Called when the app becomes active again.
    func resume() {
        appActive = true
        if wantsSound { beginClock() }
    }

    /// Master volume, 0...1: the music bus, which the pieces and the notes share.
    func setVolume(_ value: Double) {
        audio.setVolume(value, for: .music)
    }

    /// The mood the next piece is picked for. A piece already playing finishes; a different garden theme fades
    /// it out over 3 s and leaves the garden silent for a gap.
    func setMood(_ newMood: GardenMood) {
        let themeChanged = newMood.theme != mood.theme
        mood = newMood
        if themeChanged, pieceActive {
            director?.goSilent(now: Date(), density: density)
            fadePieceOut(over: Self.quickFadeSeconds)
        }
    }

    /// Off, Subtle or Often. Off fades a playing piece out over 3 s.
    func setDensity(_ newDensity: MusicDensity) {
        density = newDensity
        if wantsSound, appActive { tick() }
    }

    /// Whether garden events sound a note.
    func setGardenNotes(_ on: Bool) {
        gardenNotesOn = on
    }

    // MARK: Garden notes

    /// Something happened in the garden at screen position `x` (0 left, 1 right). Plays a note or two if the
    /// rate limit allows. It does not depend on the sound-effects setting or on a piece playing.
    func gardenEvent(_ event: GardenNoteEvent, x: Double = 0.5) {
        guard wantsSound, appActive, gardenNotesOn else { return }
        // Notes follow their own toggle: with the music Off they still sound, at the Subtle rate.
        let rate: MusicDensity = density == .off ? .subtle : density
        let planned = notes.notes(for: event, at: Date(), x: x, density: rate, night: mood.phase == .night)
        guard !planned.isEmpty, holdEngine() else { return }
        for note in planned { sound(note) }
        releaseEngineSoon()
    }

    private func sound(_ note: GardenNote) {
        if note.delay <= 0 {
            notesPlayer.play(index: note.scaleIndex, velocity: note.velocity, pan: note.pan)
        } else {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(note.delay))
                guard let self, self.wantsSound else { return }
                self.notesPlayer.play(index: note.scaleIndex, velocity: note.velocity, pan: note.pan)
            }
        }
    }

    // MARK: The clock and the director

    private func beginClock() {
        if director == nil {
            director = MusicDirector(catalogue: loadCatalogue(), now: Date(), history: history)
        }
        guard clock == nil else { return }
        clock = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func tick() {
        guard wantsSound, appActive, director != nil else { return }
        let now = Date()
        let action = director?.tick(now: now, mood: PieceMood(mood), density: density) ?? .none
        switch action {
        case .none:
            break
        case .start(let piece):
            play(piece, from: 0)
        case .stop:
            fadePieceOut(over: Self.quickFadeSeconds)
        }
        // The last 8 s of a piece fade out on top of the file's own fade.
        if let info = pieceInfo, !pieceEndFadeStarted,
           now.timeIntervalSince(pieceBegan) >= info.duration - Self.fadeOutSeconds {
            pieceEndFadeStarted = true
            pieceFade?.ramp(to: 0, over: Self.fadeOutSeconds)
        }
    }

    /// The pieces in the bundle, with their lengths. A missing file is simply not in the library.
    private func loadCatalogue() -> [PieceInfo] {
        if let catalogue { return catalogue }
        var found: [PieceInfo] = []
        for pieceMood in PieceMood.allCases {
            for number in 1...8 {
                let id = Self.pieceID(pieceMood, number)
                guard let url = Self.resourceURL(id, folder: "Music"),
                      let file = try? AVAudioFile(forReading: url), file.length > 0 else { continue }
                found.append(PieceInfo(id: id, mood: pieceMood, duration: Double(file.length) / file.processingFormat.sampleRate))
            }
        }
        catalogue = found
        return found
    }

    private static func pieceID(_ mood: PieceMood, _ number: Int) -> String {
        "japanese-\(mood.rawValue)-\(number)"
    }

    /// A bundled .m4a by name. Xcode flattens the Music folders into Resources, but a folder reference would keep
    /// them, so both places are tried.
    nonisolated static func resourceURL(_ name: String, folder: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "m4a")
            ?? Bundle.main.url(forResource: name, withExtension: "m4a", subdirectory: folder)
    }

    // MARK: Playing a piece

    /// Starts `piece` from `offset` seconds in. A fresh start fades in over 4 s; picking up after the output
    /// changed (offset > 0) fades in over half a second.
    private func play(_ piece: PieceInfo, from offset: Double) {
        guard let url = Self.resourceURL(piece.id, folder: "Music"), let file = try? AVAudioFile(forReading: url),
              buildPieceGraph(format: file.processingFormat), holdEngine(),
              let player = piecePlayer, let fade = pieceFade else {
            // Nothing could be played: wait a gap rather than trying again every second.
            director?.goSilent(now: Date(), density: density)
            return
        }
        player.stop()
        pieceToken += 1
        let rate = file.processingFormat.sampleRate
        let startFrame = min(file.length, AVAudioFramePosition(offset * rate))
        let frames = AVAudioFrameCount(max(0, file.length - startFrame))
        guard frames > 0 else { return }
        pieceInfo = piece
        pieceBegan = Date().addingTimeInterval(-offset)
        pieceEndFadeStarted = false
        Self.schedule(player, file: file, startFrame: startFrame, frames: frames,
                      done: Self.completion(for: self, token: pieceToken))
        fade.jump(to: 0)
        player.play()
        let into = offset > 0 ? 0.5 : Self.fadeInSeconds
        fade.ramp(to: 1, over: into)
        duck?.ramp(to: Self.duckGain, over: Self.duckDownSeconds)
    }

    /// Fades the piece down and stops it, then lets the ambience come back. A no-op if nothing is playing.
    private func fadePieceOut(over seconds: Double) {
        guard pieceActive, let fade = pieceFade else { return }
        let token = pieceToken
        duck?.ramp(to: 1, over: Self.duckUpSeconds)
        pieceEndFadeStarted = true
        fade.ramp(to: 0, over: seconds) { [weak self] in
            guard let self, self.pieceToken == token else { return }
            self.finishPiece()
        }
    }

    /// The piece has ended or been faded out.
    private func finishPiece() {
        piecePlayer?.stop()
        pieceToken += 1
        pieceInfo = nil
        duck?.ramp(to: 1, over: Self.duckUpSeconds)
        releaseEngineSoon()
    }

    fileprivate func pieceFinished(token: Int) {
        guard token == pieceToken, pieceActive else { return }
        finishPiece()
    }

    /// The scheduling calls are made here, not in the main-actor methods above: the completion handler runs on the
    /// audio thread, and a closure made in a main-actor method would trap there.
    private nonisolated static func schedule(_ player: AVAudioPlayerNode, file: AVAudioFile, startFrame: AVAudioFramePosition,
                                             frames: AVAudioFrameCount,
                                             done: @escaping @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void) {
        player.scheduleSegment(file, startingFrame: startFrame, frameCount: frames, at: nil,
                               completionCallbackType: .dataPlayedBack, completionHandler: done)
    }

    private nonisolated static func completion(for music: GardenMusic, token: Int)
        -> @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void {
        return { [weak music] _ in
            Task { @MainActor in music?.pieceFinished(token: token) }
        }
    }

    /// Player and fader for the pieces, connected to the music bus in the files' format (48 kHz stereo).
    private func buildPieceGraph(format: AVAudioFormat) -> Bool {
        if piecePlayer != nil { return true }
        let player = AVAudioPlayerNode()
        let mixer = AVAudioMixerNode()
        engine.attach(player)
        engine.attach(mixer)
        engine.connect(player, to: mixer, format: format)
        engine.connect(mixer, to: audio.bus(.music), format: format)
        piecePlayer = player
        pieceMixer = mixer
        pieceFade = LevelRamp(initial: 0) { mixer.outputVolume = $0 }
        return true
    }

    // MARK: The shared engine

    /// Starts the engine for the music part if needed. False when there is no usable output.
    private func holdEngine() -> Bool {
        releaseTask?.cancel()
        releaseTask = nil
        return audio.start(for: .music)
    }

    /// Lets the engine pause a while after the last piece or note, unless a piece is playing.
    private func releaseEngineSoon() {
        releaseTask?.cancel()
        releaseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.engineLinger))
            guard !Task.isCancelled, let self, !self.pieceActive else { return }
            self.audio.release(.music)
        }
    }

    /// The output changed and the engine stopped itself (GardenAudio has started it again). A piece that was
    /// playing is picked up from where it should be by now.
    private func engineConfigurationChanged() {
        guard let info = pieceInfo, wantsSound, appActive else { return }
        let elapsed = Date().timeIntervalSince(pieceBegan)
        guard elapsed < info.duration - 1 else { finishPiece(); return }
        play(info, from: elapsed)
    }

    // MARK: Debug

    /// What the director is doing, for the debug drawer.
    func statusLine(at now: Date = Date()) -> String {
        func time(_ date: Date) -> String {
            let left = Int(date.timeIntervalSince(now).rounded())
            return "\(date.formatted(date: .omitted, time: .standard)) (\(left < 0 ? "now" : "in \(left / 60) min \(left % 60) s"))"
        }
        guard wantsSound, let director else { return "Music stopped (muted or not started yet)" }
        let state: String
        switch director.state {
        case .silent(let until): state = "silent until \(time(until))"
        case .playing(let piece, let endsAt): state = "playing \(piece.id) until \(time(endsAt))"
        }
        let rate = density == .off ? "off" : density.rawValue
        return "\(state) · \(rate)\(director.isQuietHour(now) ? " · quiet hours" : "") · \(catalogue?.count ?? 0) pieces"
    }

#if DEBUG
    /// Debug: plays a piece for the current mood now, whatever the director and the clock say.
    func debugPlayPieceNow() {
        if !wantsSound { start() }
        guard let piece = director?.playNow(now: Date(), mood: PieceMood(mood)) else { return }
        if pieceActive { finishPiece() }
        play(piece, from: 0)
    }

    /// Debug: fades the piece out and waits a full gap.
    func debugSkipToSilence() {
        director?.goSilent(now: Date(), density: density == .off ? .subtle : density)
        fadePieceOut(over: Self.quickFadeSeconds)
    }

    /// Debug: plays the nine notes in order, soft then medium, a second and a half apart, ignoring the rate limit.
    func debugPlayEachNote() {
        guard holdEngine() else { return }
        var delay = 0.0
        for velocity in [0.25, 0.5] {
            for index in 0..<GardenNotes.scaleCount {
                let when = delay
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(when))
                    self?.notesPlayer.play(index: index, velocity: velocity, pan: 0)
                }
                delay += 1.5
            }
        }
        // The run lasts longer than the engine lingers, so only let it go once the last note has started.
        let runLength = delay
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(runLength))
            self?.releaseEngineSoon()
        }
    }
#endif
}
