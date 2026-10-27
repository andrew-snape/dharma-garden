import SwiftUI
import DharmaGardenCore

/// The Japanese theme's earthen wall with a tiled cap (tsuijigaki), across the back and, in the backyard, along both
/// sides to a corner pillar at each end. Every corner comes from `BarrierFrame.point`, the shared upright projection,
/// so verticals stay vertical and every line along z runs to the lawn's vanishing point. The side walls start
/// exactly at the back wall's ends, and the pillars stand on the joins and hide the cap ends.
struct JapaneseWall {
    let frame: BarrierFrame

    init(camera: Camera, size: CGSize) {
        frame = BarrierFrame(camera: camera, size: size, style: .earthWall)
    }

    /// Wall heights in world units: a darker foot, the plaster body, the eave line of the cap, and its ridge.
    static let footHeight = 0.2
    static let eaveHeight = 0.78
    static let ridgeHeight = 1.14
    /// How far the cap's eave reaches out from the wall's centre line, toward the yard.
    static let eaveReach = 0.14
    /// Half the width of a corner pillar, and its height (the tiled hat sits on top).
    static let pillarHalf = 0.17
    static let pillarHeight = 1.32
    /// The side walls stop here, short of the camera at z = 4 (as the rail fence does).
    static let sideEnd = 2.9

    /// One straight stretch of wall from `a` to `b` on the ground; `eave` is the offset of the cap's eave line from
    /// the wall's centre line (it points into the yard).
    struct Run {
        let a: (x: Double, z: Double)
        let b: (x: Double, z: Double)
        let eave: (x: Double, z: Double)
        var length: Double { hypot(b.x - a.x, b.z - a.z) }
    }

    /// The back wall, from x = -halfLength to halfLength along z = fenceZ.
    var back: Run {
        let h = BarrierFrame.halfLength, z = SceneCanvas.fenceZ
        return Run(a: (-h, z), b: (h, z), eave: (0, Self.eaveReach))
    }

    /// The side wall at x, from the back wall's end toward the viewer.
    func side(x: Double) -> Run {
        Run(a: (x, SceneCanvas.fenceZ), b: (x, Self.sideEnd), eave: (x < 0 ? Self.eaveReach : -Self.eaveReach, 0))
    }

    /// Canvas point at fraction `t` along the run, at `height`, `k` of the way from the centre line to the eave.
    func point(_ r: Run, _ t: Double, _ height: Double, eave k: Double = 0) -> CGPoint {
        frame.point(x: r.a.x + (r.b.x - r.a.x) * t + r.eave.x * k,
                    z: r.a.z + (r.b.z - r.a.z) * t + r.eave.z * k, height: height)
    }

    /// The plaster body from the ground to the eave line: bottom start, bottom end, top end, top start.
    func body(_ r: Run) -> [CGPoint] {
        [point(r, 0, 0), point(r, 1, 0), point(r, 1, Self.eaveHeight), point(r, 0, Self.eaveHeight)]
    }

    /// The tiled cap's sloped face: eave start, eave end, ridge end, ridge start.
    func cap(_ r: Run) -> [CGPoint] {
        [point(r, 0, Self.eaveHeight, eave: 1), point(r, 1, Self.eaveHeight, eave: 1),
         point(r, 1, Self.ridgeHeight), point(r, 0, Self.ridgeHeight)]
    }
}

/// Wall and tile colours, shared by the wall and the tea house.
enum JapaneseWallColour {
    static let plaster = Color(hex: 0xE4D9BF), plasterShade = Color(hex: 0xC6B898), plasterLight = Color(hex: 0xF1EAD6)
    static let foot = Color(hex: 0x9A8A70), footShade = Color(hex: 0x7C6E58)
    static let tile = Color(hex: 0x626C78), tileLight = Color(hex: 0x8791A0), tileDark = Color(hex: 0x424A56)
    static let wood = Color(hex: 0x7A5638), woodShade = Color(hex: 0x5A3E28)
}

extension SceneCanvas {
    /// The back wall, then (in the backyard) the stone lantern and the bamboo spout that stand in front of it. In
    /// first person the end pillars still stand at the wall's ends.
    func drawJapaneseBarrier() {
        let wall = JapaneseWall(camera: camera, size: size)
        drawJapaneseRun(wall.back, wall: wall, seed: 11)
        if style == .backyard { drawJapaneseWallProps() }
        for x in [-BarrierFrame.halfLength, BarrierFrame.halfLength] { drawJapanesePillar(x: x, wall: wall) }
    }

    /// The side walls, each ending in the corner pillar that is drawn again on top, so the pillar covers the join.
    func drawJapaneseSideWalls() {
        let wall = JapaneseWall(camera: camera, size: size)
        for x in [-BarrierFrame.halfLength, BarrierFrame.halfLength] {
            drawJapaneseRun(wall.side(x: x), wall: wall, seed: x < 0 ? 23 : 37)
            drawJapanesePillar(x: x, wall: wall)
        }
    }

