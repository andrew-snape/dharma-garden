import XCTest
import SwiftUI
import DharmaGardenCore
@testable import DharmaGardenArt

/// The backyard's side fences must meet the back fence at its ends. Each fence part is built by `BarrierFrame`, and the
/// fence layer moves as one piece (one shift for all of it), so the join must hold in every motion frame.
/// `testRenderFenceCornerSheets` writes PNGs of the corners to FENCE_RENDER_DIR for judging by eye.
@MainActor
final class SceneFenceJoinTests: XCTestCase {
    private let size = CGSize(width: 960, height: 720)

    /// Still, and drifted frames at several times and winds.
    private var frames: [SceneMotion.Frame] {
        [SceneMotion.Frame.still] + [0.0, 4.2, 9.7, 15.3, 21.8, 27.1].flatMap { t in
            [0.0, 1.0].map { SceneMotion.Frame(time: t, wind: $0, enabled: true) }
        }
    }

    /// Canvas points after the fence layer's parallax shift for a frame, as `SceneView` draws that layer.
    private func moved(_ pts: [CGPoint], by frame: SceneMotion.Frame) -> [CGPoint] {
        let s = frame.layerShift(.fence)
        return pts.map { CGPoint(x: $0.x + CGFloat(s.x) * size.width, y: $0.y + CGFloat(s.y) * size.height) }
    }

    /// Asserts two canvas points are within a pixel of each other in this frame.
    private func assertJoined(_ a: CGPoint, _ b: CGPoint, _ what: String, _ frame: SceneMotion.Frame,
                              file: StaticString = #filePath, line: UInt = #line) {
        let d = hypot(a.x - b.x, a.y - b.y)
        XCTAssertLessThanOrEqual(d, 1, "\(what) is \(d) px apart at time \(frame.time), wind \(frame.wind)",
                                 file: file, line: line)
    }

    func testSideFencesStartAtTheBackFenceEndsInEveryFrame() {
        let fence = BarrierFrame(camera: Camera.backyard, size: size)
        let back = fence.backBarrier()
        let rails = back.filter { !$0.isPost }
        let posts = back.filter { $0.isPost }
        let left = fence.sideBarrier(x: -BarrierFrame.halfLength)
        let right = fence.sideBarrier(x: BarrierFrame.halfLength)
        XCTAssertEqual(rails.count, 3)

        for frame in frames {
            let b = rails.map { moved($0.quad, by: frame) }
            let l = left.map { moved($0.quad, by: frame) }
            let r = right.map { moved($0.quad, by: frame) }
            let bp = posts.map { moved($0.quad, by: frame) }
            let lp = l.last!, rp = r.last!
            for i in 0..<rails.count {
                // Left rail: its near-to-join edge is the back rail's left end, bottom and top.
                assertJoined(b[i][0], l[i][0], "left rail \(i) bottom", frame)
                assertJoined(b[i][3], l[i][3], "left rail \(i) top", frame)
                // Right rail: the back rail's right end, bottom and top.
                assertJoined(b[i][1], r[i][0], "right rail \(i) bottom", frame)
                assertJoined(b[i][2], r[i][3], "right rail \(i) top", frame)
            }
            // Corner posts stand on the back fence's end posts, and their faces line up.
            let leftEnd = bp.first!, rightEnd = bp.last!
            assertJoined(leftEnd[0], lp[0], "left corner post base left", frame)
            assertJoined(leftEnd[1], lp[1], "left corner post base right", frame)
            assertJoined(rightEnd[0], rp[0], "right corner post base left", frame)
            assertJoined(rightEnd[1], rp[1], "right corner post base right", frame)
            // The corner posts stand taller, so only their faces (screen x of the top edge) must line up.
            XCTAssertEqual(leftEnd[3].x, lp[3].x, accuracy: 1, "left corner post face at time \(frame.time)")
            XCTAssertEqual(rightEnd[2].x, rp[2].x, accuracy: 1, "right corner post face at time \(frame.time)")
        }
    }

