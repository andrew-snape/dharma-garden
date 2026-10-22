import SwiftUI
import DharmaGardenCore

/// Where the cottage's parts stand, in canvas points of the fence layer. The ambient pass uses the same layout to put
/// smoke over the chimney and a glow over the windows, so the two always agree.
struct UKCottage {
    /// World depth of the cottage and how far its ground is lifted above the wall's foot (the back garden rises
    /// behind the wall, so the wall hides the cottage's feet but not its windows).
    static let z = -3.9, lift = 0.5
    /// The cottage is drawn at this fraction of full size about its door, so it stands clear of the sky's edge and
    /// leaves room for the smoke above the chimney.
    static let k = 0.76
    static let x0 = -3.9, x1 = -0.9
    static let eave = 0.82, ridge = 1.3
    /// Windows as (x0, x1, h0, h1) in world units above the cottage's ground.
    static let windows: [(Double, Double, Double, Double)] = [(-3.5, -3.0, 0.28, 0.68), (-1.8, -1.3, 0.28, 0.68)]
    static let doorX = -2.4
    static let chimneyX = -1.55

    /// Canvas points per world unit at the cottage's depth.
    let s: CGFloat
    let at: (Double, Double, Double) -> CGPoint

    /// A point standing up from the cottage's ground at x, `h` units up.
    func P(_ x: Double, _ h: Double) -> CGPoint {
        let g = at(x, 0, Self.z)
        return CGPoint(x: g.x, y: g.y - CGFloat(h + Self.lift) * s)
    }

    /// A point on the cottage itself: x and h are the cottage's own measurements, shrunk by `k` about the door.
    func cp(_ x: Double, _ h: Double) -> CGPoint { P(Self.doorX + (x - Self.doorX) * Self.k, h * Self.k) }

    /// Canvas points per cottage unit.
    var cs: CGFloat { s * CGFloat(Self.k) }

    /// The top of the chimney pots, where the smoke starts.
    var chimneyTop: CGPoint { cp(Self.chimneyX, Self.ridge + 0.42) }
}

extension SceneCanvas {
    func ukCottageLayout() -> UKCottage {
        UKCottage(s: screenPerUnit(x: 0, y: 0, z: UKCottage.z), at: { self.at3($0, $1, $2) })
    }

    private func ukH(_ seed: UInt64, _ i: Int) -> Double { unitHash(seed, UInt64(truncatingIfNeeded: i)) }

    /// Behind the back wall, in the fence layer: the raised back garden, the oak and the stone cottage.
    func ukDrawBackdrop() {
        ukDrawBank()
        ukDrawOak()
        ukDrawCottage()
    }

    /// The back garden rising behind the wall, as a band of lawn with a hedge along its top.
    private func ukDrawBank() {
        let cot = ukCottageLayout()
        let wall = UKWall(camera: camera, size: size)
        let topY = cot.P(0, 0).y
        let footY = wall.frame.point(x: 0, z: wall.backZ).y + 6
        let grass = SceneColour.scaled(ukGrass(), 1.04)
        var pts: [CGPoint] = []
        for i in 0...40 {
            let x = -0.05 + 1.1 * Double(i) / 40
            pts.append(CGPoint(x: x * size.width, y: topY - 2 * CGFloat(sin(x * 17 + 1))))
        }
        pts.append(CGPoint(x: 1.05 * size.width, y: footY))
        pts.append(CGPoint(x: -0.05 * size.width, y: footY))
        fill(pts, SceneColour.color(grass))
        // A trimmed hedge along the back of the bank, with round tops.
        let hedge = SceneColour.lerp(SceneColour.scaled(ukGrass(), 0.6), RGB(0.1, 0.25, 0.14), 0.4)
        let hedgeLight = SceneColour.lerp(hedge, grass, 0.25)
        var x = -0.04
        var n = 0
        while x < 1.04 {
            let c = CGPoint(x: x * size.width, y: topY - 2 * CGFloat(sin(x * 17 + 1)))
            let w = (0.03 + 0.012 * ukH(0x4ED6E, n)) * size.width
            ellipse(CGPoint(x: c.x, y: c.y + 1), w, w * 0.8, SceneColour.color(hedge))
            ellipse(CGPoint(x: c.x - w * 0.12, y: c.y - 1), w * 0.7, w * 0.5, SceneColour.color(hedgeLight))
            x += 0.025 + 0.012 * ukH(0x4ED6F, n)
            n += 1
        }
    }

