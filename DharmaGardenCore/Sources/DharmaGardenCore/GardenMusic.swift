import Foundation

/// The inputs that shape the garden's music: time of day, weather and season.
public struct GardenMood: Equatable, Sendable {
    public var phase: SunPhase
    public var condition: WeatherCondition
    public var season: Season
    /// The garden theme the player chose. Every theme plays the handpan library for now.
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

extension PieceMood {
    /// The piece mood for the garden's mood: rain and thunderstorms get the rain pieces whatever the hour
    /// (drizzle is too light to change the music), otherwise the time of day decides.
    public init(_ mood: GardenMood) {
        switch mood.condition {
        case .rain, .thunderstorm:
            self = .rain
        default:
            switch mood.phase {
            case .dawn: self = .dawn
            case .day: self = .day
            case .dusk: self = .dusk
            case .night: self = .night
            }
        }
    }
}
