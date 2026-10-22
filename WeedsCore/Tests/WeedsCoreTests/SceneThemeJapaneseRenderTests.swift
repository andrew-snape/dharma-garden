import XCTest
import SwiftUI
import WeedsCore
@testable import WeedsArt

/// Extra Japanese-theme sheets for judging by eye: the seasons (petals in spring, maple leaves in autumn) and rain.
/// JAPANESE_RENDER_DIR gets backyard and first-person PNGs per season; nothing is written when it is unset.
@MainActor
final class SceneThemeJapaneseRenderTests: XCTestCase {
    func testRenderSeasonSheets() throws {
        guard let dir = ProcessInfo.processInfo.environment["JAPANESE_RENDER_DIR"] else { return }
        let base = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let sun = SunLight(elevationDegrees: 38, azimuthDegrees: 200, intensity: 0.9, warmth: 0.1)
        let garden = SceneThemeRenderTests.garden(.soilPatch)
        let cases: [(String, Season, WeatherCondition)] = [
            ("spring", .spring, .clear), ("autumn", .autumn, .clear), ("winter", .winter, .clear), ("summer-rain", .summer, .rain),
        ]
        for (name, season, condition) in cases {
            let palette = ScenePalette.resolve(season: season, phase: .day, condition: condition, temperatureC: 18, cloudCover: 30, sun: sun)
            for scene in SceneStyle.allCases {
                let data = try SceneThemeRenderTests.pngData(
                    SceneThemeRenderTests.content(garden: garden, palette: palette, scene: scene, theme: .japanese))
                try data.write(to: base.appendingPathComponent("\(name)-\(scene.rawValue).png"))
            }
        }
    }
}