    /// The cottage: honey stone walls with course lines, small-paned windows, a green door under a climbing rose, a
    /// thatched roof with a ragged eave, and a stone chimney with two pots. Windows light up warmly as the light fades.
    private func ukDrawCottage() {
        let cot = ukCottageLayout()
        let s = cot.cs
        func P(_ x: Double, _ h: Double) -> CGPoint { cot.cp(x, h) }
        func poly(_ pts: [CGPoint], _ c: Color) { fill(pts, c) }
        func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ c: Color) {
            poly([P(x0, y0), P(x1, y0), P(x1, y1), P(x0, y1)], c)
        }
        let wall = Color(hex: 0xE4D1A2), wallShade = Color(hex: 0xC9B386), joint = Color(hex: 0xCDB98B)
        let thatch = Color(hex: 0xCDAA5E), thatchLight = Color(hex: 0xDFC07C), thatchShade = Color(hex: 0x9C7A3A)
        let ridgeCol = Color(hex: 0x866634)
        let frame = Color(hex: 0xFFFBEF), door = Color(hex: 0x4C6E8A), doorShade = Color(hex: 0x3A566E)
        let stone = Color(hex: 0xC9C2B2), stoneShade = Color(hex: 0x9F988A)
        let x0 = UKCottage.x0, x1 = UKCottage.x1, eave = UKCottage.eave, ridge = UKCottage.ridge

        // Ground shadow where the cottage meets the bank.
        ellipse(P((x0 + x1) / 2, 0), (x1 - x0 + 0.5) * s, 0.2 * s, Color(hex: 0x1B2A14).opacity(0.18))

        // Walls, with rough course lines and a plinth.
        rect(x0, 0, x1, eave, wall)
        rect(x0, 0, x1, 0.1, wallShade)
        for k in 1..<5 {
            let h = 0.1 + (eave - 0.1) * Double(k) / 5
            stroke([P(x0, h), P(x1, h)], width: 0.8, joint)
            var x = x0 + 0.2 * ukH(0xC07, k)
            while x < x1 {
                stroke([P(x, h), P(x, h - (eave - 0.1) / 5)], width: 0.7, joint)
                x += 0.22 + 0.25 * ukH(0xC08 + UInt64(k), Int(x * 100))
            }
        }

        // The chimney stands at the right gable, behind the roof.
        let cx = UKCottage.chimneyX
        rect(cx - 0.17, eave, cx + 0.17, ridge + 0.25, stone)
        rect(cx + 0.09, eave, cx + 0.17, ridge + 0.25, stoneShade)
        rect(cx - 0.22, ridge + 0.25, cx + 0.22, ridge + 0.32, stoneShade)
        for dx in [-0.1, 0.1] {
            rect(cx + dx - 0.05, ridge + 0.32, cx + dx + 0.05, ridge + 0.4, Color(hex: 0xB5654E))
            rect(cx + dx - 0.065, ridge + 0.38, cx + dx + 0.065, ridge + 0.43, Color(hex: 0x8F4A38))
        }

        // Windows: frame, glass (warm when it is dim), a sill and small panes.
        let lit = smooth(palette.darkness, 0.1, 0.3)
        let glass = mix(0x9CC3D6, 0xFFD98A, lit)
        for (a, b, h0, h1) in UKCottage.windows {
            rect(a - 0.04, h0 - 0.04, b + 0.04, h1 + 0.04, frame)
            rect(a, h0, b, h1, glass)
            for k in 1..<3 {
                let x = a + (b - a) * Double(k) / 3
                stroke([P(x, h0), P(x, h1)], width: 1, frame)
            }
            stroke([P(a, (h0 + h1) / 2), P(b, (h0 + h1) / 2)], width: 1, frame)
            rect(a - 0.07, h0 - 0.08, b + 0.07, h0 - 0.04, stone)
        }

        // The door: a board door with a little window, a latch and a stone step.
        let d = UKCottage.doorX
        rect(d - 0.27, 0, d + 0.27, 0.66, frame)
        rect(d - 0.23, 0, d + 0.23, 0.63, door)
        rect(d + 0.02, 0, d + 0.23, 0.63, doorShade)
        rect(d - 0.15, 0.4, d + 0.15, 0.56, mix(0x9CC3D6, 0xFFD98A, lit))
        stroke([P(d, 0.4), P(d, 0.56)], width: 1, frame)
        ellipse(P(d + 0.15, 0.28), 0.04 * s, 0.04 * s, Color(hex: 0xE3C16F))
        rect(d - 0.34, -0.02, d + 0.34, 0.03, stone)

        // The thatched roof: a thick hipped shape with a shade layer, straw lines and a ragged lower edge.
        let ov = 0.18, drop = 0.1
        let body = [P(x0 - ov, eave - drop + 0.02), P(x1 + ov, eave - drop + 0.02), P(x1 - 0.45, ridge), P(x0 + 0.45, ridge)]
        poly(body.map { CGPoint(x: $0.x, y: $0.y + 2.5) }, thatchShade)
        poly(body, thatch)
        // Shaggy edge: little straw ends hanging below the roof.
        var ex = x0 - ov + 0.04
        var en = 0
        while ex < x1 + ov {
            let len = 0.05 + 0.05 * ukH(0x7A7, en)
            poly([P(ex, eave - drop + 0.03), P(ex + 0.07, eave - drop + 0.03), P(ex + 0.035, eave - drop - len)], en % 2 == 0 ? thatch : thatchLight)
            ex += 0.075
            en += 1
        }
        let n = 26
        for i in 0...n {
            let t = Double(i) / Double(n)
            let bx = x0 - ov + (x1 - x0 + 2 * ov) * t, tx = x0 + 0.45 + (x1 - x0 - 0.9) * t
            stroke([P(bx, eave - drop + 0.03), P(tx, ridge)], width: i % 2 == 0 ? 1.2 : 0.8, i % 2 == 0 ? thatchLight : thatchShade)
        }
        stroke([P(x0 + 0.45, ridge), P(x1 - 0.45, ridge)], width: 3.2, ridgeCol)
        // The chimney's front, over the roof.
        rect(cx - 0.17, ridge - 0.18, cx + 0.17, ridge + 0.25, stone)
        rect(cx + 0.09, ridge - 0.18, cx + 0.17, ridge + 0.25, stoneShade)

