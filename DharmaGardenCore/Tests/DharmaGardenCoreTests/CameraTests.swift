import XCTest
@testable import DharmaGardenCore

/// The garden camera in both framings: depth, horizon, drift, and that the whole plot is on screen.
final class CameraTests: XCTestCase {
    let framings: [(name: String, cam: Camera)] = [("first person", Camera()), ("backyard", Camera.backyard)]

    func testBackEdgeIsHigherAndSmallerThanFrontEdge() {
        for (name, cam) in framings {
            let back = cam.groundPoint(x: 0.5, y: 0.1), front = cam.groundPoint(x: 0.5, y: 0.9)
            XCTAssertLessThan(back.y, front.y, "\(name): back edge sits higher on screen")
            XCTAssertLessThan(back.scale, front.scale, "\(name): back edge is smaller")
        }
    }

    func testBackToFrontScaleRatioIsAboutPointFiveFiveForFirstPerson() {
        // The depth range of the old 4-unit grid (z from -1.5 to 1.5) keeps the first-person ratio near 0.55.
        let ratio = Camera().project(x: 0, z: -1.5).scale / Camera().project(x: 0, z: 1.5).scale
        XCTAssertEqual(ratio, 0.55, accuracy: 0.03)
    }

    func testHorizonIsAboveTheGardenAtDefaultPitch() {
        for (name, cam) in framings {
            XCTAssertLessThan(cam.horizonY, cam.groundPoint(x: 0.5, y: 0).y, "\(name)")
        }
    }

    func testDriftOffsetsMoveTheView() {
        let cam = Camera()
        var drifted = cam
        drifted.offset = (x: 0.2, y: 0)
        XCTAssertNotEqual(drifted.groundPoint(x: 0.5, y: 0.5).x, cam.groundPoint(x: 0.5, y: 0.5).x)
        var tilted = cam
        tilted.pitchOffsetDegrees = 2
        XCTAssertNotEqual(tilted.horizonY, cam.horizonY, "a pitch drift moves the horizon")
    }

    func testBackyardIsPitchedAboveFirstPersonAndPulledBack() {
        XCTAssertEqual(Camera.backyard.pitchDegrees, 34, accuracy: 0.5)
        XCTAssertGreaterThan(Camera.backyard.distance, Camera().distance, "pulled back")
        XCTAssertGreaterThan(Camera.backyard.eyeHeight, Camera().eyeHeight, "higher")
        XCTAssertLessThan(Camera.backyard.horizonY, 0.3, "the back of the yard shows the sky above the fence")
    }

    /// Every point of the plot (the soil) is inside the frame, in both framings.
    func testWholePlotFitsTheFrame() {
        let plot = PlotShape()
        for (name, cam) in framings {
            for i in 0...50 {
                for j in 0...50 {
                    let p = GroundPoint(x: Double(i) / 50, y: Double(j) / 50)
                    guard plot.contains(p) else { continue }
                    let q = cam.groundPoint(x: p.x, y: p.y)
                    XCTAssertTrue((0.0...1.0).contains(q.x), "\(name): plot x \(q.x) off screen at \(p)")
                    XCTAssertTrue((0.0...1.0).contains(q.y), "\(name): plot y \(q.y) off screen at \(p)")
                }
            }
        }
    }
}
