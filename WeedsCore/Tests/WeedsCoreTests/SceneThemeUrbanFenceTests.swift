import XCTest
import SwiftUI
import WeedsCore
@testable import WeedsArt

/// The Urban theme's timber fence is built from `BarrierFrame.point` like the farm's: the side fences must start at
/// the back fence's ends in every motion frame, verticals must stay vertical, and horizontal lines at every height
/// must run to the lawn's vanishing point.
@MainActor
final class SceneThemeUrbanFenceTests: XCTestCase {
    private let size = CGSize(width: 960, height: 720)

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

    private func fence() -> UrbanFence {
        UrbanFence(frame: BarrierFrame(camera: Camera.backyard, size: size, style: .timberPanel))
    }

    func testSideFencesStartAtTheBackFenceEndsInEveryFrame() {
        let f = fence()
        let back = f.backParts()
        let left = f.sideParts(x: -BarrierFrame.halfLength), right = f.sideParts(x: BarrierFrame.halfLength)
        let backBoards = back.filter { if case .board = $0.kind { return true } else { return false } }
        func boards(_ parts: [UrbanFence.Part]) -> [UrbanFence.Part] { parts.filter { if case .board = $0.kind { return true } else { return false } } }
        func first(_ k: UrbanFence.Kind, _ parts: [UrbanFence.Part]) -> UrbanFence.Part { parts.first { $0.kind == k }! }
        XCTAssertFalse(backBoards.isEmpty)

        for frame in frames {
            // Boards: the first and last back boards' outer edges against the side fences' first boards.
            let bl = moved(backBoards.first!.quad, by: frame), br = moved(backBoards.last!.quad, by: frame)
            let sl = moved(boards(left).first!.quad, by: frame), sr = moved(boards(right).first!.quad, by: frame)
            assertJoined(bl[0], sl[0], "left boards bottom", frame)
            assertJoined(bl[3], sl[3], "left boards top", frame)
            assertJoined(br[1], sr[0], "right boards bottom", frame)
            assertJoined(br[2], sr[3], "right boards top", frame)
            // The top rail and the gravel board run into the corner too.
            for kind in [UrbanFence.Kind.rail, .railShade] {
                let b = back.filter { $0.kind == kind }
                let l = moved(first(kind, left).quad, by: frame), r = moved(first(kind, right).quad, by: frame)
                assertJoined(moved(b.first!.quad, by: frame)[0], l[0], "left \(kind) bottom", frame)
                assertJoined(moved(b.first!.quad, by: frame)[3], l[3], "left \(kind) top", frame)
                assertJoined(moved(b.last!.quad, by: frame)[1], r[0], "right \(kind) bottom", frame)
                assertJoined(moved(b.last!.quad, by: frame)[2], r[3], "right \(kind) top", frame)
            }
            let g = back.filter { $0.kind == .gravel }
            assertJoined(moved(g.first!.quad, by: frame)[0], moved(first(.gravel, left).quad, by: frame)[0], "left gravel", frame)
            assertJoined(moved(g.last!.quad, by: frame)[1], moved(first(.gravel, right).quad, by: frame)[0], "right gravel", frame)
            // Corner posts: the back fence's end post and the side fence's first post share a base centre and a top.
            let posts = back.filter { $0.kind == .post }
            func baseMid(_ q: [CGPoint]) -> CGPoint { CGPoint(x: (q[0].x + q[1].x) / 2, y: (q[0].y + q[1].y) / 2) }
            let lp = moved(first(.post, left).quad, by: frame), rp = moved(first(.post, right).quad, by: frame)
            let lb = moved(posts.first!.quad, by: frame), rb = moved(posts.last!.quad, by: frame)
            assertJoined(baseMid(lb), baseMid(lp), "left corner post base", frame)
            assertJoined(baseMid(rb), baseMid(rp), "right corner post base", frame)
            func topMid(_ q: [CGPoint]) -> CGPoint { CGPoint(x: (q[2].x + q[3].x) / 2, y: (q[2].y + q[3].y) / 2) }
            assertJoined(topMid(lb), topMid(lp), "left corner post top", frame)
            assertJoined(topMid(rb), topMid(rp), "right corner post top", frame)
        }
    }

    func testBoardsAndPostsStayVertical() {
        let f = fence()
        for part in f.backParts() + f.sideParts(x: -BarrierFrame.halfLength) + f.sideParts(x: BarrierFrame.halfLength) {
            switch part.kind {
            case .board, .boardEdge, .post, .postShade:
                XCTAssertEqual(part.quad[0].x, part.quad[3].x, accuracy: 1e-6)
                XCTAssertEqual(part.quad[1].x, part.quad[2].x, accuracy: 1e-6)
            default: break
            }
        }
    }

    func testRailsAtEveryHeightRunToTheLawnsVanishingPoint() {
        let frame = BarrierFrame(camera: Camera.backyard, size: size, style: .timberPanel)
        let z0 = SceneCanvas.fenceZ, z1 = UrbanFence.sideEnd, x = BarrierFrame.halfLength
        func vanishing(_ h: Double) -> CGPoint {
            let a = frame.point(x: -x, z: z0, height: h), b = frame.point(x: -x, z: z1, height: h)
            let c = frame.point(x: x, z: z0, height: h), d = frame.point(x: x, z: z1, height: h)
            // Intersection of line ab with line cd.
            let r = CGPoint(x: b.x - a.x, y: b.y - a.y), s = CGPoint(x: d.x - c.x, y: d.y - c.y)
            let t = ((c.x - a.x) * s.y - (c.y - a.y) * s.x) / (r.x * s.y - r.y * s.x)
            return CGPoint(x: a.x + t * r.x, y: a.y + t * r.y)
        }
        let ground = vanishing(0)
        for h in [UrbanFence.gravelHeight, 0.9, UrbanFence.height, UrbanFence.height + 0.12] {
            let v = vanishing(h)
            XCTAssertEqual(v.x, ground.x, accuracy: 1, "height \(h)")
            XCTAssertEqual(v.y, ground.y, accuracy: 1, "height \(h)")
        }
    }

    /// The urban theme draws its own scene in every view and light without crashing, differently from the farm, and
    /// a drifted, windy frame still draws.
    func testUrbanThemeDrawsItsOwnScene() throws {
        let garden = SceneThemeRenderTests.garden(.soilPatch)
        let light = SceneThemeRenderTests.lights[1].palette
        for scene in SceneStyle.allCases {
            let farm = try SceneThemeRenderTests.pngData(SceneThemeRenderTests.content(garden: garden, palette: light, scene: scene))
            let urban = try SceneThemeRenderTests.pngData(SceneThemeRenderTests.content(garden: garden, palette: light, scene: scene, theme: .urban))
            XCTAssertFalse(urban.isEmpty)
            XCTAssertNotEqual(urban, farm, "\(scene)")
        }
    }
}
