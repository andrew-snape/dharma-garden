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
    /// Hour angle in degrees: 0 at local apparent solar noon, negative in the morning, 15 per hour. Nil for a
    /// hand-made sun, in which case the sundial falls back to the bearing.
    public var hourAngleDegrees: Double?
    /// Latitude the sun was worked out for, in degrees (negative in the south). Nil for a hand-made sun.
    public var latitudeDegrees: Double?

    public init(elevationDegrees: Double, azimuthDegrees: Double, intensity: Double, warmth: Double,
                hourAngleDegrees: Double? = nil, latitudeDegrees: Double? = nil) {
        self.elevationDegrees = elevationDegrees
        self.azimuthDegrees = azimuthDegrees
        self.intensity = intensity
        self.warmth = warmth
        self.hourAngleDegrees = hourAngleDegrees
        self.latitudeDegrees = latitudeDegrees
    }

    /// Local apparent solar time in hours (0..<24), from the hour angle, or nil without one.
    public var solarHour: Double? {
        hourAngleDegrees.map { ((12 + $0 / 15).truncatingRemainder(dividingBy: 24) + 24).truncatingRemainder(dividingBy: 24) }
    }

    /// True while the sun is above the horizon.
    public var isUp: Bool { elevationDegrees > 0 }
}

/// Sun position by the NOAA solar position equations (Meeus): declination and equation of time from the date, the
/// hour angle from the longitude, then true elevation and azimuth. Accurate to well under a degree, which is far
/// finer than the lighting needs, and it puts the sun where the shadows and the sundial need it: it rises south of
/// east in a southern summer, and local noon follows the longitude and the equation of time, not the clock.
public enum SunPosition {
    /// Declination, equation of time (minutes) and Julian century for an instant.
    struct Ephemeris { var declination: Double; var equationOfTime: Double; var century: Double }

    static func ephemeris(at date: Date) -> Ephemeris {
        let jd = date.timeIntervalSince1970 / 86400 + 2440587.5
        let t = (jd - 2451545.0) / 36525.0
        func rad(_ d: Double) -> Double { d * Double.pi / 180 }
        let l0 = (280.46646 + t * (36000.76983 + 0.0003032 * t)).truncatingRemainder(dividingBy: 360)
        let m = 357.52911 + t * (35999.05029 - 0.0001537 * t)
        let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let c = sin(rad(m)) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(rad(2 * m)) * (0.019993 - 0.000101 * t) + sin(rad(3 * m)) * 0.000289
        let omega = 125.04 - 1934.136 * t
        let lambda = l0 + c - 0.00569 - 0.00478 * sin(rad(omega))
        let eps0 = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let eps = eps0 + 0.00256 * cos(rad(omega))
        let decl = asin(sin(rad(eps)) * sin(rad(lambda))) * 180 / Double.pi
        let y = pow(tan(rad(eps) / 2), 2)
        let eot = 4 * 180 / Double.pi * (y * sin(2 * rad(l0)) - 2 * e * sin(rad(m))
            + 4 * e * y * sin(rad(m)) * cos(2 * rad(l0)) - 0.5 * y * y * sin(4 * rad(l0))
            - 1.25 * e * e * sin(2 * rad(m)))
        return Ephemeris(declination: decl, equationOfTime: eot, century: t)
    }

    /// Solar declination in degrees at an instant.
    public static func declination(at date: Date) -> Double { ephemeris(at: date).declination }

    /// Equation of time in minutes at an instant: apparent solar time minus mean solar time.
    public static func equationOfTime(at date: Date) -> Double { ephemeris(at: date).equationOfTime }

    /// Solar declination in degrees for a day of the year (1...366), a mid-year approximation for rough use.
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

