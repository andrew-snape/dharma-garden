import SwiftUI
import DharmaGardenCore

/// The dry-stone wall's geometry, built from `BarrierFrame.point` so it uses the shared upright projection: verticals
/// stay vertical and every line running toward the viewer meets the lawn's vanishing point. The back wall runs along
/// z = `SceneCanvas.fenceZ` from x = -halfLength to halfLength, with a timber gate set in it. The side walls run along
/// x = +-halfLength from the back wall's ends to z = `sideEnd`. Each is a face (the side you see) with a flat top
/// that goes back (or out) by `thickness`, and a stone pillar stands at each corner so the walls meet cleanly.
struct UKWall {
    let frame: BarrierFrame

    static let height = 0.9
    static let thickness = 0.34
    static let pillarHeight = 1.25
    /// How far the pillar stands proud of the wall faces, and past them on the outside, in world units.
    static let pillarInset = 0.15, pillarOutset = 0.05
    static let gateX = 0.0, gateHalfWidth = 0.62
    static let sideEnd = 2.9   // stops short of the camera, which sits at z = 4

    var halfLength: Double { BarrierFrame.halfLength }
    var backZ: Double { SceneCanvas.fenceZ }

    init(camera: Camera, size: CGSize) {
        frame = BarrierFrame(camera: camera, size: size, style: .dryStoneWall)
    }

    /// A flat side of the wall or a pillar: `map` takes a position along it (u) and a height (v) to a canvas point.
    struct Face {
        let u0: Double, u1: Double
        let map: (Double, Double) -> CGPoint

        /// The face's outline for heights 0...top: bottom left, bottom right, top right, top left.
        func quad(top: Double) -> [CGPoint] { [map(u0, 0), map(u1, 0), map(u1, top), map(u0, top)] }
    }

    /// The back wall's face, along x at the front plane z = fenceZ.
    func backFace() -> Face {
        Face(u0: -halfLength, u1: halfLength) { u, v in frame.point(x: u, z: backZ, height: v) }
    }

    /// A side wall's face at x = +-halfLength, along z from the back wall toward the viewer.
    func sideFace(x: Double) -> Face {
        Face(u0: backZ, u1: Self.sideEnd) { u, v in frame.point(x: x, z: u, height: v) }
    }

    /// The corner pillar at the back wall's end on side `sign` (-1 left, +1 right): its front face, its inner side
    /// face (the one that looks into the yard) and the footprint it covers in world units.
    struct Pillar {
        let front: Face, side: Face
        let xInner: Double, xOuter: Double, zFront: Double, zBack: Double
    }

    func pillar(sign: Double) -> Pillar {
        let xInner = sign * (halfLength - Self.pillarInset)
        let xOuter = sign * (halfLength + Self.thickness + Self.pillarOutset)
        let zFront = backZ + Self.pillarInset, zBack = backZ - Self.thickness - Self.pillarOutset
        let lo = min(xInner, xOuter), hi = max(xInner, xOuter)
        return Pillar(front: Face(u0: lo, u1: hi) { u, v in frame.point(x: u, z: zFront, height: v) },
                      side: Face(u0: zBack, u1: zFront) { u, v in frame.point(x: xInner, z: u, height: v) },
                      xInner: xInner, xOuter: xOuter, zFront: zFront, zBack: zBack)
    }

    func gap() -> ClosedRange<Double> { (Self.gateX - Self.gateHalfWidth)...(Self.gateX + Self.gateHalfWidth) }
}

extension SceneCanvas {
    private func ukH(_ seed: UInt64, _ i: Int) -> Double { unitHash(seed, UInt64(truncatingIfNeeded: i)) }

    // MARK: Hooks

