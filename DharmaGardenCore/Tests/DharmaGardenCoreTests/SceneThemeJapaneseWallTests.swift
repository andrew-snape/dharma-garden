import XCTest
import SwiftUI
import DharmaGardenCore
@testable import DharmaGardenArt

/// The Japanese wall's side walls must start exactly where the back wall ends, in every motion frame (the fence layer
/// moves as one piece), and the walls must keep the shared upright projection: verticals vertical, lines along z
/// running to the lawn's vanishing point.
final class SceneThemeJapaneseWallTests: XCTestCase {
    private let size = CGSize(width: 960, height: 720)

    private var frames: [SceneMotion.Frame] {
        [SceneMotion.Frame.still] + [0.0, 4.2, 9.7, 15.3, 21.8, 27.1].flatMap { t in
            [0.0, 1.0].map { SceneMotion.Frame(time: t, wind: $0, enabled: true) }
        }
    }

    private func moved(_ q: CGPoint, by frame: SceneMotion.Frame) -> CGPoint {
        let s = frame.layerShift(.fence)
        return CGPoint(x: q.x + CGFloat(s.x) * size.width, y: q.y + CGFloat(s.y) * size.height)
    }

    private func assertJoined(_ a: CGPoint, _ b: CGPoint, _ what: String, _ frame: SceneMotion.Frame,
                              file: StaticString = #filePath, line: UInt = #line) {
        let d = hypot(a.x - b.x, a.y - b.y)
        XCTAssertLessThanOrEqual(d, 1, "\(what) is \(d) px apart at time \(frame.time), wind \(frame.wind)", file: file, line: line)
    }

    func testSideWallsStartAtTheBackWallEndsInEveryFrame() {
        let wall = JapaneseWall(camera: .backyard, size: size)
        let back = wall.back
        let left = wall.side(x: -BarrierFrame.halfLength), right = wall.side(x: BarrierFrame.halfLength)
        let heights = [0, JapaneseWall.footHeight, JapaneseWall.eaveHeight, JapaneseWall.ridgeHeight]
        for frame in frames {
            for h in heights {
                assertJoined(moved(wall.point(back, 0, h), by: frame), moved(wall.point(left, 0, h), by: frame), "left wall at \(h)", frame)
                assertJoined(moved(wall.point(back, 1, h), by: frame), moved(wall.point(right, 0, h), by: frame), "right wall at \(h)", frame)
            }
            // The bodies and caps share those end points (quad order: start bottom, end bottom, end top, start top).
            let bb = wall.body(back), lb = wall.body(left), rb = wall.body(right)
            assertJoined(moved(bb[0], by: frame), moved(lb[0], by: frame), "left body bottom", frame)
            assertJoined(moved(bb[3], by: frame), moved(lb[3], by: frame), "left body top", frame)
            assertJoined(moved(bb[1], by: frame), moved(rb[0], by: frame), "right body bottom", frame)
            assertJoined(moved(bb[2], by: frame), moved(rb[3], by: frame), "right body top", frame)
            let bc = wall.cap(back), lc = wall.cap(left), rc = wall.cap(right)
            assertJoined(moved(bc[3], by: frame), moved(lc[3], by: frame), "left cap ridge", frame)
            assertJoined(moved(bc[2], by: frame), moved(rc[3], by: frame), "right cap ridge", frame)
        }
    }

    func testWallsAreSymmetricAndUpright() {
        let wall = JapaneseWall(camera: .backyard, size: size)
        let back = wall.back
        let l = wall.side(x: -BarrierFrame.halfLength), r = wall.side(x: BarrierFrame.halfLength)
        // Mirror images about the centre line, and the back wall is level.
        XCTAssertEqual(wall.point(back, 0, 0).x + wall.point(back, 1, 0).x, size.width, accuracy: 1)
        XCTAssertEqual(wall.point(l, 1, 0).x + wall.point(r, 1, 0).x, size.width, accuracy: 1)
        XCTAssertEqual(wall.point(back, 0, 0.5).y, wall.point(back, 1, 0.5).y, accuracy: 0.001)
        // Verticals are vertical on screen, everywhere along each wall.
        for run in [back, l, r] {
            for t in [0.0, 0.3, 0.7, 1.0] {
                XCTAssertEqual(wall.point(run, t, 0).x, wall.point(run, t, JapaneseWall.ridgeHeight).x, accuracy: 1e-9)
            }
        }
        // The side walls spread toward the viewer, and every height runs to the same vanishing point as the ground.
        XCTAssertLessThan(wall.point(l, 1, 0).x, wall.point(l, 0, 0).x)
        XCTAssertGreaterThan(wall.point(r, 1, 0).x, wall.point(r, 0, 0).x)
        func vanishing(_ run: JapaneseWall.Run, _ h: Double) -> CGPoint? {
            // Intersect the side wall's line at height h with the centre line x = size.width / 2.
            let a = wall.point(run, 0, h), b = wall.point(run, 1, h)
            guard abs(b.x - a.x) > 1e-6 else { return nil }
            let t = (size.width / 2 - a.x) / (b.x - a.x)
            return CGPoint(x: size.width / 2, y: a.y + (b.y - a.y) * t)
        }
        let ground = vanishing(l, 0)!, top = vanishing(l, JapaneseWall.eaveHeight)!, ridge = vanishing(l, JapaneseWall.ridgeHeight)!
        XCTAssertEqual(top.y, ground.y, accuracy: 0.5)
        XCTAssertEqual(ridge.y, ground.y, accuracy: 0.5)
    }

    /// The side wall ends short of the camera, as the rail fence does.
    func testSideWallsStopAtTwoPointNine() {
        let wall = JapaneseWall(camera: .backyard, size: size)
        XCTAssertEqual(wall.side(x: 4.5).b.z, 2.9)
        XCTAssertEqual(wall.side(x: -4.5).b.z, 2.9)
        XCTAssertEqual(wall.back.a.z, SceneCanvas.fenceZ)
    }
}
