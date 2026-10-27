import XCTest
import SwiftUI
import DharmaGardenCore
@testable import DharmaGardenArt

/// RENDER_OUT=<dir> writes PNGs for judging by eye.
@MainActor
final class SceneSundialTests: XCTestCase {
    func testRender() throws {
        guard let dir = ProcessInfo.processInfo.environment["RENDER_OUT"] else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for theme in SceneTheme.allCases {
            for light in SceneThemeRenderTests.lights {
                let view = SceneThemeRenderTests.content(garden: SceneThemeRenderTests.garden(.soilPatch), palette: light.palette,
                                                         scene: .backyard, theme: theme)
                try SceneThemeRenderTests.pngData(view).write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(theme.rawValue)-\(light.name).png"))
            }
        }
    }

    func testRenderWaterAndCarried() throws {
        guard let dir = ProcessInfo.processInfo.environment["RENDER_OUT"] else { return }
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        for theme in SceneTheme.allCases {
            for bed in [BedStyle.soilPatch, .plantersBoxes] {
                let ripples = [SceneRipple(point: GroundPoint(x: 0.5, y: 0.88), startedAt: t0, kind: .water),
                               SceneRipple(point: GroundPoint(x: 0.25, y: 0.2), startedAt: t0.addingTimeInterval(0.2), kind: .aerate)]
                let view = SceneContent(garden: SceneThemeRenderTests.garden(bed), palette: SceneThemeRenderTests.lights[0].palette,
                                        camera: .backyard, ripples: ripples, now: t0.addingTimeInterval(0.8),
                                        motion: SceneThemeRenderTests.motion, style: .backyard, theme: theme,
                                        wateringCanCarried: theme == .urban ? CGPoint(x: 400, y: 450) : nil)
                    .frame(width: 960, height: 720)
                try SceneThemeRenderTests.pngData(view).write(to: URL(fileURLWithPath: dir).appendingPathComponent("water-\(theme.rawValue)-\(bed.rawValue).png"))
            }
        }
    }

