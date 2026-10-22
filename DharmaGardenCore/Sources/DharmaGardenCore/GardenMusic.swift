import Foundation

/// The inputs that shape the garden's music: time of day, weather and season.
public struct GardenMood: Equatable, Sendable {
    public var phase: SunPhase
    public var condition: WeatherCondition
    public var season: Season
    /// The garden theme the player chose: it picks the instruments and the scales (see `MusicScale`).
    public var theme: GardenTheme

    public init(phase: SunPhase, condition: WeatherCondition, season: Season, theme: GardenTheme = .farm) {
        self.phase = phase
        self.condition = condition
        self.season = season
        self.theme = theme
    }

    /// A plain mild day, used while no weather report is known.
    public static func plainDay(season: Season, theme: GardenTheme = .farm) -> GardenMood {
        GardenMood(phase: .day, condition: .clear, season: season, theme: theme)
    }
}

/// The sound sources of the garden's music. Japanese: koto, flute, drone. Farm: pluck (fingerpicked guitar) and bass.
/// Rural UK: piano and pad. Urban: epiano, pad and a soft bass pulse.
public enum MusicVoice: String, Sendable, Equatable {
    case koto, flute, drone
    case pluck, bass, piano, epiano, pad
}

/// One note: `time` is seconds from the start of the music, `midiNote` a MIDI note number.
public struct NoteEvent: Equatable, Sendable {
    public var time: Double
    public var midiNote: Int
    public var duration: Double
    /// 0...1
    public var velocity: Double
    public var voice: MusicVoice

    public init(time: Double, midiNote: Int, duration: Double, velocity: Double, voice: MusicVoice) {
        self.time = time
        self.midiNote = midiNote
        self.duration = duration
        self.velocity = velocity
        self.voice = voice
    }
}

/// The scales of the garden's music as MIDI pitch classes (note number mod 12). Every theme's scale contains its
/// tonic and fifth, which the phrases end on.
public enum MusicScale {
    /// The Japanese (and default) tonic D and fifth A.
    public static let tonic = 2
    public static let fifth = 9

    /// Japanese: Yo (D E G A B) in spring and summer, Hirajoshi (D E F A B-flat) in autumn and winter.
    public static func pitchClasses(for season: Season) -> [Int] {
        pitchClasses(for: season, theme: .japanese)
    }

    /// The scale for a theme and season:
    /// - Japanese: yo / hirajoshi on D.
    /// - Farm: D major pentatonic (D E F# A B) in spring and summer, D dorian without its seventh
    ///   (D E F G A B) in autumn and winter.
    /// - Rural UK: D dorian (spring, summer) or D aeolian (autumn, winter).
    /// - Urban: C major 6/9 with a major seventh (C D E G A B) or a C minor 11 set (C D E-flat F G B-flat).
    public static func pitchClasses(for season: Season, theme: GardenTheme) -> [Int] {
        let warm = season == .spring || season == .summer
        switch theme {
        case .japanese: return warm ? [2, 4, 7, 9, 11] : [2, 4, 5, 9, 10]
        case .farm: return warm ? [2, 4, 6, 9, 11] : [2, 4, 5, 7, 9, 11]
        case .ruralUK: return warm ? [0, 2, 4, 5, 7, 9, 11] : [0, 2, 4, 5, 7, 9, 10]
        case .urban: return warm ? [0, 2, 4, 7, 9, 11] : [0, 2, 3, 5, 7, 10]
        }
    }

    /// The tonic and the fifth of a theme (pitch classes): phrases end on one of them.
    public static func cadence(for theme: GardenTheme) -> [Int] {
        theme == .urban ? [0, 7] : [2, 9]
    }

    /// Every MIDI note in `range` whose pitch class is in the scale, ascending.
    static func pool(pitchClasses: [Int], range: ClosedRange<Int>) -> [Int] {
        range.filter { pitchClasses.contains((($0 % 12) + 12) % 12) }
    }

    static func isCadence(_ midi: Int, in cadence: [Int] = [tonic, fifth]) -> Bool {
        cadence.contains((midi % 12 + 12) % 12)
    }
}
