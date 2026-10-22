import SwiftUI
import WeedsCore

/// The backyard style's extras: a Queenslander house and a gum tree behind the back fence, side fences,
/// a Hills Hoist and stepping stones on the lawn. They are placed in world space and projected with the
/// same camera as the patch, so they agree with the garden and with tap hit testing.
///
/// World units are the same as `Camera`. x runs across the yard (the patch is centred on 0), y is height and
/// z runs toward the viewer, as in `Camera`.
extension SceneCanvas {
    /// Canvas point of a world position.
    func at3(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
        world(x: x, z: z, height: y)
    }

    /// Canvas points per world unit along x at a position: the local scale of the scene there.
    func screenPerUnit(x: Double, y: Double, z: Double) -> CGFloat {
        abs(at3(x + 1, y, z).x - at3(x, y, z).x)
    }

    /// Fills a world-space polygon.
    func fill3(_ pts: [(Double, Double, Double)], _ color: Color) {
        fill(pts.map { at3($0.0, $0.1, $0.2) }, color)
    }

    /// Strokes a world-space line.
    func stroke3(_ pts: [(Double, Double, Double)], width: CGFloat, _ color: Color) {
        stroke(pts.map { at3($0.0, $0.1, $0.2) }, width: width, color)
    }

    /// Canvas-point ellipse for a world-space blob centre with a world-space radius.
    func blob(_ x: Double, _ y: Double, _ z: Double, radius r: Double, _ color: Color, _ shade: Color) {
        let c = at3(x, y, z)
        let w = CGFloat(2 * r) * screenPerUnit(x: x, y: y, z: z)
        let h = w * 0.86
        ellipse(CGPoint(x: c.x + 0.012 * unit, y: c.y + 0.016 * unit), w, h, shade)
        ellipse(c, w, h, color)
    }

    /// A point standing up from the ground at (x, z): `height` is measured straight up the screen in world
    /// units at the scale `s` (canvas points per unit). Tall things drawn this way keep vertical edges
    /// vertical instead of leaning with the camera's pitch.
    func upright(_ x: Double, _ height: Double, _ z: Double, scale s: CGFloat) -> CGPoint {
        let g = at3(x, 0, z)
        return CGPoint(x: g.x, y: g.y - CGFloat(height) * s)
    }

    // MARK: Behind the back fence (fence layer, drawn before the fence)

    /// The Queenslander and the gum tree, standing on the lawn just behind the back fence, so the fence
    /// hides the stumps and the lower wall. Drawn in the fence layer so they move with it.
    func drawBackyardBack() {
        drawGumTree()
        drawHouse()
    }

    private func poly(_ pts: [CGPoint], _ color: Color) { fill(pts, color) }

    private func drawHouse() {
        let wall = Color(hex: 0xF4E9CF), wallShade = Color(hex: 0xD6C49E)
        let roof = Color(hex: 0x9AA6AE), roofShade = Color(hex: 0x6F7B85), roofLight = Color(hex: 0xB9C3C9)
        let deck = Color(hex: 0xB98A59), deckShade = Color(hex: 0x8C6340)
        let frame = Color(hex: 0xFFFBEF), door = Color(hex: 0x6E8F7A)
        let brick = Color(hex: 0xB5654E)

        let z = -3.5
        let s = screenPerUnit(x: 0, y: 0, z: z)
        func P(_ x: Double, _ h: Double) -> CGPoint { upright(x, h, z, scale: s) }
        func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ c: Color) {
            poly([P(x0, y0), P(x1, y0), P(x1, y1), P(x0, y1)], c)
        }

        let x0 = -4.0, x1 = -0.8
        let floorY = 0.35, eave = 1.3, ridge = 1.95

        // Stumps and the deck edge.
        for x in stride(from: x0 + 0.1, through: x1, by: 0.55) { rect(x - 0.04, 0, x + 0.04, floorY, Color(hex: 0x5E4632)) }

        // Wall with weatherboard lines.
        rect(x0, floorY, x1, eave, wall)
        for k in 1..<5 {
            let y = floorY + (eave - floorY) * Double(k) / 5
            stroke([P(x0, y), P(x1, y)], width: 0.8, wallShade)
        }
        // A brick chimney.
        rect(x1 - 0.7, eave, x1 - 0.45, ridge + 0.25, brick)
        rect(x1 - 0.74, ridge + 0.25, x1 - 0.41, ridge + 0.32, Color(hex: 0x8F4A38))

        // Windows and door, lit warmly as the light fades.
        let lit = smooth(palette.darkness, 0.1, 0.3)
        let glass = mix(0x9CC3D6, 0xFFD98A, lit)
        for (a, b) in [(x0 + 0.3, x0 + 0.9), (x1 - 0.9, x1 - 0.3)] {
            rect(a, floorY + 0.3, b, floorY + 0.85, frame)
            rect(a + 0.04, floorY + 0.34, b - 0.04, floorY + 0.81, glass)
            stroke([P((a + b) / 2, floorY + 0.34), P((a + b) / 2, floorY + 0.81)], width: 1, frame)
        }
        let mid = (x0 + x1) / 2
        rect(mid - 0.25, floorY, mid + 0.25, eave - 0.2, door)
        rect(mid - 0.25, floorY + 0.5, mid + 0.25, floorY + 0.53, Color(hex: 0x557562))