    func testJoinIsSymmetricAndTheSideFencesConverge() {
        let fence = BarrierFrame(camera: Camera.backyard, size: size)
        let back = fence.backBarrier().filter { !$0.isPost }
        let left = fence.sideBarrier(x: -BarrierFrame.halfLength).filter { !$0.isPost }
        let right = fence.sideBarrier(x: BarrierFrame.halfLength).filter { !$0.isPost }
        for i in 0..<3 {
            // Mirror images about the centre line of the scene.
            XCTAssertEqual(back[i].quad[0].x + back[i].quad[1].x, size.width, accuracy: 1)
            XCTAssertEqual(left[i].quad[0].x + right[i].quad[0].x, size.width, accuracy: 1)
            XCTAssertEqual(left[i].quad[0].y, right[i].quad[0].y, accuracy: 0.001)
            // Same rail thickness on screen at the join, for both sides and the back fence.
            let thick = back[i].quad[0].y - back[i].quad[3].y
            XCTAssertEqual(left[i].quad[0].y - left[i].quad[3].y, thick, accuracy: 1)
            XCTAssertEqual(right[i].quad[0].y - right[i].quad[3].y, thick, accuracy: 1)
            // Nearer ends sit further out on screen, so the side rails spread toward the viewer.
            XCTAssertLessThan(left[i].quad[1].x, left[i].quad[0].x)
            XCTAssertGreaterThan(right[i].quad[1].x, right[i].quad[0].x)
        }
    }

    /// Writes the backyard fence corners over sky, lawn and patch, at a still frame and two drifted frames, for
    /// judging by eye. Each frame draws the layers as `SceneView` does, with the same shifts and camera.
    func testRenderFenceCornerSheets() throws {
        guard let dir = ProcessInfo.processInfo.environment["FENCE_RENDER_DIR"] else { return }
        let palette = ScenePalette.resolve(season: .summer, phase: .day, condition: .clear, temperatureC: 26,
                                           cloudCover: 10,
                                           sun: SunLight(elevationDegrees: 38, azimuthDegrees: 200, intensity: 0.9, warmth: 0.1))
        let garden = SceneRenderTests.sampleGarden()
        let base = URL(fileURLWithPath: dir)
        let shots: [(String, SceneMotion.Frame)] = [
            ("still", .still),
            ("drift-a", SceneMotion.Frame(time: 9.7, wind: 1, enabled: true)),
            ("drift-b", SceneMotion.Frame(time: 21.8, wind: 0.5, enabled: true)),
        ]
        for (name, frame) in shots {
            let view = Canvas { ctx, cs in
                // A layer's canvas, shifted by its parallax as `SceneView.canvas` does.
                func layer(_ cam: Camera, _ l: SceneMotion.Layer?) -> SceneCanvas {
                    var g = ctx
                    if let l {
                        let s = frame.layerShift(l)
                        g.translateBy(x: CGFloat(s.x) * cs.width, y: CGFloat(s.y) * cs.height)
                    }
                    return SceneCanvas(ctx: g, size: cs, camera: cam, palette: palette, motion: frame, style: .backyard)
                }
                let drifted = SceneMotion.camera(Camera.backyard, frame: frame)
                layer(Camera.backyard, .sky).drawThemeSky()
                layer(Camera.backyard, .sky).drawThemeClouds()
                layer(Camera.backyard, .hills).drawThemeHorizon()
                layer(drifted, nil).drawThemeGround()
                layer(Camera.backyard, .fence).drawThemeBackdropProps()
                layer(Camera.backyard, .fence).drawThemeBarrier()
                layer(Camera.backyard, .fence).drawThemeSideBarriers()
                layer(drifted, nil).drawPatch(garden, rings: [], selected: nil, ghost: nil)
            }
            .frame(width: 960, height: 720)
            try writePNG(try pngData(view), to: base.appendingPathComponent("fence-\(name).png"))
        }
    }

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
}