    /// Hour angle in degrees at an instant for a longitude (east positive): 0 at local apparent noon, 15 per hour.
    public static func hourAngle(at date: Date, longitude: Double) -> Double {
        let utcMinutes = (date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86400) + 86400)
            .truncatingRemainder(dividingBy: 86400) / 60
        let solarMinutes = utcMinutes + ephemeris(at: date).equationOfTime + 4 * longitude
        let h = (solarMinutes / 4 - 180).truncatingRemainder(dividingBy: 360)
        return h < -180 ? h + 360 : (h > 180 ? h - 360 : h)
    }

    /// True (geometric) elevation and compass azimuth in degrees, plus the hour angle, at an instant and place.
    public static func position(at date: Date, latitude: Double, longitude: Double)
        -> (elevation: Double, azimuth: Double, hourAngle: Double) {
        let decl = declination(at: date)
        let ha = hourAngle(at: date, longitude: longitude)
        let lat = latitude * Double.pi / 180, d = decl * Double.pi / 180, h = ha * Double.pi / 180
        let cosZ = min(1, max(-1, sin(lat) * sin(d) + cos(lat) * cos(d) * cos(h)))
        let zenith = acos(cosZ)
        let elevation = 90 - zenith * 180 / Double.pi
        var azimuth = 0.0
        let denom = cos(lat) * sin(zenith)
        if abs(denom) > 1e-9 {
            let a = acos(min(1, max(-1, (sin(lat) * cosZ - sin(d)) / denom))) * 180 / Double.pi
            azimuth = ha > 0 ? (a + 180).truncatingRemainder(dividingBy: 360)
                             : (540 - a).truncatingRemainder(dividingBy: 360)
        } else {
            azimuth = latitude < 0 ? 0 : 180
        }
        return (elevation, azimuth, ha)
    }

    /// The sun at `now`.
    /// - Parameters:
    ///   - sunrise: the day's true sunrise instant. With `sunset` it only gives the longitude when none is
    ///     passed (local noon is their midpoint) and rules out polar or bad data.
    ///   - sunset: the day's true sunset instant.
    ///   - latitude: degrees, negative in the southern hemisphere.
    ///   - longitude: degrees, east positive. Estimated from the midpoint of sunrise and sunset when nil.
    ///   - cloudCover: 0...100 percent. Heavy cloud dims the direct light.
    ///   - dayOfYear: no longer used; the date comes from `now`. Kept so older callers still compile.
    public static func light(at now: Date, sunrise: Date, sunset: Date, latitude: Double, longitude: Double? = nil,
                             cloudCover: Double = 0, dayOfYear: Int? = nil) -> SunLight {
        guard sunset.timeIntervalSince(sunrise) > 0 else {
            // No proper day (polar or bad data): treat as night.
            return SunLight(elevationDegrees: -18, azimuthDegrees: 0, intensity: 0, warmth: 0)
        }
        let lon = longitude ?? impliedLongitude(sunrise: sunrise, sunset: sunset)
        let p = position(at: now, latitude: latitude, longitude: lon)
        // Below the horizon the sun is not drawn; keep the elevation within a sensible band for the tints.
        let elevation = max(-18, p.elevation)
        return SunLight(elevationDegrees: elevation, azimuthDegrees: p.azimuth,
                        intensity: intensity(elevation: elevation, cloudCover: cloudCover),
                        warmth: warmth(elevation: elevation),
                        hourAngleDegrees: p.hourAngle, latitudeDegrees: latitude)
    }

    /// Longitude (east positive) at which the midpoint of sunrise and sunset is local apparent noon.
    static func impliedLongitude(sunrise: Date, sunset: Date) -> Double {
        let noon = Date(timeIntervalSince1970: (sunrise.timeIntervalSince1970 + sunset.timeIntervalSince1970) / 2)
        let utcMinutes = (noon.timeIntervalSince1970.truncatingRemainder(dividingBy: 86400) + 86400)
            .truncatingRemainder(dividingBy: 86400) / 60
        var lon = (720 - utcMinutes - ephemeris(at: noon).equationOfTime) / 4
        while lon > 180 { lon -= 360 }
        while lon < -180 { lon += 360 }
        return lon
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
