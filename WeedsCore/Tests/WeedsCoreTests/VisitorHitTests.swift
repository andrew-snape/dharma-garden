import XCTest
import SwiftUI
@testable import WeedsCore
@testable import WeedsArt

/// Tap hit testing for visitors: a press on a visitor's body spots it, and the nearest visitor wins.
final class VisitorHitTests: XCTestCase {
    static let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    let size = CGSize(width: 960, height: 720)
    let camera = Camera()
    let garden = Garden(now: t0)

    /// A visitor standing in the middle of its stay, with its pose at that time.
    func staying(_ s: VisitorSpecies, id: Int, at p: GroundPoint) -> SceneContent.SceneVisitor {
        let v = Visitor(id: id, species: s, position: p, spawnedAt: Self.t0, lifetime: 40)
        return SceneContent.SceneVisitor(visitor: v, pose: VisitorMotion.pose(of: v, at: Self.t0.addingTimeInterval(20)))
    }

    /// Where a visitor's feet are drawn, in points.
    func feet(_ v: SceneContent.SceneVisitor) -> CGPoint {
        SceneContent.visitorFrame(v, garden: garden, size: size, camera: camera).feet
    }

    func hit(_ point: CGPoint, _ visitors: [SceneContent.SceneVisitor]) -> Visitor? {
        SceneContent.visitor(at: point, size: size, visitors: visitors, garden: garden, camera: camera)
    }

    func testPressOnAVisitorSpotsIt() {
        let bee = staying(.bee, id: 1, at: GroundPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(hit(feet(bee), [bee])?.id, 1)
    }

    func testPressAwayFromVisitorsMisses() {
        let snail = staying(.snail, id: 2, at: GroundPoint(x: 0.5, y: 0.5))
        let f = feet(snail)
        XCTAssertNil(hit(CGPoint(x: f.x + 200, y: f.y), [snail]))
        XCTAssertNil(hit(CGPoint(x: f.x, y: f.y - 300), [snail]))
        XCTAssertNil(hit(f, []), "no visitors, no hit")
    }

    func testNearestVisitorWins() {
        // Two lizards side by side, a little apart: a press on the left one's feet is nearer to it.
        let left = staying(.blueTongueLizard, id: 3, at: GroundPoint(x: 0.5, y: 0.5))
        let right = staying(.blueTongueLizard, id: 4, at: GroundPoint(x: 0.52, y: 0.5))
        let both = [left, right]
        XCTAssertEqual(hit(feet(left), both)?.id, 3)
        XCTAssertEqual(hit(feet(right), both)?.id, 4)
    }

    func testRadiusIsAtLeastFortyPoints() {
        let frog = staying(.frog, id: 5, at: GroundPoint(x: 0.5, y: 0.5))
        let f = feet(frog)
        XCTAssertEqual(hit(CGPoint(x: f.x + 30, y: f.y), [frog])?.id, 5)
        XCTAssertNil(hit(CGPoint(x: f.x + 120, y: f.y), [frog]))
    }
}
