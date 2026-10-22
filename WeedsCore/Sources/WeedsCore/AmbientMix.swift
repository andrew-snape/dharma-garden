import Foundation

/// How loud each layer of the garden's ambient sound is, each 0...1: birdsong by day, crickets by night, and rain
/// that follows the weather. Pure, so the mapping is testable; `AmbientSynth` makes the sound.
public struct AmbientMix: Equatable, Sendable {
    public var birds: Double
    public var crickets: Double
    public var rain: Double

    public init(birds: Double = 0, crickets: Double = 0, rain: Double = 0) {
        self.birds = birds
        self.crickets = crickets
        self.rain = rain
    }

    public static let silent = AmbientMix()

    /// Birds sing most at dawn and by day, less at dusk and not at night, and keep quiet in rain and storms.
    /// Crickets need a warm evening or night (10 degrees or more) and dry-ish weather. Rain follows the condition.
    /// The urban theme is a little quieter on both. `temperatureC` nil counts as mild.
    public static func resolve(phase: SunPhase, condition: WeatherCondition, temperatureC: Double?,
                               theme: GardenTheme) -> AmbientMix {
        let birdPhase: Double = switch phase { case .dawn: 1; case .day: 0.9; case .dusk: 0.4; case .night: 0 }
        let birdWeather: Double = switch condition {
        case .clear: 1
        case .partlyCloudy: 0.9
        case .overcast: 0.6
        case .fog: 0.5
        case .drizzle: 0.25
        case .rain: 0.1
        case .thunderstorm, .snow: 0
        }
        let cricketPhase: Double = switch phase { case .night: 1; case .dusk: 0.6; case .dawn: 0.2; case .day: 0 }
        let cricketWeather: Double = switch condition {
        case .clear, .partlyCloudy, .overcast: 1
        case .fog: 0.7
        case .drizzle: 0.4
        case .rain: 0.15
        case .thunderstorm, .snow: 0
        }
        let warm = (temperatureC ?? 18) >= 10 ? 1.0 : 0.0
        let rain: Double = switch condition {
        case .drizzle: 0.3
        case .rain: 0.7
        case .thunderstorm: 1
        default: 0
        }
        let theme = theme == .urban ? 0.6 : 1.0
        return AmbientMix(birds: birdPhase * birdWeather * theme,
                          crickets: cricketPhase * cricketWeather * warm * theme,
                          rain: rain)
    }
}
