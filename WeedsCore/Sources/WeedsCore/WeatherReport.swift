import Foundation

public enum WeatherCondition: String, Codable, Sendable {
    case clear, partlyCloudy, overcast, fog, drizzle, rain, thunderstorm, snow

    /// WMO weather interpretation codes as used by Open-Meteo.
    public init(wmoCode: Int) {
        switch wmoCode {
        case 0, 1: self = .clear
        case 2: self = .partlyCloudy
        case 3: self = .overcast
        case 45, 48: self = .fog
        case 51...57: self = .drizzle
        case 61...67, 80...82: self = .rain
        case 71...77, 85, 86: self = .snow
        case 95...99: self = .thunderstorm
        default: self = .partlyCloudy
        }
    }

    public var label: String {
        switch self {
        case .clear: "Clear"
        case .partlyCloudy: "Partly cloudy"
        case .overcast: "Overcast"
        case .fog: "Fog"
        case .drizzle: "Drizzle"
        case .rain: "Rain"
        case .thunderstorm: "Thunderstorm"
        case .snow: "Snow"
        }
    }
}

public struct CurrentConditions: Codable, Equatable, Sendable {
    public var temperatureC: Double
    public var apparentTemperatureC: Double
    public var precipitationMM: Double
    public var windKmh: Double
    public var cloudCover: Double
    public var isDay: Bool
    public var condition: WeatherCondition
}

public struct WeatherReport: Codable, Equatable, Sendable {
    public var current: CurrentConditions
    public var hourly: [WeatherSample]
    public var sunrise: Date
    public var sunset: Date
    public var fetchedAt: Date
    public var latitude: Double
    public var longitude: Double

    /// How old the reading is; the UI labels stale data with this.
    public func age(at now: Date) -> TimeInterval { now.timeIntervalSince(fetchedAt) }

    /// Sunrise and sunset for the day `now` falls in. The report holds one day's pair; when it is from an earlier
    /// (or later) day, the pair is moved by whole days, which is close enough because day length changes slowly.
    /// The day starts at the 45 minute dawn window, as in `OpenMeteoClient.parse`.
    public func sunTimes(at now: Date) -> (sunrise: Date, sunset: Date) {
        let day: TimeInterval = 24 * 3600
        let days = (now.addingTimeInterval(45 * 60).timeIntervalSince(sunrise) / day).rounded(.down)
        guard days != 0 else { return (sunrise, sunset) }
        return (sunrise.addingTimeInterval(days * day), sunset.addingTimeInterval(days * day))
    }
}

public enum SunPhase: String, Sendable { case night, dawn, day, dusk }

public enum SunPhaseResolver {
    /// Dawn/dusk are the 45 minutes either side of true sunrise/sunset.
    public static func phase(at now: Date, sunrise: Date, sunset: Date, twilight: TimeInterval = 45 * 60) -> SunPhase {
        if now >= sunrise.addingTimeInterval(-twilight) && now < sunrise.addingTimeInterval(twilight) { return .dawn }
        if now >= sunset.addingTimeInterval(-twilight) && now < sunset.addingTimeInterval(twilight) { return .dusk }
        return (now >= sunrise && now < sunset) ? .day : .night
    }
}
