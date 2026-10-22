import XCTest
import SwiftUI
import WeedsCore
@testable import WeedsArt

/// Both scene styles render in every weather state, with a seed ghost and a ripple, and optional PNG sheets for
/// judging by eye: SCENE_STYLE_DIR gets first-person and backyard, sunny day and rainy dusk; POLISH_SHEET_PATH
/// gets a time-lapse of daisy, lavender, basil and zucchini; BED_STYLE_DIR gets the grid, mounds and planter bed
/// styles in both scene styles at day, dusk and night. Each test writes only to its own env path.
@MainActor
final class SceneStyleRenderTests: XCTestCase {
    private func pngData<V: View>(_ view: V) throws -> Data {
        let r = ImageRenderer(content: view)
        r.scale = 1
        let img = try XCTUnwrap(r.nsImage)
        let tiff = try XCTUnwrap(img.tiffRepresentation)
        return try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }

    private func writePNG(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    private func scene(_ style: SceneStyle, palette: ScenePalette) -> some View {
        GardenSceneView(garden: SceneRenderTests.sampleGarden(), palette: palette, camera: Camera(),
                        selectedPoint: GroundPoint(x: 0.5, y: 0.5), hoverPoint: GroundPoint(x: 0.3, y: 0.7),
                        ghostFlower: .daisy, ripples: [SceneRipple(point: GroundPoint(x: 0.8, y: 0.6),
                                                                   startedAt: Date(), kind: .water)],
                        driftEnabled: false, style: style)
            .frame(width: 960, height: 720)
    }

    func testStyleDisplayNames() {
        XCTAssertEqual(SceneStyle.firstPerson.displayName, "First person")
        XCTAssertEqual(SceneStyle.backyard.displayName, "Backyard")
        XCTAssertEqual(SceneStyle.allCases, [.firstPerson, .backyard])
    }

    /// Always runs: both styles render without crashing in every weather state, day and night.
    func testBothStylesRenderForEveryCondition() throws {
        for style in SceneStyle.allCases {
            let conditions: [WeatherCondition] = [.clear, .partlyCloudy, .overcast, .fog, .drizzle, .rain, .thunderstorm, .snow]
            for condition in conditions {
                for phase in [SunPhase.day, .night] {
                    let palette = ScenePalette.resolve(season: .winter, phase: phase, condition: condition,
                                                       temperatureC: 1, cloudCover: 50)
                    XCTAssertFalse(try pngData(scene(style, palette: palette)).isEmpty,
                                   "\(style) \(condition) \(phase)")
                }
            }
        }
    }

    /// Sunny day and rainy dusk in both styles, written to SCENE_STYLE_DIR.
    func testRenderSceneStyleSheets() throws {
        guard let dir = ProcessInfo.processInfo.environment["SCENE_STYLE_DIR"] else { return }
        let sunny = ScenePalette.resolve(season: .summer, phase: .day, condition: .clear, temperatureC: 26,
                                         cloudCover: 10,
                                         sun: SunLight(elevationDegrees: 38, azimuthDegrees: 200, intensity: 0.9, warmth: 0.1))
        let rainyDusk = ScenePalette.resolve(season: .summer, phase: .dusk, condition: .rain, temperatureC: 14,
                                             cloudCover: 90,
                                             sun: SunLight(elevationDegrees: 3, azimuthDegrees: 275, intensity: 0.15, warmth: 0.8))
        let base = URL(fileURLWithPath: dir)
        let outputs: [(String, SceneStyle, ScenePalette)] = [
            ("firstperson-day", .firstPerson, sunny), ("firstperson-dusk", .firstPerson, rainyDusk),
            ("backyard-day", .backyard, sunny), ("backyard-dusk", .backyard, rainyDusk),
        ]
        for (name, style, palette) in outputs {
            try writePNG(try pngData(scene(style, palette: palette)), to: base.appendingPathComponent("\(name).png"))
        }
    }

    /// One row per plant: 10 progress columns, then droop 0.7, fade 0.5 and a seed head. Written to POLISH_SHEET_PATH.
    func testRenderPolishSheet() throws {
        guard let out = ProcessInfo.processInfo.environment["POLISH_SHEET_PATH"] else { return }
        let cell = CGFloat(Double(ProcessInfo.processInfo.environment["POLISH_CELL"] ?? "") ?? 120)
        let plants: [FlowerType] = [.daisy, .lavender, .basil, .zucchini]
        func row(_ f: FlowerType) -> [FlowerArt] {
            var arts = (0..<10).map { FlowerArt(flower: f, progress: Double($0) / 9) }
            arts.append(FlowerArt(flower: f, progress: 1, droop: 0.7))
            arts.append(FlowerArt(flower: f, progress: 1, fade: 0.5))
            arts.append(FlowerArt(flower: f, progress: 1, isSeedHead: true))
            return arts
        }
        let rows = plants.map(row)
        let sky = LinearGradient(colors: [Color(hex: 0xBFE0EE), Color(hex: 0xF7EBC8), Color(hex: 0xA9C26A)],
                                 startPoint: .top, endPoint: .bottom)
        let view = ZStack {
            sky
            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(rows[r].indices, id: \.self) { i in
                            rows[r][i].frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
        .frame(width: cell * 13, height: cell * CGFloat(plants.count))
        try writePNG(try pngData(view), to: URL(fileURLWithPath: out))
    }

    /// A garden in one bed style with 20 scattered plants, as the player sees it after some planting.
    private func bedGarden(_ style: BedStyle) -> Garden {
        var g = Garden(now: Date(timeIntervalSince1970: 1_700_000_000))
        _ = GardenEngine.setBedStyle(style, in: &g)
        return DebugTools.fillWithPlants(garden: g, count: 20)
    }

    /// Light for the bed sheets: a clear day with the sun high, a low golden dusk, and night with the sun under.
    private static let bedLights: [(name: String, palette: ScenePalette)] = [
        ("day", ScenePalette.resolve(season: .summer, phase: .day, condition: .clear, temperatureC: 26, cloudCover: 10,
                                     sun: SunLight(elevationDegrees: 38, azimuthDegrees: 200, intensity: 0.9, warmth: 0.1))),
        ("dusk", ScenePalette.resolve(season: .summer, phase: .dusk, condition: .clear, temperatureC: 16, cloudCover: 10,
                                      sun: SunLight(elevationDegrees: 4, azimuthDegrees: 285, intensity: 0.3, warmth: 0.8))),
        ("night", ScenePalette.resolve(season: .summer, phase: .night, condition: .clear, temperatureC: 12, cloudCover: 10,
                                       sun: SunLight(elevationDegrees: -30, azimuthDegrees: 330, intensity: 0, warmth: 0))),
    ]

    /// The three new bed styles in both scene styles, at day, dusk and night. Written to BED_STYLE_DIR as
    /// <style>-<scene>-<light>.png, one file per combination.
    func testRenderBedStyleSheets() throws {
        guard let dir = ProcessInfo.processInfo.environment["BED_STYLE_DIR"] else { return }
        let base = URL(fileURLWithPath: dir)
        for style in [BedStyle.grid, .mounds, .plantersBoxes] {
            let garden = bedGarden(style)
            for scene in SceneStyle.allCases {
                for light in Self.bedLights {
                    let view = GardenSceneView(garden: garden, palette: light.palette, camera: Camera(),
                                               driftEnabled: false, style: scene)
                        .frame(width: 960, height: 720)
                    let name = "\(style.rawValue)-\(scene.rawValue)-\(light.name).png"
                    try writePNG(try pngData(view), to: base.appendingPathComponent(name))
                }
            }
        }
    }

    /// Every planter box with a seed planted as close to each of its four corners as the rules allow (found by walking
    /// in along the diagonal), to check by eye that no seed overlaps a post. Written as planter-corners-<scene>-<light>.png.
    func testRenderPlanterCornerSeeds() throws {
        guard let dir = ProcessInfo.processInfo.environment["BED_STYLE_DIR"] else { return }
        var garden = Garden(now: Date(timeIntervalSince1970: 1_700_000_000))
        _ = GardenEngine.setBedStyle(.plantersBoxes, in: &garden)
        for region in garden.plot.regions {
            for sx in [-1.0, 1.0] {
                for sy in [-1.0, 1.0] {
                    var d = 0.0
                    var p = GroundPoint(x: region.centre.x + sx * region.halfWidth, y: region.centre.y + sy * region.halfHeight)
                    while !GardenEngine.canPlant(at: p, in: garden) && d < 0.2 {
                        d += 0.001
                        p = GroundPoint(x: region.centre.x + sx * (region.halfWidth - d),
                                        y: region.centre.y + sy * (region.halfHeight - d))
                    }
                    garden.plants.append(Plant(id: garden.plants.count + 1, flower: .daisy, position: p))
                }
            }
        }
        for scene in SceneStyle.allCases {
            for light in Self.bedLights.prefix(2) {
                let view = GardenSceneView(garden: garden, palette: light.palette, camera: Camera(),
                                           driftEnabled: false, style: scene)
                    .frame(width: 960, height: 720)
                let name = "planter-corners-\(scene.rawValue)-\(light.name).png"
                try writePNG(try pngData(view), to: URL(fileURLWithPath: dir).appendingPathComponent(name))
            }
        }
    }

    /// The grid bed has no line in it. Along a row through the middle of the soil (no plants there, so nothing else
    /// crosses it), brightness changes only gently even where the moisture changes: a cell edge or a grid line would
    /// show as a sharp step, and several would repeat across the bed.
    func testGridBedHasNoSharpStepsAcrossTheSoil() throws {
        let garden: Garden = {
            var g = Garden(now: Date(timeIntervalSince1970: 1_700_000_000))
            _ = GardenEngine.setBedStyle(.grid, in: &g)
            // Uneven moisture across the row, so the cells differ and any edge between them would show.
            GardenEngine.water(at: GroundPoint(x: 0.3, y: 0.5), in: &g, radius: 0.2, amount: -90)
            GardenEngine.water(at: GroundPoint(x: 0.7, y: 0.5), in: &g, radius: 0.2, amount: 70)
            return g
        }()
        let palette = Self.bedLights[0].palette
        let view = Canvas { ctx, size in
            SceneCanvas(ctx: ctx, size: size, camera: Camera(), palette: palette)
                .drawPatch(garden, rings: [], selected: nil, ghost: nil)
        }
        .frame(width: 960, height: 720)
        let rep = try bitmapRep(view)
        let row = rep.pixelsHigh / 2
        var sharp: [String] = []
        var previous = luminance(rep, x: 260, y: row)
        var lowest = previous
        for x in 261..<700 {
            let l = luminance(rep, x: x, y: row)
            if abs(l - previous) > 0.02 { sharp.append("x\(x):\(String(format: "%.3f", abs(l - previous)))") }
            previous = l
            lowest = min(lowest, l)
        }
        // The row must really cross the soil (a blank frame has no luminance at all).
        XCTAssertGreaterThan(lowest, 0.1, "the row should cross the soil")
        XCTAssertLessThanOrEqual(sharp.count, 4, "sharp luminance steps across the grid bed: \(sharp)")
    }

    /// Renders a view at scale 1 and returns its bitmap, for reading pixels back.
    private func bitmapRep<V: View>(_ view: V) throws -> NSBitmapImageRep {
        let r = ImageRenderer(content: view)
        r.scale = 1
        let img = try XCTUnwrap(r.nsImage)
        let tiff = try XCTUnwrap(img.tiffRepresentation)
        return try XCTUnwrap(NSBitmapImageRep(data: tiff))
    }

    /// Relative luminance of one pixel, 0...1.
    private func luminance(_ rep: NSBitmapImageRep, x: Int, y: Int) -> Double {
        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return 0 }
        return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
    }
}