    /// One stretch of wall: contact shadow, foot, plaster with bands and weathering, then the tiled cap.
    private func drawJapaneseRun(_ r: JapaneseWall.Run, wall w: JapaneseWall, seed: UInt64) {
        typealias W = JapaneseWallColour
        let low = JapaneseWall.footHeight, eave = JapaneseWall.eaveHeight, ridge = JapaneseWall.ridgeHeight
        let a0 = w.point(r, 0, 0), a1 = w.point(r, 1, 0)
        // Canvas points per world unit along the run: the scale that spots and tiles follow.
        let perUnit = hypot(a1.x - a0.x, a1.y - a0.y) / CGFloat(r.length)

        // Soft shadow on the ground in front of the wall.
        fill([w.point(r, 0, 0), w.point(r, 1, 0), w.point(r, 1, 0, eave: 3), w.point(r, 0, 0, eave: 3)],
             Color.black.opacity(0.12 * wallShadowShare()))

        // Foot and plaster body.
        fill([w.point(r, 0, 0), w.point(r, 1, 0), w.point(r, 1, low), w.point(r, 0, low)], W.foot)
        fill([w.point(r, 0, 0), w.point(r, 1, 0), w.point(r, 1, 0.035), w.point(r, 0, 0.035)], W.footShade)
        fill([w.point(r, 0, low), w.point(r, 1, low), w.point(r, 1, eave), w.point(r, 0, eave)], W.plaster)
        fill([w.point(r, 0, low), w.point(r, 1, low), w.point(r, 1, low + 0.03), w.point(r, 0, low + 0.03)], W.plasterShade)

        // Horizontal plaster bands (the layered earth shows as fine lines), each with a pale lip above it.
        for h in [0.36, 0.5, 0.64] {
            fill([w.point(r, 0, h), w.point(r, 1, h), w.point(r, 1, h + 0.022), w.point(r, 0, h + 0.022)], W.plasterShade)
            fill([w.point(r, 0, h + 0.022), w.point(r, 1, h + 0.022), w.point(r, 1, h + 0.036), w.point(r, 0, h + 0.036)],
                 W.plasterLight)
        }

        // Plaster texture: soft mottles, a few patches where the earth shows through, and streaks below the cap.
        let spots = Int(r.length * 2.2) + 4
        for i in 0..<spots {
            let t = unitHash(seed, UInt64(i * 4)), h = low + 0.06 + (eave - low - 0.14) * unitHash(seed, UInt64(i * 4 + 1))
            let c = w.point(r, t, h)
            let rw = CGFloat(0.06 + 0.1 * unitHash(seed, UInt64(i * 4 + 2))) * perUnit
            let bare = unitHash(seed, UInt64(i * 4 + 3)) < 0.2
            ellipse(c, rw * 2, max(2, rw * 0.7), bare ? W.foot.opacity(0.5) : W.plasterShade.opacity(0.4))
        }
        for i in 0..<Int(r.length * 1.4) + 3 {
            let t = unitHash(seed &+ 5, UInt64(i * 2)), len = 0.08 + 0.14 * unitHash(seed &+ 5, UInt64(i * 2 + 1))
            stroke([w.point(r, t, eave - 0.02), w.point(r, t, eave - 0.02 - len)], width: 1.2, W.plasterShade.opacity(0.55))
        }
        // The cap's shade on the top of the wall.
        fill([w.point(r, 0, eave - 0.1), w.point(r, 1, eave - 0.1), w.point(r, 1, eave), w.point(r, 0, eave)],
             W.plasterShade.opacity(0.8))

        // The tiled cap: a shade copy nudged down, the slope, then convex tile strips with round eave ends.
        let slope = w.cap(r)
        fill(slope.map { CGPoint(x: $0.x, y: $0.y + 2.5) }, W.tileDark)
        fill(slope, W.tile)
        let tiles = max(2, Int(r.length / 0.14))
        for i in 0..<tiles {
            let t0 = (Double(i) + 0.22) / Double(tiles), t1 = (Double(i) + 0.78) / Double(tiles)
            fill([w.point(r, t0, eave + 0.01, eave: 1), w.point(r, t1, eave + 0.01, eave: 1),
                  w.point(r, t1, ridge - 0.01, eave: 0.06), w.point(r, t0, ridge - 0.01, eave: 0.06)], W.tileLight.opacity(0.5))
            let tm = (Double(i) + 0.5) / Double(tiles)
            stroke([w.point(r, tm, eave + 0.01, eave: 1), w.point(r, tm, ridge - 0.01, eave: 0.06)], width: 1,
                   W.tileDark.opacity(0.7))
        }
        stroke([w.point(r, 0, eave, eave: 1), w.point(r, 1, eave, eave: 1)], width: 2, W.tileDark)
        // Round tile ends along the eave.
        for i in 0..<tiles {
            let tm = (Double(i) + 0.5) / Double(tiles)
            let c = w.point(r, tm, eave - 0.012, eave: 1)
            let uw = w.frame.unitWidth(x: r.a.x + (r.b.x - r.a.x) * tm + r.eave.x, z: r.a.z + (r.b.z - r.a.z) * tm + r.eave.z)
            let d = min(0.085 * uw, 0.8 * 0.14 * perUnit)
            ellipse(CGPoint(x: c.x, y: c.y + 1), d, d * 0.9, W.tileDark)
            ellipse(c, d * 0.8, d * 0.72, W.tileLight)
        }
        // The ridge: a thick rounded line.
        let ridgeLine = [w.point(r, 0, ridge), w.point(r, 1, ridge)]
        stroke(ridgeLine.map { CGPoint(x: $0.x, y: $0.y + 1.5) }, width: 4.2, W.tileDark)
        stroke(ridgeLine, width: 3.4, W.tileLight)
    }

