import Foundation

/// How much of the recorded music the player wants. Garden notes are separate (their own toggle).
public enum MusicDensity: String, CaseIterable, Sendable, Codable {
    case off, subtle, often

    /// The silence after a piece, in seconds. Subtle leaves long stretches of just ambience.
    public var gap: ClosedRange<Double>? {
        switch self {
        case .off: nil
        case .subtle: 6 * 60...12 * 60
        case .often: 1 * 60...3 * 60
        }
    }
}

/// One recorded piece in the library.
public struct PieceInfo: Equatable, Sendable {
    public var id: String
    public var mood: PieceMood
    public var duration: TimeInterval

    public init(id: String, mood: PieceMood, duration: TimeInterval) {
        self.id = id
        self.mood = mood
        self.duration = duration
    }
}

public enum MusicDirectorState: Equatable, Sendable {
    case silent(until: Date)
    case playing(PieceInfo, endsAt: Date)
}

/// What the player should do after a tick.
public enum MusicDirectorAction: Equatable, Sendable {
    case none
    case start(PieceInfo)
    /// Fade out and stop whatever is playing (the music was switched off).
    case stop
}

/// Decides when the next piece plays. The music is mostly silence: a long wait after launch, a piece, then a
/// long gap again. Pure, with an injected clock and seeded randomness, so it is easy to test.
public struct MusicDirector: Sendable {
    /// The first piece waits this long after the director is made (or after music is switched on).
    public static let firstDelay: ClosedRange<Double> = 45...90
    /// How many of the latest pieces cannot be picked again.
    public static let noRepeat = 3
    /// No piece starts from `quietFrom` o'clock until `quietUntil` o'clock (local time).
    public static let quietFrom = 22
    public static let quietUntil = 6
    /// How long to wait before looking again when nothing could be picked.
    static let retry: TimeInterval = 60

    public private(set) var state: MusicDirectorState
    /// Ids of the pieces played, oldest first.
    public private(set) var history: [String]
    public var catalogue: [PieceInfo]
    private var rng: SplitMix
    private var calendar: Calendar

    public init(catalogue: [PieceInfo], now: Date, seed: UInt64 = UInt64.random(in: 1...UInt64.max),
                calendar: Calendar = .current, history: [String] = []) {
        self.catalogue = catalogue
        self.calendar = calendar
        self.history = history
        self.rng = SplitMix(seed: seed)
        self.state = .silent(until: now)
        state = .silent(until: now.addingTimeInterval(draw(Self.firstDelay)))
    }

    private mutating func draw(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + rng.unit() * (range.upperBound - range.lowerBound)
    }

    /// True when a piece may not start at `date`.
    public func isQuietHour(_ date: Date) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= Self.quietFrom || hour < Self.quietUntil
    }

    /// Moves the state forward to `now`. Call about once a second.
    public mutating func tick(now: Date, mood: PieceMood, density: MusicDensity) -> MusicDirectorAction {
        guard density != .off else {
            // Nothing plays. Turning music back on starts the wait again, like a fresh launch.
            let wasPlaying: Bool
            if case .playing = state { wasPlaying = true } else { wasPlaying = false }
            state = .silent(until: now.addingTimeInterval(draw(Self.firstDelay)))
            return wasPlaying ? .stop : .none
        }
        switch state {
        case .playing(_, let endsAt):
            if now >= endsAt { state = .silent(until: endsAt.addingTimeInterval(gap(density))) }
            return .none
        case .silent(let until):
            guard now >= until else { return .none }
            // Not at night: keep waiting, so the first piece of the morning follows at 06:00.
            if isQuietHour(now) { return .none }
            guard let piece = pick(for: mood) else {
                state = .silent(until: now.addingTimeInterval(Self.retry))
                return .none
            }
            begin(piece, now: now)
            return .start(piece)
        }
    }

    /// Debug: starts a piece now whatever the clock says. Nil when no piece can be picked.
    public mutating func playNow(now: Date, mood: PieceMood) -> PieceInfo? {
        guard let piece = pick(for: mood) else { return nil }
        begin(piece, now: now)
        return piece
    }

    /// Ends the current piece (the player fades it) and waits a full gap before the next. Used for a theme
    /// change, for the debug drawer, and when the music is switched off.
    public mutating func goSilent(now: Date, density: MusicDensity) {
        state = .silent(until: now.addingTimeInterval(gap(density)))
    }

    private mutating func begin(_ piece: PieceInfo, now: Date) {
        state = .playing(piece, endsAt: now.addingTimeInterval(piece.duration))
        history.append(piece.id)
        if history.count > 16 { history.removeFirst(history.count - 16) }
    }

    private mutating func gap(_ density: MusicDensity) -> Double {
        draw(density.gap ?? Self.firstDelay)
    }

    /// A piece for `mood` that is not among the last few played. If the mood has none left it tries the
    /// neighbouring moods in order. A random choice among the candidates.
    mutating func pick(for mood: PieceMood) -> PieceInfo? {
        let recent = Set(history.suffix(Self.noRepeat))
        for candidateMood in mood.fallbackOrder {
            let candidates = catalogue.filter { $0.mood == candidateMood && !recent.contains($0.id) }
            if !candidates.isEmpty {
                return candidates[Int(rng.unit() * Double(candidates.count)) % candidates.count]
            }
        }
        return nil
    }
}

extension PieceMood {
    /// This mood first, then the ones that sit next to it: the day goes dawn, day, dusk, night round the clock,
    /// and rain is closest to the low, slow dusk and night.
    var fallbackOrder: [PieceMood] {
        switch self {
        case .dawn: [.dawn, .day, .night, .dusk]
        case .day: [.day, .dawn, .dusk, .night]
        case .dusk: [.dusk, .night, .day, .dawn]
        case .night: [.night, .dusk, .dawn, .day]
        case .rain: [.rain, .dusk, .night, .day]
        }
    }
}