        // Main roof: a hipped corrugated roof seen from the front, with light and dark ridges.
        let ov = 0.2
        let roofShape = [P(x0 - ov, eave - 0.05), P(x1 + ov, eave - 0.05), P(x1 - 0.45, ridge), P(x0 + 0.45, ridge)]
        poly(roofShape.map { CGPoint(x: $0.x, y: $0.y + 2.5) }, roofShade)
        poly(roofShape, roof)
        let n = 28
        for i in 0...n {
            let t = Double(i) / Double(n)
            let bx = x0 - ov + (x1 - x0 + 2 * ov) * t
            let tx = x0 + 0.45 + (x1 - x0 - 0.9) * t
            stroke([P(bx, eave - 0.05), P(tx, ridge)], width: i % 2 == 0 ? 1.4 : 0.8, i % 2 == 0 ? roofLight : roofShade)
        }
        stroke([P(x0 + 0.45, ridge), P(x1 - 0.45, ridge)], width: 3, roofShade)

        // Verandah: a lower sloping roof across the front, posts, and a railing with pickets.
        let vy0 = floorY + 0.8, vy1 = floorY + 0.98
        let vroof = [P(x0 - 0.12, vy0), P(x1 + 0.12, vy0), P(x1 + 0.2, vy1 + 0.06), P(x0 - 0.2, vy1 + 0.06)]
        poly(vroof.map { CGPoint(x: $0.x, y: $0.y + 2.5) }, roofShade)
        poly(vroof, roof)
        for i in 0...22 {
            let t = Double(i) / 22
            let bx = x0 - 0.12 + (x1 - x0 + 0.24) * t, tx = x0 - 0.2 + (x1 - x0 + 0.4) * t
            stroke([P(bx, vy0), P(tx, vy1 + 0.06)], width: i % 2 == 0 ? 1.2 : 0.7, i % 2 == 0 ? roofLight : roofShade)
        }
        rect(x0 - 0.1, floorY - 0.04, x1 + 0.1, floorY + 0.03, deck)
        rect(x0 - 0.1, floorY - 0.07, x1 + 0.1, floorY - 0.04, deckShade)
        let railY = floorY + 0.38
        rect(x0, railY, x1, railY + 0.04, frame)
        var px = x0 + 0.1
        while px < x1 { rect(px - 0.012, floorY, px + 0.012, railY, frame); px += 0.12 }
        for postX in [x0 + 0.06, x0 + 0.9, x0 + 1.6, x0 + 2.3, x1 - 0.06] {
            rect(postX - 0.04, floorY, postX + 0.04, vy0, frame)
        }
    }

    /// A gum tree: a pale, slightly tapered trunk with bark marks, and a silvery-green canopy of overlapping
    /// blobs at the back-right corner, kept well inside the top of the frame.
    private func drawGumTree() {
        let x = 3.3, z = -3.9
        let s = screenPerUnit(x: x, y: 0, z: z)
        let bark = Color(hex: 0xD9D0BE), barkMark = Color(hex: 0x9C8F7C)
        let leaf = Color(hex: 0x8FA27A), leafShade = Color(hex: 0x6C8160)
        func P(_ dx: Double, _ h: Double) -> CGPoint { upright(x + dx, h, z, scale: s) }
        poly([P(-0.14, 0), P(0.14, 0), P(0.07, 1.25), P(-0.07, 1.25)], bark)
        for (dy, dx) in [(0.25, 0.05), (0.6, -0.03), (0.9, 0.04)] {
            stroke([P(dx - 0.06, dy), P(dx + 0.06, dy + 0.12)], width: 1.4, barkMark)
        }
        stroke([P(0, 0.95), P(-0.45, 1.35)], width: 2.6, bark)
        stroke([P(0, 1.05), P(0.42, 1.45)], width: 2.3, bark)
        let blobs: [(Double, Double, Double)] = [
            (0, 1.55, 0.5), (-0.5, 1.4, 0.4), (0.5, 1.42, 0.42), (-0.18, 1.85, 0.4), (0.25, 1.8, 0.36),
        ]
        for (dx, h, r) in blobs {
            let c = P(dx, h)
            let w = CGFloat(2 * r) * s, hh = w * 0.86
            ellipse(CGPoint(x: c.x + 0.012 * unit, y: c.y + 0.016 * unit), w, hh, leafShade)
            ellipse(c, w, hh, leaf)
        }
    }

    // MARK: Lawn (ground layer)

    /// Stepping stones from the front of the patch toward the viewer, and a Hills Hoist rotary clothesline
    /// on the lawn to the right of the patch.
    func drawBackyardLawn() {
        let stone = Color(hex: 0xD9CBB0), stoneShade = Color(hex: 0xB3A285)
        for (i, z) in [2.55, 2.85, 3.15].enumerated() {
            let x = i % 2 == 0 ? -0.12 : 0.12
            let c = at3(x, 0, z)
            let w = CGFloat(0.34) * screenPerUnit(x: x, y: 0, z: z)
            let h = abs(at3(x, 0, z + 0.2).y - at3(x, 0, z - 0.2).y)
            ellipse(CGPoint(x: c.x, y: c.y + 0.008 * unit), w, h, stoneShade)
            ellipse(c, w, h, stone)
        }
        drawHillsHoist()
    }

    /// A rotary clothesline: a central pole with a hub, four arms that spread out in a ring, the washing
    /// line strung around their tips, and a tea towel, a shirt and a pair of socks hanging from it.
    /// The pole is drawn upright on screen (not leaning with the camera) so it reads as a pole.
    private func drawHillsHoist() {
        let hx = 2.75, hz = -0.4, top = 1.2, arm = 0.42
        let s = screenPerUnit(x: hx, y: 0, z: hz)
        let metal = Color(hex: 0x9A9384), metalShade = Color(hex: 0x6F695C)
        func P(_ dx: Double, _ h: Double, _ dz: Double) -> CGPoint {
            let g = at3(hx + dx, 0, hz + dz)
            return CGPoint(x: g.x, y: g.y - CGFloat(h) * s)
        }
        // Ground shadow and a small concrete footing.
        ellipse(CGPoint(x: at3(hx, 0, hz).x + 0.02 * unit, y: at3(hx, 0, hz).y), 0.9 * s, 0.14 * s, Color(hex: 0x000000).opacity(0.1))
        ellipse(at3(hx, 0, hz), 0.2 * s, 0.07 * s, Color(hex: 0x9C968A))
        // Far arms first, then the pole, then the near arms, so the pole sits in the middle of the ring.
        let turn = 0.6
        let angles = (0..<4).map { turn + Double($0) * Double.pi / 2 }
        let tips = angles.map { P(cos($0) * arm, top - 0.12, sin($0) * arm * 0.9) }
        let hub = P(0, top, 0)
        func drawArm(_ i: Int) {
            stroke([hub, tips[i]], width: 2.6, metal)
            // A bracing strut from partway down the pole to the arm's middle.
            stroke([P(0, top - 0.35, 0), CGPoint(x: (hub.x + tips[i].x) / 2, y: (hub.y + tips[i].y) / 2)], width: 1.0, metalShade)
        }
        for i in 0..<4 where sin(angles[i]) < 0 { drawArm(i) }
        stroke([P(0, 0, 0), hub], width: 3.4, metalShade)
        stroke([P(0.012, 0, 0), P(0.012, top, 0)], width: 1.6, metal)
        ellipse(hub, 0.1 * s, 0.07 * s, metal)
        for i in 0..<4 where sin(angles[i]) >= 0 { drawArm(i) }
        // The washing line around the tips.
        let ring = (0...4).map { tips[$0 % 4] }
        stroke(ring, width: 0.8, Color(hex: 0xEFEAE0))
        // Hanging washing on the near sides.
        func hang(_ a: CGPoint, _ b: CGPoint, drop: Double, _ c: Color, _ cs: Color) {
            let d = CGFloat(drop) * s
            let q = [a, b, CGPoint(x: b.x, y: b.y + d), CGPoint(x: a.x, y: a.y + d)]
            fill(q.map { CGPoint(x: $0.x, y: $0.y + 1.5) }, cs)
            fill(q, c)
        }
        func along(_ i: Int, _ j: Int, _ t: Double) -> CGPoint {
            CGPoint(x: tips[i].x + (tips[j].x - tips[i].x) * t, y: tips[i].y + (tips[j].y - tips[i].y) * t)
        }
        // The two near edges of the ring are tips (0,1) and (1,2) or similar: pick by lowest on screen.
        let order = (0..<4).sorted { tips[$0].y > tips[$1].y }
        let n0 = order[0], n1 = (n0 + 1) % 4, n2 = (n0 + 3) % 4
        hang(along(n0, n1, 0.18), along(n0, n1, 0.5), drop: 0.5, Color(hex: 0xE8746B), Color(hex: 0xC4564F))
        hang(along(n0, n2, 0.2), along(n0, n2, 0.48), drop: 0.36, Color(hex: 0x6FB7C9), Color(hex: 0x4F93A6))
        hang(along(n0, n2, 0.62), along(n0, n2, 0.74), drop: 0.2, Color(hex: 0xF2C14E), Color(hex: 0xCB9B2F))
    }

    // MARK: Side fences (fence layer)

    /// Barriers along both sides of the yard in `style`, from the back barrier's ends to beyond the front of the
    /// frame. They use the back barrier's projection (see `BarrierFrame`), so each one starts exactly where the back
    /// one ends.
    func drawSideBarriers(_ style: BarrierStyle) {
        let barrier = BarrierFrame(camera: camera, size: size, style: style)
        for x in [-BarrierFrame.halfLength, BarrierFrame.halfLength] {
            drawBarrierParts(barrier.sideBarrier(x: x), style: style)
        }
    }
}
