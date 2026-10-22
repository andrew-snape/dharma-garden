import XCTest
import SwiftUI
import WeedsCore
@testable import WeedsArt

/// The Rural UK dry-stone wall is built from `BarrierFrame.point` in `UKWall`. Its side walls must start exactly where
/// the back wall ends and its corner pillars must cover that join, in every motion frame (the fence layer moves as one
/// piece). Also: verticals stay vertical, lines toward the viewer meet one vanishing point, and the ambient touches
/// are capped and deterministic.
@MainActor
final class SceneThemeUKWallTests: XCTestCase {
    private let size = CGSize(width: 960, height: 720)

    /// Still, and drifted frames at several times and winds.
    private var frames: [SceneMotion.Frame] {
        [SceneMotion.Frame.still] + [0.0, 4.2, 9.7, 15.3, 21.8, 27.1].flatMap { t in
            [0.0, 1.0].map { SceneMotion.Frame(time: t, wind: $0, enabled: true) }
        }
    }

    private func moved(_ pts: [CGPoint], by frame: SceneMotion.Frame) -> [CGPoint] {
        let s = frame.layerShift(.fence)
        return pts.map { CGPoint(x: $0.x + CGFloat(s.x) * size.width, y: $0.y + CGFloat(s.y) * size.height) }
    }

    private func assertJoined(_ a: CGPoint, _ b: CGPoint, _ what: String, _ frame: SceneMotion.Frame,
                              file: StaticString = #filePath, line: UInt = #line) {
        let d = hypot(a.x - b.x, a.y - b.y)
        XCTAssertLessThanOrEqual(d, 1, "\(what) is \(d) px apart at time \(frame.time), wind \(frame.wind)", file: file, line: line)
    }

    func testSideWallsStartAtTheBackWallEndsInEveryFrame() {
        let wall = UKWall(camera: .backyard, size: size)
        let back = wall.backFace().quad(top: UKWall.height)
        for frame in frames {
            let b = moved(back, by: frame)
            for (sign, end) in [(-1.0, (bottom: 0, top: 3)), (1.0, (bottom: 1, top: 2))] {
                let side = moved(wall.sideFace(x: sign * wall.halfLength).quad(top: UKWall.height), by: frame)
                // The side face's near-the-back edge is bottom left / top left; the back face's end edge is its own end.
                assertJoined(b[end.bottom], side[0], "side wall \(sign) bottom", frame)
                assertJoined(b[end.top], side[3], "side wall \(sign) top", frame)
                // The pillar stands over the join: both edges of its front face straddle the corner, and its inner
                // face spans the back wall's depth.
                let pillar = wall.pillar(sign: sign)
                let front = moved(pillar.front.quad(top: UKWall.pillarHeight), by: frame)
                let corner = b[end.bottom]
                XCTAssertLessThan(min(front[0].x, front[1].x), corner.x, "pillar \(sign) covers the corner at time \(frame.time)")
                XCTAssertGreaterThan(max(front[0].x, front[1].x), corner.x, "pillar \(sign) covers the corner at time \(frame.time)")
                XCTAssertLessThan(pillar.zBack, wall.backZ)
                XCTAssertGreaterThan(pillar.zFront, wall.backZ)
                XCTAssertGreaterThan(pillar.front.quad(top: UKWall.pillarHeight)[3].y, -size.height)
            }
        }
    }

    func testJoinIsSymmetricAndSideWallsConverge() {
        let wall = UKWall(camera: .backyard, size: size)
        let back = wall.backFace().quad(top: UKWall.height)
        let left = wall.sideFace(x: -wall.halfLength).quad(top: UKWall.height)
        let right = wall.sideFace(x: wall.halfLength).quad(top: UKWall.height)
        // Mirror images about the centre line of the scene.
        XCTAssertEqual(back[0].x + back[1].x, size.width, accuracy: 1)
        XCTAssertEqual(left[0].x + right[0].x, size.width, accuracy: 1)
        XCTAssertEqual(left[0].y, right[0].y, accuracy: 0.001)
        XCTAssertEqual(left[3].y, right[3].y, accuracy: 0.001)
        // Nearer ends sit further out, so the side walls spread toward the viewer.
        XCTAssertLessThan(left[1].x, left[0].x)
        XCTAssertGreaterThan(right[1].x, right[0].x)
        // The back wall's left and right pillars are mirrors too.
        let pl = wall.pillar(sign: -1).front.quad(top: UKWall.pillarHeight)
        let pr = wall.pillar(sign: 1).front.quad(top: UKWall.pillarHeight)
        XCTAssertEqual(pl[0].x + pr[1].x, size.width, accuracy: 1)
    }