    /// SHADOW_OUT=<dir> renders Mount Duneed on 2026-10-28 at 07:30, 10:00, 13:20, 16:00 and 19:00 AEDT, backyard and
    /// first person, for two themes, and prints the sun and the sundial reading for each.
    func testRenderShadowsThroughTheDay() throws {
        guard let dir = ProcessInfo.processInfo.environment["SHADOW_OUT"] else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Australia/Melbourne")!
        let lat = -38.24, lon = 144.33
        func local(_ h: Int, _ m: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: h, minute: m))! }
        let sunrise = local(6, 8), sunset = local(19, 52)
        for (h, m) in [(7, 30), (10, 0), (13, 20), (16, 0), (19, 0)] {
            let when = local(h, m)
            let sun = SunPosition.light(at: when, sunrise: sunrise, sunset: sunset, latitude: lat, longitude: lon)
            let phase = SunPhaseResolver.phase(at: when, sunrise: sunrise, sunset: sunset)
            let palette = ScenePalette.resolve(season: .spring, phase: phase, condition: .clear, temperatureC: 20, cloudCover: 5, sun: sun)
            let dirn = SceneLighting.shadowDirection(for: sun)
            print(String(format: "SHADOW %02d:%02d el %.1f az %.1f solar %@ shadowDir (%.2f, %.2f) length %.2f",
                         h, m, sun.elevationDegrees, sun.azimuthDegrees, SceneCanvas.sundialReading(for: sun),
                         dirn?.x ?? 0, dirn?.y ?? 0, SceneLighting.shadowLength(elevationDegrees: sun.elevationDegrees)))
            for theme in [SceneTheme.farm, .urban] {
                for style in SceneStyle.allCases {
                    let view = SceneThemeRenderTests.content(garden: SceneThemeRenderTests.garden(.soilPatch), palette: palette,
                                                             scene: style, theme: theme)
                    let name = String(format: "%@-%@-%02d%02d.png", theme.rawValue, style.rawValue, h, m)
                    try SceneThemeRenderTests.pngData(view).write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
                }
            }
        }
    }

    func testSundialReadingFollowsSun() {
        let real = SunLight(elevationDegrees: 40, azimuthDegrees: 30, intensity: 0.9, warmth: 0, hourAngleDegrees: -45, latitudeDegrees: -38)
        XCTAssertEqual(SceneCanvas.sundialSolarHour(for: real)!, 9, accuracy: 0.001)
        XCTAssertEqual(SceneCanvas.sundialReading(for: real), "Sundial: 9:00 am (solar time)")
        func sun(_ az: Double, _ el: Double = 40) -> SunLight { SunLight(elevationDegrees: el, azimuthDegrees: az, intensity: 0.9, warmth: 0) }
        XCTAssertEqual(SceneCanvas.sundialSolarHour(for: sun(90))!, 6, accuracy: 0.01)
        XCTAssertEqual(SceneCanvas.sundialSolarHour(for: sun(180))!, 12, accuracy: 0.01)
        XCTAssertEqual(SceneCanvas.sundialSolarHour(for: sun(270))!, 18, accuracy: 0.01)
        XCTAssertEqual(SceneCanvas.sundialSolarHour(for: sun(0))!, 12, accuracy: 0.01)      // southern hemisphere noon
        XCTAssertEqual(SceneCanvas.sundialSolarHour(for: sun(45))!, 9, accuracy: 0.01)
        XCTAssertNil(SceneCanvas.sundialSolarHour(for: sun(180, -5)))
        XCTAssertNil(SceneCanvas.sundialSolarHour(for: nil))
        XCTAssertEqual(SceneCanvas.sundialReading(for: sun(195)), "Sundial: 1:00 pm (solar time)")
    }

    /// The sundial's shadow edge must lie on the hour line for the true solar hour, in both hemispheres, on any date.
    func testGnomonShadowLiesOnTheHourLine() {
        func utc(_ y: Int, _ mo: Int, _ d: Int) -> Date {
            var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
            return c.date(from: DateComponents(year: y, month: mo, day: d, hour: 0))!
        }
        for (lat, lon) in [(-38.24, 144.33), (-37.81, 144.96), (51.5, -0.12), (40.7, -74.0)] {
            for day in [(2026, 3, 20), (2026, 6, 21), (2026, 10, 28), (2026, 12, 21)] {
                for hour in stride(from: 7.0, through: 17.0, by: 1.0) {
                    // The instant whose true solar time is `hour` at this longitude: noon UTC offset by longitude.
                    var date = utc(day.0, day.1, day.2).addingTimeInterval((hour * 60 - 4 * lon) * 60)
                    date = date.addingTimeInterval(-SunPosition.equationOfTime(at: date) * 60)
                    let sun = SunPosition.light(at: date, sunrise: date.addingTimeInterval(-6 * 3600),
                                                sunset: date.addingTimeInterval(6 * 3600), latitude: lat, longitude: lon)
                    guard sun.elevationDegrees > 8 else { continue }
                    XCTAssertEqual(SceneCanvas.sundialSolarHour(for: sun)!, hour, accuracy: 0.05)
                    let tip = SceneCanvas.sundialShadowTip(for: sun)
                    let shadowBearing = atan2(tip.east, tip.north) * 180 / .pi
                    let lineBearing = SceneCanvas.sundialHourBearing(hourAngle: 15 * (hour - 12), latitude: lat)
                    var gap = abs(shadowBearing - lineBearing).truncatingRemainder(dividingBy: 360)
                    gap = min(gap, 360 - gap)
                    XCTAssertLessThan(gap, 0.5, "lat \(lat) \(day) hour \(hour): shadow \(shadowBearing) line \(lineBearing)")
                }
            }
        }
    }

    func testHourLinesRunAnticlockwiseInTheSouthAndClockwiseInTheNorth() {
        XCTAssertEqual(SceneCanvas.sundialHourBearing(hourAngle: 0, latitude: -38), 180, accuracy: 1e-9)
        XCTAssertEqual(SceneCanvas.sundialHourBearing(hourAngle: -90, latitude: -38), 270, accuracy: 1e-9)
        XCTAssertEqual(SceneCanvas.sundialHourBearing(hourAngle: 90, latitude: -38), 90, accuracy: 1e-9)
        XCTAssertEqual(SceneCanvas.sundialHourBearing(hourAngle: 0, latitude: 51).truncatingRemainder(dividingBy: 360), 0, accuracy: 1e-9)
        XCTAssertEqual(SceneCanvas.sundialHourBearing(hourAngle: -90, latitude: 51), 270, accuracy: 1e-9)
    }

    func testSundialIsOnOpenLawn() {
        let plot = Garden(now: Date()).plot
        XCTAssertFalse(plot.contains(GroundPoint(x: 0.5 + SceneCanvas.sundialX / 6, y: 0.5 + SceneCanvas.sundialZ / 6)))
        let rect = SceneContent.sundialRect(size: CGSize(width: 960, height: 720), camera: .backyard)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 960, height: 720).contains(rect))
        XCTAssertFalse(rect.intersects(SceneContent.chairRect(size: CGSize(width: 960, height: 720), camera: .backyard)))
    }

    func testWateringCanRectIsOnScreenInEveryTheme() {
        let size = CGSize(width: 960, height: 720)
        for theme in SceneTheme.allCases {
            let rect = GardenSceneView.wateringCanRect(size: size, theme: theme, driftEnabled: false)
            XCTAssertTrue(CGRect(origin: .zero, size: size).contains(rect), "\(theme) \(rect)")
        }
    }
}
