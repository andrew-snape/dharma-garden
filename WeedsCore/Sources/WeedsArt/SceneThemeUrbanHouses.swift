import SwiftUI
import WeedsCore

/// The backyard's backdrop (fence layer, drawn before the fence): the backs of two terraces of brick houses behind
/// the neighbours' gardens, with a gap between them (an alley) where the skyline shows, and a neighbour's tree crown
/// in front of the alley's edge. The fence hides the ground floors, so what shows above it is the first floor, the
/// roof and the chimneys: windows with curtains, drainpipes, a balcony, a fire escape and a satellite dish.
///
/// The houses stand at `UrbanScene.houseZ` in the world, so they move with the same camera as the lawn. Their heights
/// are in "pixels" at a reference scale (`UrbanHouseFrame.k` rescales them), not world units: a real house would
/// rise far out of the frame behind a 1.7 unit fence, so these are deliberately squat.
extension SceneCanvas {
    struct UrbanHouseSpec {
        let x0: Double
        let brick: UInt32
        /// 0 plain, 1 first-floor door with a balcony, 2 fire escape.
        let kind: Int
    }

    static let urbanHouseWidth = 2.8
    static let urbanHouseSpecs: [UrbanHouseSpec] = [
        UrbanHouseSpec(x0: -8.6, brick: 0xB5654E, kind: 0),
        UrbanHouseSpec(x0: -5.8, brick: 0xA65A45, kind: 1),
        UrbanHouseSpec(x0: 1.4, brick: 0xC27A58, kind: 2),
        UrbanHouseSpec(x0: 4.2, brick: 0xAD5F49, kind: 0),
        UrbanHouseSpec(x0: 7.0, brick: 0xBC6B50, kind: 1),
    ]
    /// The two terraces, each under one roof: world x ranges.
    static let urbanTerraces: [(x0: Double, x1: Double)] = [(-8.6, -3.0), (1.4, 9.8)]

    /// Heights (in reference pixels above the ground) of the parts of a house.
    static let urbanFloor = 34.0, urbanEave = 66.0, urbanRidge = 90.0

    /// Where the houses stand: a canvas point for a world x and a height in reference pixels.
    struct UrbanHouseFrame {
        let canvas: SceneCanvas
        let z: Double
        /// Pixels per reference pixel at this depth.
        let k: CGFloat

        init(_ canvas: SceneCanvas, z: Double = UrbanScene.houseZ) {
            self.canvas = canvas
            self.z = z
            self.k = canvas.screenPerUnit(x: 0, y: 0, z: z) / 57
        }

        func pt(_ x: Double, _ h: Double) -> CGPoint {
            let g = canvas.at3(x, 0, z)
            return CGPoint(x: g.x, y: g.y - CGFloat(h) * k)
        }

        func quad(_ x0: Double, _ x1: Double, _ h0: Double, _ h1: Double) -> [CGPoint] {
            [pt(x0, h0), pt(x1, h0), pt(x1, h1), pt(x0, h1)]
        }
    }

