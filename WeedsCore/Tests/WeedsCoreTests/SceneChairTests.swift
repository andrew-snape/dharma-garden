import XCTest
import SwiftUI
import WeedsCore
@testable import WeedsArt

/// The reading chair is drawn in every theme and style, and a press on it (and only near it) is a hit.
/// `testRenderChairSheets` writes PNGs to CHAIR_RENDER_DIR for judging by eye.
@MainActor
final class SceneChairTests: XCTestCase {
    private let size = CGSize(width: 960, height: 720)

    func testPressOnChairHitsAndFarPressMisses() {
        for cam in [Camera(), Camera.backyard] {
            let rect = SceneContent.chairRect(size: size, camera: cam)
            XCTAssertTrue(SceneContent.chairHit(at: CGPoint(x: rect.midX, y: rect.midY), size: size, camera: cam))
            XCTAssertFalse(SceneContent.chairHit(at: CGPoint(x: rect.midX + rect.width * 2, y: rect.midY), size: size, camera: cam))
            XCTAssertFalse(SceneContent.chairHit(at: CGPoint(x: size.width / 2, y: size.height / 2), size: size, camera: cam))
        }
    }

    func testChairIsOnScreenAndClearOfBed() {
        for cam in [Camera(), Camera.backyard] {
            let rect = SceneContent.chairRect(size: size, camera: cam)
            XCTAssertTrue(CGRect(origin: .zero, size: size).contains(rect), "\(cam) \(rect)")
            let ground = cam.groundPoint(atScreen: (x: Double(rect.midX / size.width), y: Double(rect.maxY / size.height)))
            let plot = Garden(now: Date()).plot
            XCTAssertFalse(ground.map { plot.contains($0) } ?? false)
        }
    }

    func testRenderChairSheets() throws {
        guard let dir = ProcessInfo.processInfo.environment["CHAIR_RENDER_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let palette = ScenePalette.resolve(season: .summer, phase: .day, condition: .clear, temperatureC: 24, cloudCover: 10)
        for style in SceneStyle.allCases {
            for theme in SceneTheme.allCases {
                let view = GardenSceneView(garden: SceneRenderTests.sampleGarden(), palette: palette, driftEnabled: false,
                                           style: style, theme: theme)
                    .frame(width: 960, height: 720)
                let r = ImageRenderer(content: view)
                r.scale = 1
                let tiff = try XCTUnwrap(r.nsImage?.tiffRepresentation)
                let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("chair-\(style)-\(theme).png"))
            }
        }
    }
}
