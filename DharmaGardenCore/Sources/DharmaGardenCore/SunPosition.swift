import Foundation

/// The sun as seen from the garden right now. Pure values, no UI types.
public struct SunLight: Equatable, Sendable {
    /// Height of the sun above the horizon in degrees. Negative after sunset and before sunrise.
    public var elevationDegrees: Double
    /// Compass bearing of the sun: 0 = north, 90 = east, 180 = south, 270 = west.
    public var azimuthDegrees: Double
    /// Strength of the direct light, 0...1. Rises with elevation, reduced by cloud. Zero at night.
    public var intensity: Double
    /// Golden-hour colour, 0...1. Highest near the horizon, zero at midday and at night.
    public var warmth: Double

    public init(elevationDegrees: Double, azimuthDegrees: Double, intensity: Double, warmth: Double) {
        self.elevationDegrees = elevationDegrees
        self.azimuthDegrees = azimuthDegrees
        self.intensity = intensity
        self.warmth = warmth
    }

    /// True while the sun is above the horizon.
    public var isUp: Bool { elevationDegrees > 0 }
}

/// Sun position from the day's true sunrise and sunset (Open-Meteo) and the latitude.
///
/// Day fraction f runs 0 at sunrise to 1 at sunset. Elevation is sin(pi f) times the noon elevation.
/// Azimuth sweeps from east at sunrise, through north at noon in the southern hemisphere (south in the
/// northern), to west at sunset. The model is deliberately simple: it is for lighting, not navigation.
public enum SunPosition {
    /// Solar declination in degrees for a day of the year (1...366).
    public static func declination(dayOfYear: Int) -> Double {
        23.44 * sin(2 * Double.pi * Double(dayOfYear - 81) / 365)
    }

    /// Sun elevation at solar noon in degrees.
    public static func noonElevation(latitude: Double, dayOfYear: Int) -> Double {
        90 - abs(latitude - declination(dayOfYear: dayOfYear))
    }

    /// Day of the year for a date, in the current calendar.
    public static func dayOfYear(of date: Date) -> Int {
        Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
    }

    /// The sun at `now`.
    /// - Parameters:
    ///   - sunrise: the day's true sunrise instant.
    ///   - sunset: the day's true sunset instant.
    ///   - latitude: degrees, negative in the southern hemisphere.
    ///   - cloudCover: 0...100 percent. Heavy cloud dims the direct light.
    ///   - dayOfYear: defaults to the day of `now`.
    public static func light(at now: Date, sunrise: Date, sunset: Date, latitude: Double,
                             cloudCover: Double = 0, dayOfYear: Int? = nil) -> SunLight {
        let day = dayOfYear ?? Self.dayOfYear(of: now)
        let length = sunset.timeIntervalSince(sunrise)
        guard length > 0 else {
            // No proper day (polar or bad data): treat as night.
            return SunLight(elevationDegrees: -18, azimuthDegrees: 0, intensity: 0, warmth: 0)
        }
        let f = now.timeIntervalSince(sunrise) / length
        let noon = noonElevation(latitude: latitude, dayOfYear: day)

        let elevation: Double
        if f >= 0 && f <= 1 {
            elevation = sin(Double.pi * f) * noon
        } else {
            // Night: sinks away from the horizon at 60 degrees per day-length, capped at 18.
            let outside = f < 0 ? -f : f - 1
            elevation = -min(18, 60 * outside)
        }

        let clampedF = min(1, max(0, f))
        let azimuth: Double
        if latitude < 0 {
            azimuth = 90 - 180 * clampedF          // east, north at noon, west
        } else {
            azimuth = 90 + 180 * clampedF          // east, south at noon, west
        }
        let bearing = (azimuth.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)

        return SunLight(elevationDegrees: elevation, azimuthDegrees: bearing,
                        intensity: intensity(elevation: elevation, cloudCover: cloudCover),
                        warmth: warmth(elevation: elevation))
    }

    /// Direct light: square root of sin(elevation) so low sun still reads, cut by cloud (up to 70%).
    static func intensity(elevation: Double, cloudCover: Double) -> Double {
        guard elevation > 0 else { return 0 }
        let base = sqrt(sin(elevation * Double.pi / 180))
        let cloud = min(1, max(0, cloudCover / 100))
        return min(1, max(0, base * (1 - 0.7 * cloud)))
    }

    /// Golden hour: 1 at the horizon, fading to 0 by 35 degrees, and 0 again well below the horizon.
    static func warmth(elevation: Double) -> Double {
        let high = 1 - min(1, max(0, elevation / 35))
        let low = min(1, max(0, (elevation + 8) / 8))
        return high * low
    }
}