    func ukDrawBarrier() {
        let wall = UKWall(camera: camera, size: size)
        ukDrawVerge(wall)
        let back = wall.backFace()
        ukDrawStoneFace(back, top: UKWall.height, seed: 0xA11, tone: 0, skip: wall.gap())
        ukDrawWallTop(wall, face: back, seed: 0xA12, skip: wall.gap(), side: nil)
        ukDrawGate(wall)
        ukDrawWallBase(wall, face: back, seed: 0xA13, skip: wall.gap())
        // First person has no side walls, so the back wall ends in its two pillars. (The backyard's come with the sides.)
        if style == .firstPerson {
            for (n, sign) in [-1.0, 1.0].enumerated() { ukDrawPillar(wall, sign: sign, seed: 0xC40 + UInt64(n)) }
        }
    }

    func ukDrawSideWalls() {
        let wall = UKWall(camera: camera, size: size)
        for (n, sign) in [-1.0, 1.0].enumerated() {
            let x = sign * wall.halfLength
            let face = wall.sideFace(x: x)
            ukDrawStoneFace(face, top: UKWall.height, seed: 0xB10 + UInt64(n), tone: 0.14, skip: nil)
            ukDrawWallTop(wall, face: face, seed: 0xB20 + UInt64(n), skip: nil, side: sign)
            ukDrawWallBase(wall, face: face, seed: 0xB30 + UInt64(n), skip: nil)
        }
        // The corner pillars last, over both walls' ends.
        for (n, sign) in [-1.0, 1.0].enumerated() { ukDrawPillar(wall, sign: sign, seed: 0xC40 + UInt64(n)) }
    }

    // MARK: Pieces

    /// A strip of verge in front of the wall's foot: it hides the seam between the lawn and the wall under camera
    /// drift, and puts a soft shadow where the wall meets the grass.
    private func ukDrawVerge(_ wall: UKWall) {
        let h = wall.halfLength, z = wall.backZ
        let f = wall.frame
        let verge = SceneColour.color(SceneColour.scaled(ukGrass(), 0.93))
        fill([f.point(x: -h, z: z - 0.02), f.point(x: h, z: z - 0.02), f.point(x: h, z: z + 0.2), f.point(x: -h, z: z + 0.2)], verge)
        let shadow = Color(hex: 0x1B2A14).opacity(0.16)
        fill([f.point(x: -h, z: z), f.point(x: h, z: z), f.point(x: h, z: z + 0.1), f.point(x: -h, z: z + 0.1)], shadow)
    }

    /// A face of irregular stones laid in rough courses, with dark gaps between them and no mortar. `skip` leaves a
    /// range along the face open (the gate). `tone` darkens the stones toward the shade (faces turned from the light).
    private func ukDrawStoneFace(_ f: UKWall.Face, top: Double, seed: UInt64, tone: Double, skip: ClosedRange<Double>?) {
        let gapColour = mix(0x5E574E, 0x2A2622, tone)
        // The dark backing the gaps show.
        if let s = skip {
            fill([f.map(f.u0, 0), f.map(s.lowerBound, 0), f.map(s.lowerBound, top), f.map(f.u0, top)], gapColour)
            fill([f.map(s.upperBound, 0), f.map(f.u1, 0), f.map(f.u1, top), f.map(s.upperBound, top)], gapColour)
        } else {
            fill(f.quad(top: top), gapColour)
        }
        var v = 0.0, row = 0
        while v < top - 0.02 {
            let v1 = min(top, v + 0.13 + 0.07 * ukH(seed, row * 7))
            var u = f.u0 - 0.35 * ukH(seed ^ 0x55, row)
            var n = 0
            while u < f.u1 {
                let w = 0.26 + 0.34 * ukH(seed ^ 0x77, row * 64 + n)
                var segs = [(max(u, f.u0), min(u + w, f.u1))]
                if let s = skip {
                    let (a, b) = segs[0]
                    segs = []
                    if b <= s.lowerBound || a >= s.upperBound { segs = [(a, b)] } else {
                        if s.lowerBound - a > 0.05 { segs.append((a, s.lowerBound)) }
                        if b - s.upperBound > 0.05 { segs.append((s.upperBound, b)) }
                    }
                }
                for (k, seg) in segs.enumerated() where seg.1 - seg.0 > 0.05 {
                    ukDrawStone(f, a: seg.0, b: seg.1, v0: v, v1: v1, seed: seed, id: row * 64 + n + k * 1000, tone: tone)
                }
                u += w
                n += 1
            }
            v = v1
            row += 1
        }
    }

