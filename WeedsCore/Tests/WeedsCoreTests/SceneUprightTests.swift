import XCTest
import WeedsCore
@testable import WeedsArt

/// `Camera.upright`: things with height keep vertical edges vertical, and lines parallel to z at any height share the
/// lawn's vanishing point. Checked for both framings and for drifted cameras.
final class SceneUprightTests: XCTestCase {
    private var cameras: [Camera] {
        [Camera(), Camera.backyard]
            + [Camera.backyard, Camera()].map { SceneMotion.camera($0, frame: SceneMotion.Frame(time: 9.7, wind: 1, enabled: true)) }
    }

    /// Intersection of the lines through (p, q) and (r, s).
    private func intersection(_ p: (x: Double, y: Double), _ q: (x: Double, y: Double),
                              _ r: (x: Double, y: Double), _ s: (x: Double, y: Double)) -> (x: Double, y: Double) {
        let d = (p.x - q.x) * (r.y - s.y) - (p.y - q.y) * (r.x - s.x)
        let a = p.x * q.y - p.y * q.x, b = r.x * s.y - r.y * s.x
        return (x: (a * (r.x - s.x) - (p.x - q.x) * b) / d, y: (a * (r.y - s.y) - (p.y - q.y) * b) / d)
    }

    func testHeightZeroIsTheTrueProjection() {
        for cam in cameras {
            for (x, z) in [(0.0, 0.0), (-3.2, -2.0), (4.5, 2.9)] {
                let a = cam.upright(x: x, z: z), b = cam.project(x: x, z: z)
                XCTAssertEqual(a.x, b.x, accuracy: 1e-12)
                XCTAssertEqual(a.y, b.y, accuracy: 1e-12)
                XCTAssertEqual(a.scale, b.scale, accuracy: 1e-12)
            }
        }
    }

    func testVerticalsAreExactlyVerticalAndRiseWithHeight() {
        for cam in cameras {
            for (x, z) in [(0.0, 0.0), (-4.5, -3.3), (4.5, 2.9), (1.3, -1.1)] {
                let base = cam.upright(x: x, z: z)
                var lastY = base.y
                for h in [0.2, 0.5, 0.92] {
                    let q = cam.upright(x: x, z: z, height: h)
                    XCTAssertEqual(q.x, base.x, accuracy: 1e-12)
                    XCTAssertLessThan(q.y, lastY)
                    lastY = q.y
                }
            }
        }
    }

    func testHeightAtTheGardenCentreIsTheTrueHeight() {
        for cam in cameras {
            let h = 0.4
            XCTAssertEqual(cam.upright(x: 0, z: 0, height: h).y, cam.project(x: 0, z: 0, height: h).y, accuracy: 0.01)
        }
    }

    func testLinesParallelToZShareTheGroundVanishingPoint() {
        for cam in cameras {
            let z0 = -3.3, z1 = 2.9
            func pt(_ x: Double, _ z: Double, _ h: Double) -> (x: Double, y: Double) {
                let q = cam.upright(x: x, z: z, height: h); return (q.x, q.y)
            }
            let vp = intersection(pt(-4.5, z0, 0), pt(-4.5, z1, 0), pt(4.5, z0, 0), pt(4.5, z1, 0))
            for x in [-4.5, 4.5, 1.7] {
                for h in [0.2, 0.48, 0.76, 1.5] {
                    let m = intersection(pt(x, z0, h), pt(x, z1, h), pt(-4.5, z0, 0), pt(-4.5, z1, 0))
                    XCTAssertEqual(m.x, vp.x, accuracy: 1e-6, "x at height \(h)")
                    XCTAssertEqual(m.y, vp.y, accuracy: 1e-6, "y at height \(h)")
                }
            }
        }
    }

    func testInverseRoundTrips() {
        for cam in cameras {
            for h in [0.0, 0.25, 0.7, 1.2] {
                for i in 0...10 {
                    for j in 0...10 {
                        let g = GroundPoint(x: -0.2 + 1.4 * Double(i) / 10, y: -0.2 + 1.4 * Double(j) / 10)
                        let q = cam.uprightGroundPoint(x: g.x, y: g.y, height: h)
                        let back = cam.groundPoint(atScreen: (x: q.x, y: q.y), uprightHeight: h)
                        XCTAssertEqual(back?.x ?? -9, g.x, accuracy: 1e-9)
                        XCTAssertEqual(back?.y ?? -9, g.y, accuracy: 1e-9)
                    }
                }
            }
        }
    }

    /// The side fence's rails, at every height, run to the same point as the lawn's edge lines.
    func testSideFenceRailsConvergeOnTheLawnVanishingPoint() {
        let size = CGSize(width: 960, height: 720)
        let cam = Camera.backyard
        let fence = BarrierFrame(camera: cam, size: size)
        func line(_ a: CGPoint, _ b: CGPoint) -> ((x: Double, y: Double), (x: Double, y: Double)) {
            ((Double(a.x), Double(a.y)), (Double(b.x), Double(b.y)))
        }
        let ground = (fence.point(x: 4.5, z: -3.3), fence.point(x: 4.5, z: 2.9))
        let g = line(ground.0, ground.1)
        let rails = fence.sideBarrier(x: 4.5).filter { !$0.isPost }
        XCTAssertEqual(rails.count, 3)
        var points: [(x: Double, y: Double)] = []
        for rail in rails {
            let l = line(rail.quad[0], rail.quad[1])   // the rail's lower edge, back end to front end
            points.append(intersection(l.0, l.1, g.0, g.1))
        }
        for m in points {
            XCTAssertEqual(m.x, points[0].x, accuracy: 1e-3)
            XCTAssertEqual(m.y, points[0].y, accuracy: 1e-3)
        }
    }
}
