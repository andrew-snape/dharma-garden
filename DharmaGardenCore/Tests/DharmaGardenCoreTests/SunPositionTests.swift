import XCTest
@testable import DharmaGardenCore

/// Sun model: elevation, azimuth, intensity and warmth from sunrise/sunset and latitude.
final class SunPositionTests: XCTestCase {
    let geelong = -38.2167
    let dec = 355   // 21 December
    let jun = 172   // 21 June
    let melbourne = (lat: -37.81, lon: 144.96)

    /// A UTC instant.
    func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    /// Reference position from the NOAA spreadsheet equations (Julian day, mean and true longitude, equation of time),
    /// written out again here so the test does not lean on the code under test. Returns (elevation, azimuth).
    func reference(_ date: Date, lat: Double, lon: Double) -> (el: Double, az: Double) {
        let r = Double.pi / 180
        let jd = date.timeIntervalSince1970 / 86400 + 2440587.5
        let t = (jd - 2451545) / 36525
        let l0 = (280.46646 + t * (36000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        let m = 357.52911 + t * (35999.05029 - 0.0001537 * t)
        let ecc = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let c = sin(m * r) * (1.914602 - t * (0.004817 + 0.000014 * t)) + sin(2 * m * r) * (0.019993 - 0.000101 * t)
            + sin(3 * m * r) * 0.000289
        let app = l0 + c - 0.00569 - 0.00478 * sin((125.04 - 1934.136 * t) * r)
        let eps = 23.4392911 - 0.0130042 * t + 0.00256 * cos((125.04 - 1934.136 * t) * r)
        let decl = asin(sin(eps * r) * sin(app * r))
        let y = pow(tan(eps * r / 2), 2)
        let eot = 4 / r * (y * sin(2 * l0 * r) - 2 * ecc * sin(m * r) + 4 * ecc * y * sin(m * r) * cos(2 * l0 * r)
                           - 0.5 * y * y * sin(4 * l0 * r) - 1.25 * ecc * ecc * sin(2 * m * r))
        let minutes = (date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86400)) / 60
        let ha = ((minutes + eot + 4 * lon) / 4 - 180) * r
        let cosZ = sin(lat * r) * sin(decl) + cos(lat * r) * cos(decl) * cos(ha)
        let el = 90 - acos(cosZ) / r
        // Azimuth from the sun vector instead of the NOAA acos form, as an independent check.
        let east = -sin(ha) * cos(decl)
        let north = cos(lat * r) * sin(decl) - sin(lat * r) * cos(decl) * cos(ha)
        let az = (atan2(east, north) / r + 360).truncatingRemainder(dividingBy: 360)
        return (el, az)
    }

    /// Smallest angle between two compass bearings, in degrees.
    func bearingGap(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    func pos(_ date: Date, lat: Double? = nil, lon: Double? = nil) -> (elevation: Double, azimuth: Double, hourAngle: Double) {
        SunPosition.position(at: date, latitude: lat ?? melbourne.lat, longitude: lon ?? melbourne.lon)
    }

    /// 2026-12-21 at 13:20 AEDT (02:20 UTC): solar noon in Melbourne, sun 75.6 degrees up, due north.
    func testMelbourneSolsticeSolarNoon() {
        let p = pos(utc(2026, 12, 21, 2, 20))
        XCTAssertEqual(p.elevation, 75.6, accuracy: 1)
        XCTAssertEqual(p.hourAngle, 0, accuracy: 1)
        // True noon is about 02:18 UTC (equation of time +1.9 min); the sun is near the zenith, so the azimuth swings
        // quickly and is only checked to the minute.
        XCTAssertLessThan(bearingGap(pos(utc(2026, 12, 21, 2, 18)).azimuth, 0), 1)
    }

    /// Southern spring and summer mornings: the sun is in the east-south-east at low height, not due east.
    func testMelbourneSummerMorningRisesSouthOfEast() {
        let date = utc(2026, 12, 20, 20, 0)      // 07:00 AEDT on 21 December
        let p = pos(date)
        let ref = reference(date, lat: melbourne.lat, lon: melbourne.lon)
        XCTAssertEqual(p.elevation, ref.el, accuracy: 1)
        XCTAssertLessThan(bearingGap(p.azimuth, ref.az), 1)
        XCTAssertEqual(p.elevation, 11, accuracy: 2)
        XCTAssertEqual(p.azimuth, 90, accuracy: 25, "east-south-east to east-north-east, never far off east")
    }

    func testSunriseIsSouthOfEastInSouthernSummer() {
        // Sunrise at Melbourne on 21 December is about 06:00 AEDT: elevation near 0, azimuth about 118.
        let p = pos(utc(2026, 12, 20, 19, 0))
        XCTAssertEqual(p.elevation, -0.8, accuracy: 1.2)
        XCTAssertEqual(p.azimuth, 118, accuracy: 5, "south of east, not due east")
    }

    func testMelbourneJuneNoonAndMorning() {
        // Solar noon on 21 June: 12:00 mean solar at 144.96 E is 02:20 UTC less the equation of time (about -1.5 min).
        let noon = utc(2026, 6, 21, 2, 22)
        let p = pos(noon)
        XCTAssertEqual(p.elevation, 90 - 37.81 - 23.44, accuracy: 1)
        XCTAssertLessThan(bearingGap(p.azimuth, 0), 1)
        let morning = utc(2026, 6, 20, 22, 0)    // 08:00 AEST
        let q = pos(morning)
        let ref = reference(morning, lat: melbourne.lat, lon: melbourne.lon)
        XCTAssertEqual(q.elevation, ref.el, accuracy: 1)
        XCTAssertLessThan(bearingGap(q.azimuth, ref.az), 1)
        XCTAssertEqual(q.azimuth, 57, accuracy: 4, "winter morning sun is north-east")
    }

    func testMatchesReferenceAcrossTheYearAndBothHemispheres() {
        let places: [(Double, Double)] = [(-38.24, 144.33), (51.5, -0.12), (-33.87, 151.2), (40.7, -74.0)]
        for (lat, lon) in places {
            for (mo, d, h) in [(1, 15, 3), (3, 20, 9), (6, 21, 5), (9, 22, 22), (10, 28, 14), (12, 21, 11)] {
                let date = utc(2026, mo, d, h, 17)
                let p = pos(date, lat: lat, lon: lon)
                let ref = reference(date, lat: lat, lon: lon)
                XCTAssertEqual(p.elevation, ref.el, accuracy: 0.5, "\(lat),\(lon) \(mo)/\(d) \(h)h")
                if ref.el > 0 { XCTAssertLessThan(bearingGap(p.azimuth, ref.az), 1, "\(lat),\(lon) \(mo)/\(d) \(h)h") }
            }
        }
    }

    func testEquationOfTimeInLateOctober() {
        XCTAssertEqual(SunPosition.equationOfTime(at: utc(2026, 10, 28, 2, 0)), 16.2, accuracy: 0.6)
        XCTAssertEqual(SunPosition.equationOfTime(at: utc(2026, 2, 11, 2, 0)), -14.2, accuracy: 0.6)
    }

    func testSolarHourFollowsLongitudeNotTheClock() {
        // Mount Duneed, 28 October, 10:00 AEDT (23:00 UTC the day before): solar time about 8:55.
        let sun = SunPosition.light(at: utc(2026, 10, 27, 23, 0), sunrise: utc(2026, 10, 27, 19, 0),
                                    sunset: utc(2026, 10, 28, 9, 0), latitude: -38.24, longitude: 144.33)
        XCTAssertEqual(sun.solarHour!, 8.93, accuracy: 0.1)
        // Without a longitude it is worked out from sunrise and sunset, and lands close.
        let implied = SunPosition.light(at: utc(2026, 10, 27, 23, 0), sunrise: utc(2026, 10, 27, 19, 3),
                                        sunset: utc(2026, 10, 28, 8, 51), latitude: -38.24)
        XCTAssertEqual(implied.solarHour!, sun.solarHour!, accuracy: 0.3)
    }

    func testNoonElevationHigherInSummerThanWinter() {
        let summerNoon = SunPosition.noonElevation(latitude: geelong, dayOfYear: dec)
        let winterNoon = SunPosition.noonElevation(latitude: geelong, dayOfYear: jun)
        XCTAssertGreaterThan(summerNoon, winterNoon + 30, "December noon sun is much higher than June's")
        XCTAssertEqual(summerNoon, 75, accuracy: 1)
        XCTAssertEqual(winterNoon, 28, accuracy: 1)
    }

    func testDeclinationAtSolstices() {
        XCTAssertEqual(SunPosition.declination(dayOfYear: jun), 23.44, accuracy: 0.1)
        XCTAssertEqual(SunPosition.declination(dayOfYear: dec), -23.44, accuracy: 0.1)
    }








    func testPositiveLatitudeNoonElevationUsesSameFormula() {
        XCTAssertEqual(SunPosition.noonElevation(latitude: 51.5, dayOfYear: jun), 90 - (51.5 - 23.44), accuracy: 0.1)
    }

    // MARK: Light

    func light(_ date: Date, cloud: Double = 0) -> SunLight {
        SunPosition.light(at: date, sunrise: utc(2026, 12, 20, 18, 45), sunset: utc(2026, 12, 21, 9, 0),
                          latitude: melbourne.lat, longitude: melbourne.lon, cloudCover: cloud)
    }

    func testNightIsBelowHorizonWithNoLight() {
        let night = light(utc(2026, 12, 21, 13, 0))
        XCTAssertLessThan(night.elevationDegrees, 0)
        XCTAssertGreaterThanOrEqual(night.elevationDegrees, -18)
        XCTAssertEqual(night.intensity, 0)
        XCTAssertFalse(night.isUp)
    }

    func testIntensityCloudAndWarmth() {
        let noon = light(utc(2026, 12, 21, 2, 20))
        let low = light(utc(2026, 12, 21, 8, 30))         // 19:30 AEDT, sun low in the west
        XCTAssertGreaterThan(noon.intensity, 0.9)
        XCTAssertLessThan(low.intensity, noon.intensity)
        XCTAssertEqual(noon.warmth, 0, accuracy: 1e-9)
        XCTAssertGreaterThan(low.warmth, 0.5)
        let overcast = light(utc(2026, 12, 21, 2, 20), cloud: 100)
        XCTAssertGreaterThan(overcast.intensity, 0)
        XCTAssertLessThan(overcast.intensity, noon.intensity)
        XCTAssertEqual(overcast.elevationDegrees, noon.elevationDegrees, accuracy: 1e-9, "cloud does not move the sun")
    }

}