    func testVerticalsAreVerticalAndLinesMeetOneVanishingPoint() {
        let wall = UKWall(camera: .backyard, size: size)
        for face in [wall.backFace(), wall.sideFace(x: -wall.halfLength), wall.sideFace(x: wall.halfLength),
                     wall.pillar(sign: 1).front, wall.pillar(sign: -1).side] {
            let q = face.quad(top: UKWall.height)
            XCTAssertEqual(q[0].x, q[3].x, accuracy: 0.001)
            XCTAssertEqual(q[1].x, q[2].x, accuracy: 0.001)
        }
        // Bottom and top edges of both side walls run to the lawn's vanishing point.
        func meet(_ a: (CGPoint, CGPoint), _ b: (CGPoint, CGPoint)) -> CGPoint? {
            let d1 = CGPoint(x: a.1.x - a.0.x, y: a.1.y - a.0.y), d2 = CGPoint(x: b.1.x - b.0.x, y: b.1.y - b.0.y)
            let den = d1.x * d2.y - d1.y * d2.x
            guard abs(den) > 1e-9 else { return nil }
            let t = ((b.0.x - a.0.x) * d2.y - (b.0.y - a.0.y) * d2.x) / den
            return CGPoint(x: a.0.x + t * d1.x, y: a.0.y + t * d1.y)
        }
        let l = wall.sideFace(x: -wall.halfLength).quad(top: UKWall.height)
        let r = wall.sideFace(x: wall.halfLength).quad(top: UKWall.height)
        let points = [meet((l[0], l[1]), (r[0], r[1])), meet((l[3], l[2]), (r[3], r[2])), meet((l[0], l[1]), (l[3], l[2]))]
        let first = points[0]!
        for p in points {
            let v = try? XCTUnwrap(p)
            XCTAssertEqual(v?.x ?? 0, first.x, accuracy: 1)
            XCTAssertEqual(v?.y ?? 0, first.y, accuracy: 1)
        }
        // And it is the vanishing point of the lawn's own edge lines (a point far down the yard).
        let cam = Camera.backyard
        let far = cam.project(x: 0, z: -1e7)
        XCTAssertEqual(first.x, CGFloat(far.x) * size.width, accuracy: 2)
        XCTAssertEqual(first.y, CGFloat(far.y) * size.height, accuracy: 2)
    }

    func testGateSitsInTheBackWallClearOfTheEnds() {
        let wall = UKWall(camera: .backyard, size: size)
        let gap = wall.gap()
        XCTAssertGreaterThan(gap.lowerBound, -wall.halfLength + 1)
        XCTAssertLessThan(gap.upperBound, wall.halfLength - 1)
        for spot in SceneCanvas.ukRobinSpots {
            XCTAssertFalse(gap.contains(spot), "robin spot \(spot) must not be on the gate")
            XCTAssertLessThan(abs(spot), wall.halfLength - UKWall.pillarInset)
        }
    }

    // MARK: Ambient and rendering

    func testAmbientIsCapped() {
        XCTAssertLessThanOrEqual(SceneCanvas.ukSmokePuffs, 8)
        XCTAssertGreaterThan(SceneCanvas.ukRobinPeriod * SceneCanvas.ukRobinStay.lowerBound, 1)
        XCTAssertLessThan(SceneCanvas.ukRobinStay.upperBound, 1)
    }

    private func render(_ motion: SceneMotion.Frame, scene: SceneStyle, theme: SceneTheme) throws -> Data {
        let garden = SceneThemeRenderTests.garden(.soilPatch)
        let palette = SceneThemeRenderTests.lights[0].palette
        let camera: Camera = scene == .backyard ? .backyard : Camera()
        let view = SceneContent(garden: garden, palette: palette, camera: camera, motion: motion, style: scene, theme: theme)
            .frame(width: 480, height: 360)
        let r = ImageRenderer(content: view)
        r.scale = 1
        let img = try XCTUnwrap(r.nsImage)
        let tiff = try XCTUnwrap(img.tiffRepresentation)
        return try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }

    /// The theme renders both views, differs from the farm, and moves when time moves (smoke, robin, clouds).
    func testUKRendersBothViewsAndAnimates() throws {
        for scene in SceneStyle.allCases {
            let uk = try render(SceneThemeRenderTests.motion, scene: scene, theme: .ruralUK)
            let farm = try render(SceneThemeRenderTests.motion, scene: scene, theme: .farm)
            XCTAssertNotEqual(uk, farm, "\(scene) looks like the farm")
            let later = try render(SceneMotion.Frame(time: 40, wind: 0.25, enabled: true), scene: scene, theme: .ruralUK)
            XCTAssertNotEqual(uk, later, "\(scene) does not animate")
        }
    }
}
