import XCTest
import WeedsCore
@testable import WeedsArt

@MainActor
final class SceneThemeTests: XCTestCase {
    func testRawValuesAndCases() {
        XCTAssertEqual(SceneTheme.allCases.map(\.rawValue), ["farm", "japanese", "ruralUK", "urban"])
        XCTAssertEqual(GardenTheme.allCases.map(\.rawValue), SceneTheme.allCases.map(\.rawValue))
    }

    func testRoundTripBetweenSceneAndGardenTheme() {
        for theme in SceneTheme.allCases {
            XCTAssertEqual(SceneTheme(theme.gardenTheme), theme)
            XCTAssertEqual(theme.gardenTheme.rawValue, theme.rawValue)
        }
        for theme in GardenTheme.allCases {
            XCTAssertEqual(SceneTheme(theme).gardenTheme, theme)
        }
    }

    func testGardenThemeCodableUsesTheRawValue() throws {
        let data = try JSONEncoder().encode(GardenTheme.ruralUK)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"ruralUK\"")
        XCTAssertEqual(try JSONDecoder().decode(GardenTheme.self, from: data), .ruralUK)
    }

    func testDisplayNamesAndBlurbs() {
        XCTAssertEqual(SceneTheme.allCases.map(\.displayName),
                       ["Farm", "Japanese garden", "Rural UK garden", "Urban backyard"])
        for theme in SceneTheme.allCases {
            XCTAssertFalse(theme.blurb.isEmpty)
            XCTAssertFalse(theme.blurb.contains("\n"))
        }
    }

    func testFarmIsTheDefaultEverywhere() {
        let mood = GardenMood(phase: .day, condition: .clear, season: .spring)
        XCTAssertEqual(mood.theme, .farm)
        XCTAssertEqual(GardenMood.plainDay(season: .autumn).theme, .farm)
        XCTAssertEqual(GardenSceneView(garden: Garden(now: Date()), palette: ScenePalette.resolve(
            season: .summer, phase: .day, condition: .clear, temperatureC: 20, cloudCover: 0)).theme, .farm)
    }

    /// No theme tints the palette yet, so every theme resolves to the farm's.
    func testPaletteIsTheSameForEveryThemeForNow() {
        let farm = ScenePalette.resolve(season: .winter, phase: .dusk, condition: .rain, temperatureC: 5, cloudCover: 80)
        for theme in GardenTheme.allCases {
            XCTAssertEqual(ScenePalette.resolve(season: .winter, phase: .dusk, condition: .rain, temperatureC: 5,
                                                cloudCover: 80, theme: theme), farm)
        }
    }
}