    /// A square corner pillar of plaster with a timber band and a small hipped tile hat, standing on the wall join
    /// at x. Two faces show: the front and the one that looks into the yard.
    func drawJapanesePillar(x: Double, wall w: JapaneseWall) {
        typealias W = JapaneseWallColour
        let p = JapaneseWall.pillarHalf, height = JapaneseWall.pillarHeight, z0 = SceneCanvas.fenceZ
        let inner = x < 0 ? x + p : x - p, outer = x < 0 ? x - p : x + p
        func P(_ px: Double, _ pz: Double, _ h: Double) -> CGPoint { w.frame.point(x: px, z: pz, height: h) }
        // Shadow on the ground.
        fill([P(outer, z0 + p, 0), P(inner, z0 + p, 0), P(inner + (x < 0 ? 0.3 : -0.3), z0 + p + 0.3, 0), P(outer, z0 + p + 0.3, 0)],
             Color.black.opacity(0.12 * wallShadowShare()))
        // Inner face (looks into the yard), then the front face.
        let innerFace = [P(inner, z0 - p, 0), P(inner, z0 + p, 0), P(inner, z0 + p, height), P(inner, z0 - p, height)]
        fill(innerFace, W.plasterShade)
        let front = [P(outer, z0 + p, 0), P(inner, z0 + p, 0), P(inner, z0 + p, height), P(outer, z0 + p, height)]
        fill(front, W.plaster)
        fill([P(outer, z0 + p, 0), P(inner, z0 + p, 0), P(inner, z0 + p, 0.12), P(outer, z0 + p, 0.12)], W.foot)
        // Weathering on the front face.
        for (dx, h, len) in [(0.3, 0.9, 0.2), (0.7, 0.8, 0.14)] {
            let px = outer + (inner - outer) * dx
            stroke([P(px, z0 + p, h), P(px, z0 + p, h - len)], width: 1.2, W.plasterShade.opacity(0.6))
        }
        // Timber band under the hat, on both faces.
        let band0 = height - 0.1
        fill([P(outer, z0 + p, band0), P(inner, z0 + p, band0), P(inner, z0 + p, height), P(outer, z0 + p, height)], W.wood)
        fill([P(inner, z0 - p, band0), P(inner, z0 + p, band0), P(inner, z0 + p, height), P(inner, z0 - p, height)], W.woodShade)
        // The hat: a four-sided tile pyramid with a round finial. The base is wider than the pillar.
        let q = p + 0.08, top = height + 0.27, apex = P(x, z0, top)
        let frontHat = [P(x - q, z0 + q, height), P(x + q, z0 + q, height), apex]
        let sideHat = [P(inner + (x < 0 ? 0.08 : -0.08), z0 + q, height), P(inner + (x < 0 ? 0.08 : -0.08), z0 - q, height), apex]
        fill(sideHat.map { CGPoint(x: $0.x, y: $0.y + 2) }, W.tileDark)
        fill(sideHat, W.tileDark)
        fill(frontHat.map { CGPoint(x: $0.x, y: $0.y + 2) }, W.tileDark)
        fill(frontHat, W.tile)
        for k in 1..<5 {
            let t = Double(k) / 5
            let a = CGPoint(x: frontHat[0].x + (frontHat[1].x - frontHat[0].x) * t, y: frontHat[0].y)
            stroke([a, apex], width: 1, W.tileDark.opacity(0.7))
        }
        stroke([frontHat[0], frontHat[1]], width: 2, W.tileDark)
        let finial = P(x, z0, top + 0.03)
        let s = w.frame.unitWidth(x: x, z: z0)
        ellipse(finial, 0.1 * s, 0.1 * s, W.tileLight)
    }
}
