import XCTest
@testable import DharmaGardenCore

/// Sun model: elevation, azimuth, intensity and warmth from sunrise/sunset and latitude.
final class SunPositionTests: XCTestCase {
    let geelong = -38.2167
    let dec = 355   // 21 December
    let jun = 172   // 21 June
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    /// A 14-hour day starting at `base`.
    var sunrise: Date { base }
    var sunset: Date { base.addingTimeInterval(14 * 3600) }

    /// Sun at a fraction of the day (0 = sunrise, 1 = sunset).
    func sun(_ f: Double, lat: Double = -38.2167, day: Int = 355, cloud: Double = 0) -> SunLight {
        SunPosition.light(at: sunrise.addingTimeInterval(f * 14 * 3600), sunrise: sunrise, sunset: sunset,
                          latitude: lat, cloudCover: cloud, dayOfYear: day)
    }

    /// Smallest angle between two compass bearings, in degrees.
    func bearingGap(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    func testNoonElevationHigherInSummerThanWinter() {
        let summerNoon = SunPosition.noonElevation(latitude: geelong, dayOfYear: dec)
        let winterNoon = SunPosition.noonElevation(latitude: geelong, dayOfYear: jun)
        XCTAssertGreaterThan(summerNoon, winterNoon + 30, "December noon sun is much higher than June's")
        XCTAssertEqual(summerNoon, 75, accuracy: 1)
        XCTAssertEqual(winterNoon, 28, accuracy: 1)

        XCTAssertGreaterThan(sun(0.5, day: dec).elevationDegrees, sun(0.5, day: jun).elevationDegrees)
    }

    func testDeclinationAtSolstices() {
        XCTAssertEqual(SunPosition.declination(dayOfYear: jun), 23.44, accuracy: 0.1)
        XCTAssertEqual(SunPosition.declination(dayOfYear: dec), -23.44, accuracy: 0.1)
    }

    func testSunriseAzimuthNearEastAndSunsetNearWest() {
        XCTAssertLessThan(bearingGap(sun(0).azimuthDegrees, 90), 2, "sunrise is due east")
        XCTAssertLessThan(bearingGap(sun(1).azimuthDegrees, 270), 2, "sunset is due west")
        XCTAssertEqual(sun(0).elevationDegrees, 0, accuracy: 0.001, "sun is on the horizon at sunrise")
        XCTAssertEqual(sun(1).elevationDegrees, 0, accuracy: 0.001, "sun is on the horizon at sunset")
    }

    func testAzimuthPassesThroughNorthAtNoonSouthernHemisphere() {
        XCTAssertLessThan(bearingGap(sun(0.5).azimuthDegrees, 0), 0.5, "noon is due north in Geelong")
        // Morning is in the north-east quadrant, afternoon in the north-west, both through north.
        XCTAssertLessThan(bearingGap(sun(0.25).azimuthDegrees, 45), 1)
        XCTAssertLessThan(bearingGap(sun(0.75).azimuthDegrees, 315), 1)
    }

    func testNightIsBelowHorizonWithNoLight() {
        let night = SunPosition.light(at: sunset.addingTimeInterval(2 * 3600), sunrise: sunrise, sunset: sunset,
                                      latitude: geelong, dayOfYear: dec)
        XCTAssertLessThan(night.elevationDegrees, 0)
        XCTAssertEqual(night.intensity, 0)
        XCTAssertFalse(night.isUp)

        let beforeDawn = SunPosition.light(at: sunrise.addingTimeInterval(-1 * 3600), sunrise: sunrise, sunset: sunset,
                                           latitude: geelong, dayOfYear: dec)
        XCTAssertLessThan(beforeDawn.elevationDegrees, 0)
        XCTAssertEqual(beforeDawn.intensity, 0)
    }

    func testIntensityRisesWithElevation() {
        XCTAssertLessThan(sun(0.1).intensity, sun(0.5).intensity)
        XCTAssertGreaterThan(sun(0.5, day: dec).intensity, 0.8)
    }

    func testCloudCoverReducesIntensity() {
        let clear = sun(0.5, cloud: 0).intensity
        let partly = sun(0.5, cloud: 50).intensity
        let overcast = sun(0.5, cloud: 100).intensity
        XCTAssertGreaterThan(clear, partly)
        XCTAssertGreaterThan(partly, overcast)
        XCTAssertGreaterThan(overcast, 0, "overcast is dim, not dark")
        XCTAssertEqual(sun(0.5, cloud: 0).elevationDegrees, sun(0.5, cloud: 100).elevationDegrees, accuracy: 1e-9,
                       "cloud dims the light but does not move the sun")
    }

    func testWarmthHigherAtLowSun() {
        let golden = sun(0.93)   // about an hour before sunset
        let noon = sun(0.5)
        XCTAssertGreaterThan(golden.warmth, noon.warmth)
        XCTAssertEqual(noon.warmth, 0, accuracy: 1e-9, "midday has no golden tint")
        XCTAssertGreaterThan(golden.warmth, 0.5)
        XCTAssertLessThanOrEqual(golden.warmth, 1)
        XCTAssertLessThanOrEqual(sun(0.05).warmth, 1)
        XCTAssertGreaterThanOrEqual(sun(0.05).warmth, 0)
    }

    func testNorthernHemisphereFlipsAzimuth() {
        // London-ish, June: noon sun is due south, sunrise east, sunset west.
        XCTAssertLessThan(bearingGap(sun(0.5, lat: 51.5, day: jun).azimuthDegrees, 180), 0.5)
        XCTAssertLessThan(bearingGap(sun(0, lat: 51.5, day: jun).azimuthDegrees, 90), 2)
        XCTAssertLessThan(bearingGap(sun(1, lat: 51.5, day: jun).azimuthDegrees, 270), 2)
        // Mid-morning is south-east, not north-east.
        XCTAssertLessThan(bearingGap(sun(0.25, lat: 51.5, day: jun).azimuthDegrees, 135), 1)
    }

    func testPositiveLatitudeNoonElevationUsesSameFormula() {
        XCTAssertEqual(SunPosition.noonElevation(latitude: 51.5, dayOfYear: jun), 90 - (51.5 - 23.44), accuracy: 0.1)
    }
}
