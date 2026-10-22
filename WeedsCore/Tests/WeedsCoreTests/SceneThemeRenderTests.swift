import XCTest
import SwiftUI
import WeedsCore
@testable import WeedsArt

/// Deterministic renders of the scene for before/after pixel comparison. THEME_RENDER_DIR gets one PNG per scene
/// style x light x bed style (named <bed>-<scene>-<light>.png), drawn from the debug scatter of 20 plants at a fixed
/// motion time with no ripples, hover or ghost, so two runs of the same code are byte-identical. THEME_RENDER_THEME
/// (a `SceneTheme` raw value, farm when unset) picks the theme. THEME_BASELINE_DIR points at the sheets written
/// before the theme refactor, and every theme must still render pixel-identical to them.
@MainActor
final class SceneThemeRenderTests: XCTestCase {
    /// Fixed moment for clouds, sway and drift.
    static let motion = SceneMotion.Frame(time: 12.5, wind: 0.25, enabled: true)

    static let lights: [(name: String, palette: ScenePalette)] = [
        ("day", ScenePalette.resolve(season: .summer, phase: .day, condition: .clear, temperatureC: 26, cloudCover: 10,
                                     sun: SunLight(elevationDegrees: 38, azimuthDegrees: 200, intensity: 0.9, warmth: 0.1))),
        ("dusk", ScenePalette.resolve(season: .summer, phase: .dusk, condition: .clear, temperatureC: 16, cloudCover: 10,
                                      sun: SunLight(elevationDegrees: 4, azimuthDegrees: 285, intensity: 0.3, warmth: 0.8))),
        ("night", ScenePalette.resolve(season: .summer, phase: .night, condition: .clear, temperatureC: 12, cloudCover: 10,
                                       sun: SunLight(elevationDegrees: -30, azimuthDegrees: 330, intensity: 0, warmth: 0))),
    ]

    static func garden(_ style: BedStyle) -> Garden {
        var g = Garden(now: Date(timeIntervalSince1970: 1_700_000_000))
        _ = GardenEngine.setBedStyle(style, in: &g)
        return DebugTools.fillWithPlants(garden: g, count: 20)
    }

    /// The scene content for one combination, at the fixed motion time and with nothing date-dependent.
    static func content(garden: Garden, palette: ScenePalette, scene: SceneStyle,
                        theme: SceneTheme = .farm) -> some View {
        let camera: Camera = scene == .backyard ? .backyard : Camera()
        return SceneContent(garden: garden, palette: palette, camera: camera, motion: motion, style: scene, theme: theme)
            .frame(width: 960, height: 720)
    }

    private static var renderedBefore = false

    /// ImageRenderer does not draw the same view identically every time: the first few renders in a process, and the
    /// first two of any view, differ from later ones by up to 4 per channel (a few anti-aliased pixels, mostly in the
    /// sky), then it settles. So every view is rendered three times (eight the very first time) and the last render
    /// is the one kept.
    static func pngData<V: View>(_ view: V) throws -> Data {
        var img: NSImage?
        defer { renderedBefore = true }
        for _ in 0..<(renderedBefore ? 3 : 8) {
            let r = ImageRenderer(content: view)
            r.scale = 1
            img = r.nsImage
        }
        let tiff = try XCTUnwrap(try XCTUnwrap(img).tiffRepresentation)
        return try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }

    static let beds: [BedStyle] = [.soilPatch, .mounds, .grid, .plantersBoxes]

    /// Writes every combination to THEME_RENDER_DIR.
    func testRenderThemeSheets() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["THEME_RENDER_DIR"] else { return }
        let theme = try XCTUnwrap(SceneTheme(rawValue: env["THEME_RENDER_THEME"] ?? "farm"))
        let base = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        for bed in Self.beds {
            let garden = Self.garden(bed)
            for scene in SceneStyle.allCases {
                for light in Self.lights {
                    let data = try Self.pngData(Self.content(garden: garden, palette: light.palette, scene: scene, theme: theme))
                    try data.write(to: base.appendingPathComponent("\(bed.rawValue)-\(scene.rawValue)-\(light.name).png"))
                }
            }
        }
    }

    /// Every theme renders every scene style and light without crashing, and each non-farm theme draws its own
    /// scenery: its picture is not the farm's.
    func testEveryThemeRenders() throws {
        let garden = Self.garden(.soilPatch)
        for scene in SceneStyle.allCases {
            for light in Self.lights {
                let farm = try Self.pngData(Self.content(garden: garden, palette: light.palette, scene: scene))
                XCTAssertFalse(farm.isEmpty)
                for theme in SceneTheme.allCases where theme != .farm {
                    let data = try Self.pngData(Self.content(garden: garden, palette: light.palette, scene: scene, theme: theme))
                    XCTAssertFalse(data.isEmpty)
                    // The PNG encoder's bytes can vary between runs, so compare by pixel. nil (different sizes)
                    // also counts as different.
                    XCTAssertNotEqual(maxChannelDifference(data, farm), 0, "\(theme) \(scene) \(light.name) looks like the farm")
                }
            }
        }
    }

    /// The image as 8-bit sRGB RGBA bytes, with its size.
    private func pixels(_ png: Data) -> (width: Int, height: Int, bytes: [UInt8])? {
        guard let cg = NSBitmapImageRep(data: png)?.cgImage else { return nil }
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8,
                                      bytesPerRow: cg.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            return true
        }
        return drawn ? (cg.width, cg.height, bytes) : nil
    }

    /// Largest per-channel difference between two PNGs, nil when their sizes differ.
    private func maxChannelDifference(_ a: Data, _ b: Data) -> Int? {
        guard let pa = pixels(a), let pb = pixels(b), pa.width == pb.width, pa.height == pb.height else { return nil }
        return zip(pa.bytes, pb.bytes).reduce(0) { max($0, abs(Int($1.0) - Int($1.1))) }
    }

    /// Against THEME_BASELINE_DIR (sheets from before the refactor): the farm theme, every scene style, light and
    /// bed style, matches pixel for pixel (max channel difference 0). The other themes draw their own scenery.
    func testFarmMatchesBaseline() throws {
        guard let dir = ProcessInfo.processInfo.environment["THEME_BASELINE_DIR"] else { return }
        let base = URL(fileURLWithPath: dir)
        var compared = 0
        for bed in Self.beds {
            let garden = Self.garden(bed)
            for scene in SceneStyle.allCases {
                for light in Self.lights {
                    let name = "\(bed.rawValue)-\(scene.rawValue)-\(light.name).png"
                    let expected = try Data(contentsOf: base.appendingPathComponent(name))
                    let data = try Self.pngData(Self.content(garden: garden, palette: light.palette, scene: scene, theme: .farm))
                    compared += 1
                    if data == expected { continue }
                    XCTAssertEqual(maxChannelDifference(data, expected), 0, "farm \(name) differs from the baseline")
                }
            }
        }
        XCTAssertEqual(compared, 24)
    }
}