    private func ukDrawStone(_ f: UKWall.Face, a: Double, b: Double, v0: Double, v1: Double,
                             seed: UInt64, id: Int, tone: Double) {
        let g = 0.012
        func j(_ k: Int, _ amount: Double) -> Double { (ukH(seed ^ 0x99, id * 8 + k) - 0.5) * amount }
        let c = 0.02 + 0.035 * ukH(seed ^ 0xAA, id)
        let u0 = a + g, u1 = b - g, w0 = v0 + g, w1 = v1 - g
        let pts = [
            f.map(u0 + c, w0 + j(0, 0.01)), f.map(u1 - c, w0 + j(1, 0.01)), f.map(u1 + j(2, 0.01), w0 + c),
            f.map(u1 + j(3, 0.01), w1 - c), f.map(u1 - c, w1 + j(4, 0.02)), f.map(u0 + c, w1 + j(5, 0.02)),
            f.map(u0 + j(6, 0.01), w1 - c), f.map(u0 + j(7, 0.01), w0 + c),
        ]
        let hex = UKWall.stoneHexPick(Int(ukH(seed ^ 0xBB, id) * 7))
        let dark: UInt32 = 0x3B3630
        fill(pts.map { CGPoint(x: $0.x, y: $0.y + 1.6) }, mix(hex, 0x4A453D, 0.32 + tone))
        fill(pts, mix(hex, dark, tone))
        // A patch of lichen on a few stones.
        if ukH(seed ^ 0xCC, id) < 0.14 {
            let m = pts[0], n = pts[2]
            let c = CGPoint(x: (m.x + n.x) / 2 + 2, y: (m.y + n.y) / 2 + 3)
            ellipse(c, 0.012 * unit, 0.007 * unit, Color(hex: 0xB9C07A).opacity(0.75))
        }
    }

    /// The flat top of the wall: a row of chunky capping stones, each standing a little above the wall with its own
    /// front face and flat top. `side` is nil for the back wall (the top goes back from the face) or -1 / +1 for a side
    /// wall (the top goes out, away from the yard).
    private func ukDrawWallTop(_ wall: UKWall, face f: UKWall.Face, seed: UInt64, skip: ClosedRange<Double>?, side: Double?) {
        let h = UKWall.height
        let frame = wall.frame
        func pt(_ u: Double, _ depth: Double, _ v: Double) -> CGPoint {
            // `depth` 0 is the face, 1 the far edge of the top.
            if let side {
                return frame.point(x: side * (wall.halfLength + UKWall.thickness * depth), z: u, height: v)
            }
            return frame.point(x: u, z: wall.backZ - UKWall.thickness * depth, height: v)
        }
        // A bare top under the capping stones, so no gap shows between them.
        func base(_ a: Double, _ b: Double) {
            fill([pt(a, 0, h), pt(b, 0, h), pt(b, 1, h), pt(a, 1, h)], Color(hex: 0x8F8B80))
        }
        if let s = skip { base(f.u0, s.lowerBound); base(s.upperBound, f.u1) } else { base(f.u0, f.u1) }
        var u = f.u0, n = 0
        while u < f.u1 {
            let w = 0.3 + 0.3 * ukH(seed, n * 3)
            var a = u, b = min(u + w, f.u1)
            u += w
            n += 1
            if let s = skip {
                if b <= s.lowerBound || a >= s.upperBound { /* clear of the gate */ } else {
                    if a < s.lowerBound { b = min(b, s.lowerBound) } else { a = max(a, s.upperBound) }
                }
                if b - a < 0.05 { continue }
            }
            let hc = 0.05 + 0.07 * ukH(seed, n * 3 + 1)
            let top = h + hc
            let pick = ukH(seed, n * 3 + 2)
            let faceHex: UInt32 = pick < 0.3 ? 0xCDB98C : (pick < 0.65 ? 0xB4AFA2 : 0xA29E92)
            let topHex: UInt32 = pick < 0.3 ? 0xE0CEA0 : (pick < 0.65 ? 0xD2CEC0 : 0xC3BEAF)
            let ga = 0.012, ch = 0.03
            // Front face (chamfered at the top), then the top.
            fill([pt(a + ga, 0, h), pt(b - ga, 0, h), pt(b - ga, 0, top - ch), pt(b - ga - ch, 0, top), pt(a + ga + ch, 0, top), pt(a + ga, 0, top - ch)],
                 mix(faceHex, 0x4A453D, 0.18))
            fill([pt(a + ga, 0, top), pt(b - ga, 0, top), pt(b - ga - 0.02, 1, top), pt(a + ga + 0.02, 1, top)], mix(topHex, faceHex, 0.0))
        }
    }

