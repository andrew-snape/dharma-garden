import XCTest
import SwiftUI
@testable import DharmaGardenCore
@testable import DharmaGardenArt

/// Renders the free-form garden scene to PNG so it can be judged by eye. Each test writes only to its env path.
@MainActor
final class SceneRenderTests: XCTestCase {
    /// The sample garden for judging the scene: 25 plants of every type at varied progress (fresh bloom, fading,
    /// seed heads, buds, wilting, one dead), 8 weeds of several ages, and uneven moisture: a dry patch on the
    /// left and a freshly watered patch on the right.
    static func sampleGarden() -> Garden {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        var g = DebugTools.fillWithPlants(garden: Garden(now: t), count: 25)

        // Uneven moisture first: watering refreshes each plant's moisture snapshot.
        GardenEngine.water(at: GroundPoint(x: 0.2, y: 0.74), in: &g, radius: 0.2, amount: -90)
        GardenEngine.water(at: GroundPoint(x: 0.8, y: 0.7), in: &g, radius: 0.2, amount: 70)

        let bloom = Tuning.bloomDays * 24
        for i in g.plants.indices {
            var p = g.plants[i]
            switch i {
            case 3: p.progress = 0.6; p.isDead = true                                  // dead
            case 0, 6, 11, 19: p.progress = 1; p.bloomHoursElapsed = 48                // fresh bloom
            case 2, 9, 17: p.progress = 1; p.bloomHoursElapsed = bloom + 4 * 24        // fading
            case 5, 13, 21: p.progress = 1; p.bloomHoursElapsed = bloom + 8 * 24       // seed head
            case 8, 15: p.progress = 0.72                                              // bud
            case 12, 23: p.progress = 0.5; p.dryHours = Tuning.wiltAfterDryHours + 10  // wilting
            default: p.progress = 0.05 + 0.85 * Double(i % 7) / 6                      // growing
            }
            g.plants[i] = p
        }

        g.weeds = (0..<8).map { k in
            Weed(id: 900 + k, position: g.plot.point(seed: 0x5EED &+ UInt64(k) &* 97, inset: 0.05),
                 ageHours: 12 + 36 * k)
        }
        g.nextID = 1000
        return g
    }

    /// Sunny summer day, sun high in the north-west.
    static let dayPalette = ScenePalette.resolve(season: .summer, phase: .day, condition: .clear, temperatureC: 26,
                                                 cloudCover: 10,
                                                 sun: SunLight(elevationDegrees: 38, azimuthDegrees: 200,
                                                               intensity: 0.9, warmth: 0.1))
    /// Summer dusk: low warm sun from the west, long shadows.
    static let duskPalette = ScenePalette.resolve(season: .summer, phase: .dusk, condition: .clear, temperatureC: 17,
                                                  cloudCover: 5,
                                                  sun: SunLight(elevationDegrees: 3, azimuthDegrees: 275,
                                                                intensity: 0.15, warmth: 0.8))

    private func pngData<V: View>(_ view: V) throws -> Data {
        let r = ImageRenderer(content: view)
        r.scale = 1
        let img = try XCTUnwrap(r.nsImage)
        let tiff = try XCTUnwrap(img.tiffRepresentation)
        return try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }

    private func writePNG(_ data: Data, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    private func scene(palette: ScenePalette) -> some View {
        GardenSceneView(garden: Self.sampleGarden(), palette: palette, camera: Camera())
            .frame(width: 960, height: 720)
    }

    /// Sunny summer day.
    func testRenderSunnyScene() throws {
        guard let out = ProcessInfo.processInfo.environment["SCENE_PATH"] else { return }
        try writePNG(try pngData(scene(palette: Self.dayPalette)), to: out)
    }

    /// Rainy dusk, same garden.
    func testRenderRainyDuskScene() throws {
        guard let out = ProcessInfo.processInfo.environment["SCENE_RAIN_PATH"] else { return }
        let palette = ScenePalette.resolve(season: .summer, phase: .dusk, condition: .rain,
                                           temperatureC: 14, cloudCover: 90)
        try writePNG(try pngData(scene(palette: palette)), to: out)
    }

    /// Always runs: the scene renders without crashing for every weather state.
    func testSceneRendersForEveryCondition() throws {
        for condition in [WeatherCondition.clear, .fog, .thunderstorm, .snow] {
            let palette = ScenePalette.resolve(season: .winter, phase: .night, condition: condition,
                                               temperatureC: 1, cloudCover: 50)
            XCTAssertFalse(try pngData(scene(palette: palette)).isEmpty)
        }
    }

    /// Writes the judging sheet to FREE_SCENE_DIR: first person day and dusk, backyard day, a seed ghost with a
    /// water ripple on the watered patch, and a ghost on a spot that is not allowed.
    func testRenderFreeSceneSheets() throws {
        guard let dir = ProcessInfo.processInfo.environment["FREE_SCENE_DIR"] else { return }
        let base = URL(fileURLWithPath: dir)
        let garden = Self.sampleGarden()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let watered = GroundPoint(x: 0.8, y: 0.7)

        func write<V: View>(_ view: V, _ name: String) throws {
            let url = base.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            try pngData(view.frame(width: 960, height: 720)).write(to: url)
        }
        try write(GardenSceneView(garden: garden, palette: Self.dayPalette, camera: Camera(), driftEnabled: false),
                  "firstperson-day.png")
        try write(GardenSceneView(garden: garden, palette: Self.duskPalette, camera: Camera(), driftEnabled: false),
                  "firstperson-dusk.png")
        try write(GardenSceneView(garden: garden, palette: Self.dayPalette, camera: Camera(), driftEnabled: false,
                                  style: .backyard),
                  "backyard-day.png")
        try write(SceneContent(garden: garden, palette: Self.dayPalette, camera: Camera(),
                               selectedPoint: watered, hoverPoint: GroundPoint(x: 0.5, y: 0.42),
                               ghostFlower: .lavender,
                               ripples: [SceneRipple(point: watered, startedAt: now.addingTimeInterval(-0.5), kind: .water)],
                               now: now, motion: .still),
                  "firstperson-ghost-ripple.png")
        try write(SceneContent(garden: garden, palette: Self.dayPalette, camera: Camera(),
                               hoverPoint: GroundPoint(x: 0.5, y: 0.97), ghostFlower: .sunflower,
                               now: now, motion: .still),
                  "firstperson-ghost-invalid.png")
    }
}
