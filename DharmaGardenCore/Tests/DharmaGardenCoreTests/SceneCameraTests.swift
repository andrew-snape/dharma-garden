import XCTest
import DharmaGardenCore
@testable import DharmaGardenArt

/// The ground plane of the planting patch: mapping to the screen, the exact inverse, and the plot outline.
final class SceneCameraTests: XCTestCase {
    /// Both framings, undrifted.
    let framings: [Camera] = [Camera(), Camera.backyard]

    /// Drift states: calm and strong wind, spread across the drift cycle, with and without offsets.
    func driftedCameras(_ base: Camera) -> [Camera] {
        stride(from: 0.0, through: 40.0, by: 3.7).flatMap { t in
            [0.0, 1.0].map { wind in
                SceneMotion.camera(base, frame: SceneMotion.Frame(time: t, wind: wind, enabled: true))
            }
        }
    }

    /// Points from just past the back of the patch to just past the front, including points on the lawn.
    func samplePoints() -> [(x: Double, y: Double)] {
        var out: [(x: Double, y: Double)] = []
        for i in 0...20 {
            for j in 0...20 {
                let x: Double = -0.2 + 1.4 * Double(i) / 20
                let y: Double = -0.2 + 1.4 * Double(j) / 20
                out.append((x: x, y: y))
            }
        }
        return out
    }

    func assertRoundTrip(_ cam: Camera, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        for p in samplePoints() {
            let s = cam.groundPoint(x: p.x, y: p.y)
            guard let back = cam.groundPoint(atScreen: (x: s.x, y: s.y)) else {
                XCTFail("\(label): ground point (\(p.x), \(p.y)) gave no hit", file: file, line: line)
                return
            }
            XCTAssertEqual(back.x, p.x, accuracy: 1e-9, "\(label) x at (\(p.x), \(p.y))", file: file, line: line)
            XCTAssertEqual(back.y, p.y, accuracy: 1e-9, "\(label) y at (\(p.x), \(p.y))", file: file, line: line)
        }
    }

    func testGroundRoundTripWithoutDrift() {
        for cam in framings { assertRoundTrip(cam, "undrifted") }
    }

    func testGroundRoundTripWithDriftInBothStyles() {
        for base in framings {
            for (k, cam) in driftedCameras(base).enumerated() {
                assertRoundTrip(cam, "drift \(k)")
            }
        }
    }

    func testRoundTripWithManualOffsetsAndPitch() {
        var cam = Camera()
        cam.offset = (x: 0.07, y: -0.04)
        cam.pitchOffsetDegrees = 1.5
        assertRoundTrip(cam, "manual drift")
    }

    func testGroundCornersAreThePatchCorners() {
        // The unit square maps onto the world patch, centred on the garden: its corners sit half a patch out.
        let half = Camera.patchSide / 2
        for cam in framings {
            let corner = cam.groundPoint(x: 0, y: 0)
            let world = cam.project(x: -half, z: -half)
            XCTAssertEqual(corner.x, world.x, accuracy: 1e-12)
            XCTAssertEqual(corner.y, world.y, accuracy: 1e-12)
            XCTAssertEqual(corner.scale, world.scale, accuracy: 1e-12)
            let far = cam.groundPoint(x: 1, y: 1)
            let farWorld = cam.project(x: half, z: half)
            XCTAssertEqual(far.x, farWorld.x, accuracy: 1e-12)
            XCTAssertEqual(far.y, farWorld.y, accuracy: 1e-12)
        }
    }

    func testPatchIsAboutThirtyFivePercentWiderThanTheOldGrid() {
        XCTAssertEqual(Camera.patchSide / 4.0, 1.35, accuracy: 0.005, "the old grid was 4 world units wide")
        for cam in framings {
            let width = cam.groundPoint(x: 1, y: 0.5).x - cam.groundPoint(x: 0, y: 0.5).x
            let old = cam.project(x: 2, z: 0).x - cam.project(x: -2, z: 0).x
            XCTAssertGreaterThan(width, old * 1.2, "the patch is wider on screen than the 4-unit grid")
        }
    }