    /// Tufts of grass and the odd daisy at the foot of a wall, standing up from the lawn.
    private func ukDrawWallBase(_ wall: UKWall, face f: UKWall.Face, seed: UInt64, skip: ClosedRange<Double>?) {
        let blade = SceneColour.color(SceneColour.scaled(ukGrass(), 0.72))
        let light = SceneColour.color(SceneColour.scaled(ukGrass(), 0.95))
        var u = f.u0 + 0.2, n = 0
        while u < f.u1 {
            defer { u += 0.45 + 0.7 * ukH(seed, n); n += 1 }
            if let s = skip, s.contains(u) { continue }
            let foot = f.map(u, 0)
            let unitLen = frameUnit(f, u)
            for b in 0..<4 {
                let a = -Double.pi / 2 + (Double(b) - 1.5) * 0.42
                let len = unitLen * (0.1 + 0.05 * Double(b % 2))
                let tip = CGPoint(x: foot.x + CGFloat(cos(a) * len), y: foot.y + 2 + CGFloat(sin(a) * len))
                stroke([CGPoint(x: foot.x, y: foot.y + 2), tip], width: 1.5, b % 2 == 0 ? blade : light)
            }
            if ukH(seed, n + 500) < 0.3 {
                let c = CGPoint(x: foot.x + 3, y: foot.y - CGFloat(unitLen * 0.16))
                ellipse(c, 5, 4, Color(hex: 0xFFFDF2))
                ellipse(c, 2, 2, Color(hex: 0xF2C94C))
            }
        }
    }

    /// Canvas points per world unit along a face near position `u` (its local scale).
    private func frameUnit(_ f: UKWall.Face, _ u: Double) -> Double {
        let a = f.map(u, 0), b = f.map(u, 1)
        return Double(abs(a.y - b.y))
    }

    /// A corner pillar: stones on its front and inner faces and a flat capstone with a little overhang.
    private func ukDrawPillar(_ wall: UKWall, sign: Double, seed: UInt64) {
        let pillar = wall.pillar(sign: sign)
        let top = UKWall.pillarHeight
        ukDrawStoneFace(pillar.front, top: top, seed: seed, tone: 0, skip: nil)
        ukDrawStoneFace(pillar.side, top: top, seed: seed ^ 0x31, tone: 0.16, skip: nil)
        // Capstone: a slab a touch wider than the pillar, with its front face and its top.
        let f = wall.frame
        let o = 0.05, t = top + 0.09
        let lo = min(pillar.xInner, pillar.xOuter) - o, hi = max(pillar.xInner, pillar.xOuter) + o
        let zF = pillar.zFront + o, zB = pillar.zBack - o
        fill([f.point(x: lo, z: zF, height: top), f.point(x: hi, z: zF, height: top), f.point(x: hi, z: zF, height: t), f.point(x: lo, z: zF, height: t)],
             Color(hex: 0xA29E92))
        // The inner side of the slab, the face looking into the yard.
        let inner = sign < 0 ? hi : lo
        fill([f.point(x: inner, z: zB, height: top), f.point(x: inner, z: zF, height: top), f.point(x: inner, z: zF, height: t), f.point(x: inner, z: zB, height: t)],
             Color(hex: 0x8F8B80))
        fill([f.point(x: lo, z: zF, height: t), f.point(x: hi, z: zF, height: t), f.point(x: hi, z: zB, height: t), f.point(x: lo, z: zB, height: t)],
             Color(hex: 0xD6D2C4))
    }

