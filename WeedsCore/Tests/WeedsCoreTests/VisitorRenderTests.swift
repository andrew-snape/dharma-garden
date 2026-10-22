import XCTest
import SwiftUI
@testable import WeedsCore
@testable import WeedsArt

/// Renders the visitor art and sample scenes to PNG so they can be judged by eye. Each test writes only when
/// VISITOR_RENDER_DIR is set (it is the folder for the PNGs).
@MainActor
final class VisitorRenderTests: XCTestCase {
    static let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    static let nightPalette = ScenePalette.resolve(season: .summer, phase: .night, condition: .clear,
                                                   temperatureC: 16, cloudCover: 10)

    private func pngData<V: View>(_ view: V) throws -> Data {
        let r = ImageRenderer(content: view)
        r.scale = 1
        let img = try XCTUnwrap(r.nsImage)
        let tiff = try XCTUnwrap(img.tiffRepresentation)
        return try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }

    private func write(_ view: some View, _ dir: URL, _ name: String) throws {
        try pngData(view).write(to: dir.appendingPathComponent(name))
    }

    private func outputDir() throws -> URL? {
        guard let path = ProcessInfo.processInfo.environment["VISITOR_RENDER_DIR"] else { return nil }
        let dir = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A pose from the real motion at the middle of a visitor's stay, on the patch centre.
    static func midStayPose(_ s: VisitorSpecies) -> VisitorPose {
        let v = Visitor(id: 11, species: s, position: GroundPoint(x: 0.5, y: 0.5), spawnedAt: t0, lifetime: 40)
        return VisitorMotion.pose(of: v, at: t0.addingTimeInterval(20))
    }

    /// A small backdrop in the palette's sky and lawn colours, so each visitor is seen as it would be.
    private func backdrop<V: View>(_ palette: ScenePalette, _ content: V) -> some View {
        ZStack(alignment: .bottom) {
            Rectangle().fill(LinearGradient(colors: [SceneColour.color(palette.skyTop), SceneColour.color(palette.skyBottom)],
                                            startPoint: .top, endPoint: .bottom))
            Rectangle().fill(SceneColour.color(palette.grass)).frame(height: 60)
            content
        }
    }

    /// Every species at day, dusk and night, at 160 points, with the moth glowing at night.
    func testRenderEverySpeciesAtDayDuskNight() throws {
        guard let dir = try outputDir() else { return }
        let phases: [(String, ScenePalette)] = [("day", SceneRenderTests.dayPalette),
                                                ("dusk", SceneRenderTests.duskPalette),
                                                ("night", Self.nightPalette)]
        for (name, palette) in phases {
            for s in VisitorSpecies.allCases {
                let art = VisitorArt(species: s, size: 160, pose: Self.midStayPose(s), night: name == "night")
                try write(backdrop(palette, art).frame(width: 200, height: 200), dir, "\(s.rawValue)-\(name).png")
            }
        }
    }

    /// Every species in silhouette (the collection book before a visitor is spotted).
    func testRenderSilhouettes() throws {
        guard let dir = try outputDir() else { return }
        for s in VisitorSpecies.allCases {
            let art = VisitorArt(species: s, size: 160, pose: Self.midStayPose(s), silhouette: true)
            try write(backdrop(SceneRenderTests.dayPalette, art).frame(width: 200, height: 200), dir,
                      "silhouette-\(s.rawValue).png")
        }
    }

    /// All twelve species at 60 points, on the day backdrop: the size they show in the scene.
    func testRenderSixtyPointSheet() throws {
        guard let dir = try outputDir() else { return }
        let row = { (species: [VisitorSpecies]) in
            HStack(spacing: 8) {
                ForEach(species, id: \.self) { s in
                    VisitorArt(species: s, size: 60, pose: Self.midStayPose(s))
                }
            }
        }
        let sheet = VStack(spacing: 8) {
            row(Array(VisitorSpecies.allCases.prefix(6)))
            row(Array(VisitorSpecies.allCases.suffix(6)))
        }
        try write(backdrop(SceneRenderTests.dayPalette, sheet).frame(width: 560, height: 200), dir,
                  "sheet-60px-day.png")
    }

    /// A full scene with three visitors on each bed style, and a sparkle where one was spotted.
    func testRenderVisitorScenesOnEveryBedStyle() throws {
        guard let dir = try outputDir() else { return }
        let now = Self.t0.addingTimeInterval(20)
        for style in BedStyle.allCases {
            var garden = SceneRenderTests.sampleGarden()
            garden.plot.style = style
            let kinds: [VisitorSpecies] = [.bee, .orangeButterfly, .magpieLark]
            let visitors = kinds.enumerated().map { i, s in
                Visitor(id: 100 + i, species: s, position: garden.plot.point(seed: UInt64(i) &* 7919 &+ 3, inset: 0.05),
                        spawnedAt: Self.t0, lifetime: 40)
            }
            let spot = visitors[0].position
            let scene = SceneContent(garden: garden, palette: SceneRenderTests.dayPalette, camera: Camera(),
                                     ripples: [SceneRipple(point: spot, startedAt: now.addingTimeInterval(-0.3), kind: .spot)],
                                     now: now, motion: .still, visitors: visitors)
            try write(scene.frame(width: 960, height: 720), dir, "scene-\(style.rawValue).png")
        }
    }
}