    func testGardenCentreIsTheGroundCentreAtScaleOne() {
        for cam in framings {
            let c = cam.groundPoint(x: 0.5, y: 0.5)
            XCTAssertEqual(c.x, cam.focus.x, accuracy: 1e-9)
            XCTAssertEqual(c.y, cam.focus.y, accuracy: 1e-9)
            XCTAssertEqual(c.scale, 1, accuracy: 1e-9)
            XCTAssertEqual(cam.scale(atGroundY: 0.5), 1, accuracy: 1e-9)
        }
    }

    func testScaleAtGroundYMatchesTheWorldDepthScale() {
        for cam in framings {
            for y in stride(from: 0.05, through: 0.95, by: 0.1) {
                let z = Camera.groundWorld(x: 0.5, y: y).z
                XCTAssertEqual(cam.scale(atGroundY: y), cam.project(x: 0, z: z).scale, accuracy: 1e-9)
            }
        }
    }

    func testBackEdgeIsSmallerThanFrontEdge() {
        for cam in framings {
            XCTAssertLessThan(cam.scale(atGroundY: 0.1), cam.scale(atGroundY: 0.9))
            let backWidth = cam.groundPoint(x: 1, y: 0.1).x - cam.groundPoint(x: 0, y: 0.1).x
            let frontWidth = cam.groundPoint(x: 1, y: 0.9).x - cam.groundPoint(x: 0, y: 0.9).x
            XCTAssertLessThan(backWidth, frontWidth, "the back edge of the patch is narrower on screen")
        }
    }

    func testScaleGrowsWithDepthForEveryY() {
        for cam in framings {
            var last = 0.0
            for y in stride(from: 0.0, through: 1.0, by: 0.05) {
                let s = cam.scale(atGroundY: y)
                XCTAssertGreaterThan(s, last, "scale rises toward the viewer at y \(y)")
                last = s
            }
        }
    }

    func testPlotOutlineProjectsInsideTheFrame() {
        let outline = SceneCanvas.patchOutline(PlotShape())
        XCTAssertGreaterThan(outline.count, 40)
        for cam in framings {
            for p in outline {
                let q = cam.groundPoint(x: p.x, y: p.y)
                XCTAssertTrue((0.0...1.0).contains(q.x), "outline x \(q.x) off screen")
                XCTAssertTrue((0.0...1.0).contains(q.y), "outline y \(q.y) off screen")
            }
        }
    }

    func testPlotOutlineLiesOnThePlotEdge() {
        let plot = PlotShape()
        for p in SceneCanvas.patchOutline(plot) {
            XCTAssertEqual(plot.edgeDistance(p), 0, accuracy: 1e-6)
        }
    }

    func testPlotOutlineStaysInsideTheUnitSquare() {
        for p in SceneCanvas.patchOutline(PlotShape()) {
            XCTAssertTrue((0.0...1.0).contains(p.x) && (0.0...1.0).contains(p.y))
        }
    }

    func testRayAboveTheHorizonMisses() {
        // Pitched up a little, the horizon sits inside the frame: rays above it hit no ground, rays below it do.
        let cam = Camera(pitchDegrees: 20)
        XCTAssertGreaterThan(cam.horizonY, 0.03)
        XCTAssertLessThan(cam.horizonY, 0.5)
        XCTAssertNil(cam.groundPoint(atScreen: (x: 0.5, y: cam.horizonY - 0.02)))
        XCTAssertNotNil(cam.groundPoint(atScreen: (x: 0.5, y: cam.horizonY + 0.1)))
    }

    func testTapsOnThePatchHitTheRightGroundPoint() {
        // A tap at a plant's screen position gives back the plant's ground point, with the drifted camera.
        let cam = SceneMotion.camera(Camera(), frame: SceneMotion.Frame(time: 5, wind: 0.3, enabled: true))
        let target = GroundPoint(x: 0.31, y: 0.72)
        let q = cam.groundPoint(x: target.x, y: target.y)
        let hit = cam.groundPoint(atScreen: (x: q.x, y: q.y))
        XCTAssertEqual(hit?.x ?? -1, target.x, accuracy: 1e-9)
        XCTAssertEqual(hit?.y ?? -1, target.y, accuracy: 1e-9)
    }
}