    /// The first-floor windows of every house (canvas points before any layer shift), and whether each is lit tonight.
    func urbanHouseWindows() -> [(rect: CGRect, lit: Bool)] {
        let f = UrbanHouseFrame(self)
        var out: [(CGRect, Bool)] = []
        for (i, house) in Self.urbanHouseSpecs.enumerated() {
            for j in 0..<2 {
                let cx = house.x0 + Self.urbanHouseWidth / 2 + (j == 0 ? -0.7 : 0.7)
                let bottom = (house.kind == 1 && j == 1) ? Self.urbanFloor + 3 : Self.urbanFloor + 6
                let a = f.pt(cx - 0.3, Self.urbanFloor + 28), b = f.pt(cx + 0.3, bottom)
                out.append((CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y), unitHash(0x71E5, UInt64(i * 2 + j)) > 0.45))
            }
        }
        return out
    }

    func urbanBackdropProps() {
        let f = UrbanHouseFrame(self)
        for t in Self.urbanTerraces { urbanDrawTerrace(f, t) }
        urbanDrawTree()
    }

    private func urbanDrawTerrace(_ f: UrbanHouseFrame, _ t: (x0: Double, x1: Double)) {
        let eave = Self.urbanEave, ridge = Self.urbanRidge, floor = Self.urbanFloor
        let slate = Color(hex: 0x6F7B85), slateShade = Color(hex: 0x4F5962), slateLight = Color(hex: 0x8794A0)
        let stone = Color(hex: 0xDDD3BF), trim = Color(hex: 0xFBF6EA), pipe = Color(hex: 0x4B5359)
        let houses = Self.urbanHouseSpecs.enumerated().filter { $0.element.x0 >= t.x0 - 0.01 && $0.element.x0 < t.x1 }
        let w = Self.urbanHouseWidth

        // Brick walls first, one per house, with courses, a string course and the ground floor's openings.
        for (_, h) in houses {
            let x0 = h.x0, x1 = h.x0 + w
            fill(f.quad(x0, x1, -16, eave), urbanTone(h.brick))
            fill(f.quad(x1 - 0.12, x1, -16, eave), urbanTone(h.brick, 0.85))
            var y = 20.0
            while y < eave {
                let a = f.pt(x0, y), b = f.pt(x1, y)
                stroke([a, b], width: 0.7, urbanTone(h.brick, 0.84))
                y += 4
            }
            fill(f.quad(x0, x1, floor - 1, floor + 2), stone)
            // Ground floor: a back door with a fanlight and a kitchen window (the fence hides most of it).
            let door = Color(hex: 0x3F6670)
            fill(f.quad(x0 + 0.5, x0 + 1.1, -16, 30), door)
            fill(f.quad(x0 + 0.5, x1 - 0.12, 29, 31), stone)
            fill(f.quad(x0 + 1.6, x0 + 2.3, 12, 27), trim)
            fill(f.quad(x0 + 1.65, x0 + 2.25, 14, 25), Color(hex: 0x9CC3D6))
        }
        // First-floor windows, drawn from the shared window list so the ambient pass lights the same ones.
        let windows = urbanHouseWindows()
        let lit = urbanLit
        let curtains: [UInt32] = [0xE8A6A0, 0x9CC8B4, 0xF2D27A, 0xA9B5E0, 0xE9E1D3]
        for (i, h) in Self.urbanHouseSpecs.enumerated() where houses.contains(where: { $0.offset == i }) {
            for j in 0..<2 {
                let wnd = windows[i * 2 + j]
                let r = wnd.rect
                let isDoor = h.kind == 1 && j == 1
                let sill = CGRect(x: r.minX - 3, y: r.maxY, width: r.width + 6, height: 3 * f.k)
                ctx.fill(Path(sill), with: .color(stone))
                ctx.fill(Path(CGRect(x: r.minX - 3, y: r.minY - 3 * f.k, width: r.width + 6, height: 3 * f.k)), with: .color(stone))
                ctx.fill(Path(r.insetBy(dx: -2, dy: -1)), with: .color(trim))
                let glassNight = wnd.lit ? lit : 0
                let glass = mix(0x9CC3D6, 0xFFD98A, glassNight)
                let inner = r.insetBy(dx: 1.5, dy: 1)
                ctx.fill(Path(inner), with: .color(glass))
                // Curtains: a panel each side, wider when the window is lit (drawn for the evening).
                let cw = inner.width * (0.3 + 0.1 * (wnd.lit ? lit : 0))
                let c = curtains[(i * 2 + j) % curtains.count]
                ctx.fill(Path(CGRect(x: inner.minX, y: inner.minY, width: cw, height: inner.height)), with: .color(urbanTone(c)))
                ctx.fill(Path(CGRect(x: inner.maxX - cw, y: inner.minY, width: cw, height: inner.height)), with: .color(urbanTone(c, 0.92)))
                stroke([CGPoint(x: r.midX, y: inner.minY), CGPoint(x: r.midX, y: inner.maxY)], width: 1.1, trim)
                if !isDoor { stroke([CGPoint(x: inner.minX, y: r.midY - 2 * f.k), CGPoint(x: inner.maxX, y: r.midY - 2 * f.k)], width: 1, trim) }
            }
            let cx = h.x0 + w / 2
            if h.kind == 1 { urbanBalcony(f, cx: cx + 0.7) }
            if h.kind == 2 { urbanFireEscape(f, x0: h.x0 + 0.15, x1: h.x0 + w - 0.15) }
            // A satellite dish on the plain house's wall.
            if h.kind == 0 {
                let c = f.pt(h.x0 + w - 0.5, floor + 24)
                ellipse(CGPoint(x: c.x + 1.5, y: c.y + 1.5), 9 * f.k, 8 * f.k, urbanTone(0xBDB6A8))
                ellipse(c, 9 * f.k, 8 * f.k, Color(hex: 0xF1EEE6))
                stroke([c, CGPoint(x: c.x + 4 * f.k, y: c.y - 3 * f.k)], width: 1, pipe)
            }
        }

        // Gutter along the eave and drainpipes down the party walls (and the terrace's two ends).
        stroke([f.pt(t.x0 - 0.1, eave - 1), f.pt(t.x1 + 0.1, eave - 1)], width: 2.2, pipe)
        for x in stride(from: t.x0 + 0.25, through: t.x1, by: w * 2) where x < t.x1 {
            stroke([f.pt(x, -16), f.pt(x, eave - 1)], width: 2.4, pipe)
            stroke([f.pt(x - 0.05, eave - 1), f.pt(x + 0.05, eave - 1)], width: 4, pipe)
        }

        // The roof: one hipped slate roof over the terrace, with rows of tiles, a ridge and a roof window.
        let roof = [f.pt(t.x0 - 0.15, eave - 1), f.pt(t.x1 + 0.15, eave - 1), f.pt(t.x1 - 0.5, ridge), f.pt(t.x0 + 0.5, ridge)]
        fill(roof.map { CGPoint(x: $0.x, y: $0.y + 3) }, slateShade)
        fill(roof, slate)
        var row = 0
        var y = eave + 2
        while y < ridge {
            let a = (y - eave) / (ridge - eave)
            stroke([f.pt(t.x0 - 0.15 + 0.65 * a, y), f.pt(t.x1 + 0.15 - 0.65 * a, y)], width: 0.8, row % 2 == 0 ? slateLight : slateShade)
            y += 3.4
            row += 1
        }
        stroke([f.pt(t.x0 + 0.5, ridge), f.pt(t.x1 - 0.5, ridge)], width: 3, slateShade)
        // Chimney stacks on the party walls and the ends, each with a pair of terracotta pots.
        var stacks = [t.x0 + 0.7, t.x1 - 0.7]
        stacks += houses.dropFirst().map { $0.element.x0 }
        for sx in stacks {
            let top = ridge + 12
            fill(f.quad(sx - 0.2, sx + 0.2, ridge - 18, top), urbanTone(0xA45A45))
            fill(f.quad(sx + 0.08, sx + 0.2, ridge - 18, top), urbanTone(0xA45A45, 0.85))
            fill(f.quad(sx - 0.25, sx + 0.25, top, top + 3), urbanTone(0x86483A))
            for dx in [-0.09, 0.09] {
                fill(f.quad(sx + dx - 0.055, sx + dx + 0.055, top + 3, top + 11), urbanTone(0xC9703F))
                fill(f.quad(sx + dx - 0.07, sx + dx + 0.07, top + 11, top + 13), urbanTone(0xDE8A55))
            }
        }
        // A roof window on the second house of the terrace.
        if let h = houses.dropFirst().first?.element {
            let cx = h.x0 + w / 2
            fill(f.quad(cx - 0.3, cx + 0.3, eave + 7, eave + 17), trim)
            fill(f.quad(cx - 0.25, cx + 0.25, eave + 8.5, eave + 15.5), Color(hex: 0x9CC3D6))
        }
    }

    /// A small wrought-iron balcony in front of a first-floor door: a ledge and a railing with bars, and a pot plant.
    private func urbanBalcony(_ f: UrbanHouseFrame, cx: Double) {
        let iron = Color(hex: 0x30363B), floor = Self.urbanFloor
        let a = cx - 0.55, b = cx + 0.55
        fill(f.quad(a, b, floor - 1, floor + 2), iron)
        fill(f.quad(a, b, floor + 12, floor + 13.5), iron)
        var x = a + 0.05
        while x < b {
            stroke([f.pt(x, floor + 2), f.pt(x, floor + 13)], width: 0.9, iron)
            x += 0.11
        }
        // A pot plant on the ledge.
        let c = f.pt(cx - 0.3, floor + 2)
        fill([CGPoint(x: c.x - 3 * f.k, y: c.y - 5 * f.k), CGPoint(x: c.x + 3 * f.k, y: c.y - 5 * f.k),
              CGPoint(x: c.x + 2 * f.k, y: c.y), CGPoint(x: c.x - 2 * f.k, y: c.y)], urbanTone(0xCF7B52))
        let leaf = SceneColour.color(SceneColour.scaled(palette.foliage, 0.85))
        ellipse(CGPoint(x: c.x, y: c.y - 8 * f.k), 8 * f.k, 7 * f.k, leaf)
    }

    /// A black iron fire escape: a platform at the first-floor level with a rail, and a stair zigzagging down from it.
    private func urbanFireEscape(_ f: UrbanHouseFrame, x0: Double, x1: Double) {
        let iron = Color(hex: 0x2E3338), floor = Self.urbanFloor
        fill(f.quad(x0, x1, floor - 2, floor + 1), iron)
        fill(f.quad(x0, x1, floor + 11, floor + 12.5), iron)
        var x = x0 + 0.05
        while x < x1 {
            stroke([f.pt(x, floor + 1), f.pt(x, floor + 12)], width: 0.8, iron)
            x += 0.12
        }
        // The stair: stringers running down to the right from the platform's end, with treads.
        let sx = x1 - 0.75
        stroke([f.pt(sx, floor - 2), f.pt(x1 - 0.1, floor - 22)], width: 1.4, iron)
        stroke([f.pt(sx + 0.12, floor + 10), f.pt(x1 + 0.02, floor - 12)], width: 1.0, iron)
        for k in 0..<5 {
            let t = Double(k) / 4
            let tx = sx + (x1 - 0.1 - sx) * t, th = floor - 2 - 20 * t
            stroke([f.pt(tx - 0.07, th), f.pt(tx + 0.07, th)], width: 1.1, iron)
        }
    }

    /// A neighbour's tree: a round crown of palette-green blobs in front of the alley's edge, its trunk hidden by the fence.
    private func urbanDrawTree() {
        let x = -2.0, z = UrbanScene.treeZ
        let s = screenPerUnit(x: x, y: 0, z: z)
        let leaf = SceneColour.color(SceneColour.lerp(SceneColour.scaled(palette.foliage, 0.95), RGB(0.5, 0.58, 0.45), 0.2))
        let shade = SceneColour.color(SceneColour.scaled(palette.foliage, 0.7))
        let light = SceneColour.color(SceneColour.lerp(palette.foliage, RGB(1, 1, 0.7), 0.18))
        func P(_ dx: Double, _ h: Double) -> CGPoint { upright(x + dx, h, z, scale: s) }
        // A few branches between the fence top and the crown.
        let bark = Color(hex: 0x6B5646)
        stroke([P(0, 0.9), P(-0.1, 1.3)], width: 3, bark)
        stroke([P(0.05, 1.0), P(0.35, 1.3)], width: 2, bark)
        let blobs: [(Double, Double, Double)] = [(0, 1.4, 0.5), (-0.5, 1.28, 0.4), (0.52, 1.3, 0.42), (-0.15, 1.7, 0.36), (0.3, 1.62, 0.34)]
        for (dx, h, r) in blobs {
            let c = P(dx, h)
            let w = CGFloat(2 * r) * s, hh = w * 0.86
            ellipse(CGPoint(x: c.x + 0.012 * unit, y: c.y + 0.016 * unit), w, hh, shade)
            ellipse(c, w, hh, leaf)
        }
        for (dx, h, r) in blobs.prefix(3) {
            let c = P(dx - 0.1, h + 0.12)
            ellipse(c, CGFloat(r) * s, CGFloat(r) * s * 0.8, light.opacity(0.45))
        }
    }
}
