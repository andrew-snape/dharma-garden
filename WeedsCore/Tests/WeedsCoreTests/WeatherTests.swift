import XCTest
@testable import WeedsCore

final class WeatherTests: XCTestCase {
    let json = """
    {"current":{"temperature_2m":31.5,"apparent_temperature":33,"precipitation":0,"weather_code":2,"cloud_cover":40,"wind_speed_10m":12,"is_day":1},
     "hourly":{"time":[1700000000,1700003600],"temperature_2m":[20,null],"precipitation":[0.2,0],"wind_speed_10m":[5,6],"cloud_cover":[10,20],"is_day":[1,0]},
     "daily":{"time":[1699920000,1700006400],"sunrise":[1699900000,1699986400],"sunset":[1699950000,1700036400]}}
    """.data(using: .utf8)!

    func testParseCurrentHourlyAndSun() throws {
        let now = Date(timeIntervalSince1970: 1_699_990_000)
        let r = try OpenMeteoClient.parse(json, latitude: -38.2, longitude: 144.3, fetchedAt: now)
        XCTAssertEqual(r.current.temperatureC, 31.5)
        XCTAssertEqual(r.current.condition, .partlyCloudy)
        XCTAssertTrue(r.current.isDay)
        XCTAssertEqual(r.hourly.count, 1, "null temperature hours are dropped")
        XCTAssertEqual(r.sunrise.timeIntervalSince1970, 1_699_986_400)
    }

    func testEveningPicksTodaysSunTimesNotTomorrows() throws {
        // Fetched at 19:22, 13h after today's sunrise and 11h before tomorrow's: must pick today's.
        let today = 1_700_000_000.0
        let rises = [today - 86400, today, today + 86400]
        let sets = rises.map { $0 + 13 * 3600 }
        let sunJSON = """
        {"current":{"temperature_2m":20,"apparent_temperature":20,"precipitation":0,"weather_code":0,"cloud_cover":0,"wind_speed_10m":5,"is_day":0},
         "hourly":{"time":[\(today)],"temperature_2m":[20],"precipitation":[0],"wind_speed_10m":[5],"cloud_cover":[0],"is_day":[0]},
         "daily":{"time":[0,0,0],"sunrise":\(rises),"sunset":\(sets)}}
        """.data(using: .utf8)!
        let now = Date(timeIntervalSince1970: today + 13 * 3600 + 22 * 60)
        let r = try OpenMeteoClient.parse(sunJSON, latitude: -38.2, longitude: 144.3, fetchedAt: now)
        XCTAssertEqual(r.sunrise.timeIntervalSince1970, today)
        let phase = SunPhaseResolver.phase(at: now, sunrise: r.sunrise, sunset: r.sunset)
        XCTAssertNotEqual(phase, .day)
        XCTAssertEqual(phase, .dusk)
    }

    func testSunTimesMoveToTheDayNowFallsIn() throws {
        let r = try OpenMeteoClient.parse(json, latitude: -38.2, longitude: 144.3,
                                          fetchedAt: Date(timeIntervalSince1970: 1_699_990_000))
        let day = 86_400.0
        // Same day: unchanged.
        let same = r.sunTimes(at: r.sunrise.addingTimeInterval(3600))
        XCTAssertEqual(same.sunrise, r.sunrise)
        XCTAssertEqual(same.sunset, r.sunset)
        // Two days later at noon (a cached report while offline): moved by two days, so it is day, not night.
        let later = r.sunrise.addingTimeInterval(2 * day + 5 * 3600)
        let moved = r.sunTimes(at: later)
        XCTAssertEqual(moved.sunrise, r.sunrise.addingTimeInterval(2 * day))
        XCTAssertEqual(moved.sunset, r.sunset.addingTimeInterval(2 * day))
        XCTAssertEqual(SunPhaseResolver.phase(at: later, sunrise: moved.sunrise, sunset: moved.sunset), .day)
        // Just before the next dawn window: still the stored day, so it is night.
        let lateNight = r.sunrise.addingTimeInterval(day - 50 * 60)
        XCTAssertEqual(r.sunTimes(at: lateNight).sunrise, r.sunrise)
        // Inside the next dawn window: the next day's sunrise, so it is dawn.
        let dawn = r.sunrise.addingTimeInterval(day - 30 * 60)
        let next = r.sunTimes(at: dawn)
        XCTAssertEqual(next.sunrise, r.sunrise.addingTimeInterval(day))
        XCTAssertEqual(SunPhaseResolver.phase(at: dawn, sunrise: next.sunrise, sunset: next.sunset), .dawn)
    }

    func testWMOMapping() {
        XCTAssertEqual(WeatherCondition(wmoCode: 0), .clear)
        XCTAssertEqual(WeatherCondition(wmoCode: 61), .rain)
        XCTAssertEqual(WeatherCondition(wmoCode: 95), .thunderstorm)
        XCTAssertEqual(WeatherCondition(wmoCode: 45), .fog)
    }

    func testSunPhases() {
        let rise = Date(timeIntervalSince1970: 100_000), set = rise.addingTimeInterval(12 * 3600)
        XCTAssertEqual(SunPhaseResolver.phase(at: rise.addingTimeInterval(-3600), sunrise: rise, sunset: set), .night)
        XCTAssertEqual(SunPhaseResolver.phase(at: rise, sunrise: rise, sunset: set), .dawn)
        XCTAssertEqual(SunPhaseResolver.phase(at: rise.addingTimeInterval(6 * 3600), sunrise: rise, sunset: set), .day)
        XCTAssertEqual(SunPhaseResolver.phase(at: set, sunrise: rise, sunset: set), .dusk)
    }

    func testRequestURLAsksForUnixtimeAndAutoTimezone() {
        let u = OpenMeteoClient.url(latitude: -38.2, longitude: 144.3).absoluteString
        XCTAssertTrue(u.contains("timeformat=unixtime") && u.contains("timezone=auto") && u.contains("current="))
    }

    func testPaletteEverySeasonPhaseConditionResolves() {
        for s in [Season.summer, .autumn, .winter, .spring] {
            for p in [SunPhase.night, .dawn, .day, .dusk] {
                for c in [WeatherCondition.clear, .overcast, .rain, .thunderstorm, .fog, .snow] {
                    let pal = ScenePalette.resolve(season: s, phase: p, condition: c, temperatureC: 15, cloudCover: 50)
                    XCTAssertTrue((0...0.8).contains(pal.darkness))
                }
            }
        }
    }

    func testPaletteBehaviour() {
        let sunny = ScenePalette.resolve(season: .summer, phase: .day, condition: .clear, temperatureC: 22, cloudCover: 0)
        let night = ScenePalette.resolve(season: .summer, phase: .night, condition: .clear, temperatureC: 22, cloudCover: 0)
        let rainy = ScenePalette.resolve(season: .summer, phase: .day, condition: .rain, temperatureC: 22, cloudCover: 90)
        let hot = ScenePalette.resolve(season: .summer, phase: .day, condition: .clear, temperatureC: 38, cloudCover: 0)
        XCTAssertGreaterThan(night.darkness, sunny.darkness)
        XCTAssertGreaterThan(rainy.rainStrength, 0)
        XCTAssertNotEqual(rainy.skyTop, sunny.skyTop)
        XCTAssertGreaterThan(hot.overlayStrength, sunny.overlayStrength)
        let autumn = ScenePalette.resolve(season: .autumn, phase: .day, condition: .clear, temperatureC: 22, cloudCover: 0)
        XCTAssertNotEqual(autumn.foliage, sunny.foliage)
    }
}