        // Climbing rose around the door: leaves first, then roses.
        let leaf = Color(hex: 0x4F8A4A), leafShade = Color(hex: 0x3B6B37)
        let spray: [(Double, Double, Double)] = [
            (-0.34, 0.12, 0.1), (-0.38, 0.3, 0.11), (-0.33, 0.5, 0.11), (-0.28, 0.68, 0.11), (-0.12, 0.76, 0.1), (0.08, 0.77, 0.1),
            (0.26, 0.7, 0.1), (0.36, 0.52, 0.11), (0.34, 0.3, 0.1), (0.4, 0.14, 0.09), (-0.5, 0.78, 0.09), (0.52, 0.66, 0.09),
            (0.0, 0.88, 0.08), (-0.2, 0.9, 0.07),
        ]
        for (dx, h, r) in spray {
            ellipse(P(d + dx + 0.012, h - 0.01), 2 * r * s, 1.8 * r * s, leafShade)
            ellipse(P(d + dx, h), 2 * r * s, 1.8 * r * s, leaf)
        }
        let roses: [(Double, Double)] = [
            (-0.36, 0.22), (-0.3, 0.55), (-0.18, 0.78), (0.02, 0.8), (0.2, 0.74), (0.36, 0.42), (0.38, 0.2), (-0.48, 0.8),
            (0.5, 0.68), (-0.06, 0.9), (-0.38, 0.4),
        ]
        for (i, (dx, h)) in roses.enumerated() {
            let c = P(d + dx, h)
            let r = 0.05 * s
            let petal = i % 3 == 0 ? Color(hex: 0xD6455F) : Color(hex: 0xEE7C9A)
            ellipse(c, 2 * r, 2 * r, petal)
            ellipse(CGPoint(x: c.x - 0.01 * s, y: c.y - 0.01 * s), 1.1 * r, 1.1 * r, Color(hex: 0xF7B2C4))
        }
    }

    /// A big round oak behind the wall at the back right: a sturdy trunk with a root flare, two limbs and a canopy of
    /// overlapping blobs, each with a shade layer. Its leaf colour follows the palette's foliage, so it turns with the
    /// seasons.
    private func ukDrawOak() {
        let cot = ukCottageLayout()
        let s = cot.s
        let x = 3.1
        func P(_ dx: Double, _ h: Double) -> CGPoint { cot.P(x + dx, h) }
        let bark = Color(hex: 0x6F5A47), barkLight = Color(hex: 0x8A7058)
        let leaf = SceneColour.lerp(SceneColour.scaled(palette.foliage, 0.85), RGB(0.2, 0.45, 0.2), 0.3)
        let leafShade = SceneColour.color(SceneColour.scaled(leaf, 0.76))
        let leafLight = SceneColour.color(SceneColour.lerp(leaf, RGB(0.85, 0.9, 0.4), 0.22))
        let leafMain = SceneColour.color(leaf)

        ellipse(P(0.05, 0), 1.9 * s, 0.22 * s, Color(hex: 0x1B2A14).opacity(0.18))
        // Trunk with a flare at the foot, then two limbs into the canopy.
        fill([P(-0.3, 0), P(0.3, 0), P(0.15, 0.4), P(0.17, 1.0), P(-0.17, 1.0), P(-0.15, 0.4)], bark)
        stroke([P(-0.04, 0.2), P(-0.06, 0.8)], width: 1.4, barkLight)
        stroke([P(0.05, 0.85), P(-0.42, 1.2)], width: 0.13 * s, bark)
        stroke([P(0.05, 0.9), P(0.45, 1.25)], width: 0.12 * s, bark)
        let blobs: [(Double, Double, Double)] = [
            (0.0, 0.95, 0.48), (-0.58, 0.84, 0.38), (0.58, 0.88, 0.4), (-0.3, 1.25, 0.36), (0.32, 1.22, 0.34), (0.0, 1.42, 0.3),
        ]
        for (dx, h, r) in blobs {
            let c = P(dx, h)
            let w = CGFloat(2 * r) * s, hh = w * 0.88
            ellipse(CGPoint(x: c.x + 0.012 * unit, y: c.y + 0.016 * unit), w, hh, leafShade)
            ellipse(c, w, hh, leafMain)
        }
        // Lighter leaf clumps on the sunny upper left of each blob.
        for (dx, h, r) in blobs {
            let c = P(dx - 0.12, h + 0.14)
            ellipse(c, CGFloat(r) * s * 0.9, CGFloat(r) * s * 0.55, leafLight)
        }
    }
}