    /// A timber five-bar gate hung between two gateposts in the gap, in the wall's plane.
    private func ukDrawGate(_ wall: UKWall) {
        let f = wall.frame, z = wall.backZ
        let g = wall.gap()
        let wood = Color(hex: 0xB88A57), woodShade = Color(hex: 0x8C6440), woodLight = Color(hex: 0xD1A46D)
        func pt(_ x: Double, _ v: Double, _ dz: Double = 0) -> CGPoint { f.point(x: x, z: z + dz, height: v) }
        func quad(_ x0: Double, _ x1: Double, _ v0: Double, _ v1: Double, _ dz: Double, _ c: Color, _ shade: Color) {
            let q = [pt(x0, v0, dz), pt(x1, v0, dz), pt(x1, v1, dz), pt(x0, v1, dz)]
            fill(q.map { CGPoint(x: $0.x + 1.5, y: $0.y + 1.5) }, shade)
            fill(q, c)
        }
        // The leaf sits a little behind the posts. Bars, then end stiles, a middle stile and the diagonal brace.
        let l = g.lowerBound + 0.09, r = g.upperBound - 0.09, dz = -0.05
        let bars = [0.16, 0.36, 0.56, 0.76, 0.96]
        for v in bars { quad(l, r, v, v + 0.07, dz, wood, woodShade) }
        quad(l, l + 0.07, 0.12, 1.07, dz, wood, woodShade)
        quad(r - 0.07, r, 0.12, 1.07, dz, wood, woodShade)
        quad((l + r) / 2 - 0.035, (l + r) / 2 + 0.035, 0.16, 1.03, dz, wood, woodShade)
        let brace = [pt(l, 0.18, dz), pt(l + 0.09, 0.16, dz), pt(r, 0.99, dz), pt(r - 0.09, 1.01, dz)]
        fill(brace.map { CGPoint(x: $0.x + 1.5, y: $0.y + 1.5) }, woodShade)
        fill(brace, woodLight)
        // Gateposts over the stone ends: square, with a chamfered top.
        for x in [g.lowerBound, g.upperBound] {
            let x0 = x - 0.09, x1 = x + 0.09, top = 1.3
            let post = [pt(x0, 0), pt(x1, 0), pt(x1, top), pt(x0, top)]
            fill(post.map { CGPoint(x: $0.x + 2, y: $0.y) }, woodShade)
            fill(post, wood)
            stroke([pt(x0 + 0.04, 0.05), pt(x0 + 0.04, top - 0.03)], width: 1.2, woodLight)
            fill([pt(x0, top), pt(x1, top), pt(x1 - 0.02, top, -0.16), pt(x0 + 0.02, top, -0.16)], woodLight)
        }
        // A flat threshold stone in the gap.
        fill([pt(g.lowerBound + 0.1, 0, 0.16), pt(g.upperBound - 0.1, 0, 0.16), pt(g.upperBound - 0.1, 0, -0.06), pt(g.lowerBound + 0.1, 0, -0.06)],
             Color(hex: 0xC2BBAA))
    }

    /// Where a bird sits on the wall: the middle of the wall's flat top at world x.
    func ukWallTopPoint(x: Double) -> CGPoint {
        let wall = UKWall(camera: camera, size: size)
        return wall.frame.point(x: x, z: wall.backZ - UKWall.thickness / 2, height: UKWall.height + 0.1)
    }
}

extension UKWall {
    static func stoneHexPick(_ i: Int) -> UInt32 { stoneHexTable[min(i, stoneHexTable.count - 1)] }
    private static let stoneHexTable: [UInt32] = [0xA9A79E, 0x9B9990, 0xB8B3A6, 0xC9B48A, 0xD2BD8F, 0xBFA574, 0xA89F8E]
}
