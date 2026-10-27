import SwiftUI
import DharmaGardenCore

/// The backyard's scenery behind the Japanese wall: a tiled-roof tea house, a red maple (momiji) and a cloud-pruned
/// pine (niwaki), and in front of the wall a stone lantern and a bamboo water spout (shishi-odoshi). Everything is
/// placed in world space and projected with `BarrierFrame.point`, the same upright projection as the wall, so heights
/// agree with it and verticals stay vertical.
extension SceneCanvas {
    /// The tea house's footprint: x range and depth, and the lit shoji bays (as canvas quads in the fence layer), shared
    /// with the ambient glow.
    static let japaneseTeaHouse = (x0: -4.1, x1: -0.7, z: -5.3)

    func drawJapaneseBackdrop() {
        drawJapanesePine()
        drawJapaneseTeaHouse()
        drawJapaneseMaple()
    }

    private func japaneseFrame() -> BarrierFrame { BarrierFrame(camera: camera, size: size, style: .earthWall) }

    // MARK: Tea house

    /// Heights of the tea house in world units.
    private static let teaPlinth = 0.4, teaFloor = 0.5, teaEave = 1.5, teaRidge = 2.2

    /// Canvas quads of the shoji bays (paper panels), in the fence layer's coordinates, for the lit glow.
    func japaneseShojiQuads() -> [[CGPoint]] {
        let f = japaneseFrame(), t = Self.japaneseTeaHouse
        let bays = 4, x0 = t.x0 + 0.35, w = (t.x1 - t.x0 - 0.7) / Double(bays)
        var quads: [[CGPoint]] = []
        for i in 0..<bays where i != 1 {
            let a = x0 + w * Double(i) + 0.04, b = x0 + w * Double(i + 1) - 0.04
            let lo = Self.teaFloor + 0.2, hi = Self.teaEave - 0.17
            quads.append([f.point(x: a, z: t.z, height: lo), f.point(x: b, z: t.z, height: lo),
                          f.point(x: b, z: t.z, height: hi), f.point(x: a, z: t.z, height: hi)])
        }
        return quads
    }

    private func drawJapaneseTeaHouse() {
        typealias W = JapaneseWallColour
        let f = japaneseFrame(), t = Self.japaneseTeaHouse
        let x0 = t.x0, x1 = t.x1, z = t.z
        func P(_ x: Double, _ h: Double) -> CGPoint { f.point(x: x, z: z, height: h) }
        func rect(_ a: Double, _ lo: Double, _ b: Double, _ hi: Double, _ c: Color) { fill([P(a, lo), P(b, lo), P(b, hi), P(a, hi)], c) }
        let s = f.unitWidth(x: (x0 + x1) / 2, z: z)
        let plinth = Self.teaPlinth, floor = Self.teaFloor, eave = Self.teaEave, ridge = Self.teaRidge
        let stone = Color(hex: 0x9C998F), stoneShade = Color(hex: 0x77746B)
        let deck = Color(hex: 0xB58859), deckShade = Color(hex: 0x8C6340)
        let paper = Color(hex: 0xF2EAD2), paperShade = Color(hex: 0xD8CDAE), lattice = Color(hex: 0x8B6A48)
        let lit = smooth(palette.darkness, 0.1, 0.3)

        // Ground shadow and the stone plinth with joints.
        propShadow(foot: CGPoint(x: P((x0 + x1) / 2, 0).x, y: P(0, 0).y + 0.02 * s), height: CGFloat(eave) * s, width: (x1 - x0 + 1.2) * s, depth: 0.28 * s, opacity: 0.14)
        rect(x0 - 0.12, 0, x1 + 0.12, plinth, stone)
        rect(x0 - 0.12, 0, x1 + 0.12, 0.07, stoneShade)
        var jx = x0 - 0.12 + 0.5
        while jx < x1 + 0.12 { stroke([P(jx, 0.07), P(jx, plinth)], width: 0.8, stoneShade); jx += 0.62 }
        // Deck (engawa): its front board and the lit top edge.
        rect(x0 - 0.12, plinth, x1 + 0.12, floor, deck)
        rect(x0 - 0.12, plinth, x1 + 0.12, plinth + 0.035, deckShade)

        // Back wall of the room, then the bays: shoji screens, one slid open to show the room.
        let bays = 4, bx0 = x0 + 0.35, bw = (x1 - x0 - 0.7) / Double(bays)
        rect(bx0, floor, bx0 + bw * Double(bays), eave - 0.1, Color(hex: 0x4A3B30))
        for i in 0..<bays {
            let a = bx0 + bw * Double(i) + 0.03, b = bx0 + bw * Double(i + 1) - 0.03
            let lo = floor + 0.2, hi = eave - 0.17
            if i == 1 {
                // Open bay: the room inside, with a hanging scroll and a low lit lamp.
                rect(a, floor, b, eave - 0.1, mix(0x4A3B30, 0x7A5A3A, lit))
                rect(a + 0.12, floor + 0.4, a + 0.26, floor + 0.85, Color(hex: 0xE9DDBC))
                rect(a + 0.17, floor + 0.46, a + 0.21, floor + 0.79, Color(hex: 0x3D3128))
                rect(a, floor, b, floor + 0.05, Color(hex: 0xC9B88A))
                continue
            }
            // Wooden lower panel, then the paper with a lattice.
            rect(a, floor, b, lo, Color(hex: 0xA77B52))
            rect(a, lo, b, hi, mix(0xF2EAD2, 0xFFDC96, lit))
            rect(a, hi - 0.06, b, hi, mix(0xD8CDAE, 0xE8B96A, lit))
            let cols = 3, rows = 4
            for c in 0...cols {
                let x = a + (b - a) * Double(c) / Double(cols)
                stroke([P(x, lo), P(x, hi)], width: c == 0 || c == cols ? 1.6 : 1, lattice)
            }
            for r in 0...rows {
                let h = lo + (hi - lo) * Double(r) / Double(rows)
                stroke([P(a, h), P(b, h)], width: r == 0 || r == rows ? 1.6 : 1, lattice)
            }
            _ = (paper, paperShade)
        }
        // Posts between the bays and a beam across the top of them.
        for i in 0...bays {
            let x = bx0 + bw * Double(i), pw = 0.055
            rect(x - pw, floor, x + pw, eave - 0.05, W.wood)
            rect(x - pw, floor, x - pw * 0.2, eave - 0.05, W.woodShade.opacity(0.35))
        }
        rect(x0 + 0.1, eave - 0.2, x1 - 0.1, eave - 0.05, W.woodShade)
        // Soft shade under the eave on the screens.
        rect(bx0, eave - 0.45, bx0 + bw * Double(bays), eave - 0.2, Color.black.opacity(0.1))

        // The roof: a hipped tile roof whose eaves curve up at the corners.
        let ov = 0.75
        let n = 40
        func eavePoint(_ t: Double) -> CGPoint {
            let x = (x0 - ov) + (x1 - x0 + 2 * ov) * t
            return P(x, eave + 0.2 * pow(abs(2 * t - 1), 2.2))
        }
        let ridgeL = x0 + 0.55, ridgeR = x1 - 0.55
        func ridgePoint(_ t: Double) -> CGPoint { P(ridgeL + (ridgeR - ridgeL) * t, ridge) }
        func roofPoint(_ t: Double, _ u: Double) -> CGPoint {
            let a = eavePoint(t), b = ridgePoint(t)
            // The sides curve in a little (concave) toward the ridge.
            let bow = sin(u * Double.pi) * 0.012 * unit * (t < 0.5 ? 1 : -1) * (1 - abs(2 * t - 1))
            return CGPoint(x: a.x + (b.x - a.x) * u + bow, y: a.y + (b.y - a.y) * u)
        }
        let eaveCurve = (0...n).map { eavePoint(Double($0) / Double(n)) }
        var outline = eaveCurve
        outline.append(contentsOf: [ridgePoint(1), ridgePoint(0)])
        // A pale soffit (the underside of the eave) first, then the roof with its shade copy.
        fill(eaveCurve.map { CGPoint(x: $0.x, y: $0.y + 0.1 * s) } + eaveCurve.reversed(), W.woodShade)
        fill(outline.map { CGPoint(x: $0.x, y: $0.y + 3) }, W.tileDark)
        fill(outline, W.tile)
        // Tile rows (curved courses) and the ridges between tile columns.
        for k in 1..<7 {
            let u = Double(k) / 7
            stroke((0...n).map { roofPoint(Double($0) / Double(n), u) }, width: 0.9, W.tileDark.opacity(0.55))
        }
        let cols = 36
        for i in 0...cols {
            let t = Double(i) / Double(cols)
            stroke([roofPoint(t, 0.02), roofPoint(t, 1)], width: i % 2 == 0 ? 1.3 : 0.8, i % 2 == 0 ? W.tileLight.opacity(0.7) : W.tileDark.opacity(0.7))
        }
        // The eave face (a dark band with round tile ends) and the ridge cap with its ornaments.
        let faceThick = 0.11 * s
        fill(eaveCurve.map { CGPoint(x: $0.x, y: $0.y - 0.01 * s) } + eaveCurve.reversed().map { CGPoint(x: $0.x, y: $0.y + faceThick) }, W.tileDark)
        for i in 0..<cols {
            let c = eavePoint((Double(i) + 0.5) / Double(cols))
            let d = 0.085 * s
            ellipse(CGPoint(x: c.x, y: c.y + faceThick * 0.55), d, d * 0.85, W.tileLight)
        }
        let ridgeLine = (0...12).map { ridgePoint(Double($0) / 12) }
        stroke(ridgeLine.map { CGPoint(x: $0.x, y: $0.y + 1.5) }, width: 6, W.tileDark)
        stroke(ridgeLine, width: 5, W.tileLight)
        for end in [ridgePoint(0), ridgePoint(1)] {
            ellipse(CGPoint(x: end.x, y: end.y - 0.04 * s), 0.2 * s, 0.22 * s, W.tileDark)
            ellipse(CGPoint(x: end.x, y: end.y - 0.05 * s), 0.15 * s, 0.17 * s, W.tileLight)
        }
    }

    // MARK: Trees

    /// A red maple at the back right: a dark twisting trunk and a canopy of overlapping blobs in reds and oranges.
    private func drawJapaneseMaple() {
        let f = japaneseFrame()
        let x = 3.35, z = -4.7
        func P(_ dx: Double, _ h: Double) -> CGPoint { f.point(x: x + dx, z: z, height: h) }
        let s = f.unitWidth(x: x, z: z)
        let bark = Color(hex: 0x5E4838), barkShade = Color(hex: 0x3F2F24)
        let red = Color(hex: 0xC4412E), redShade = Color(hex: 0x8E2B22), orange = Color(hex: 0xE0833A), light = Color(hex: 0xF0A24A)
        ellipse(CGPoint(x: P(0, 0).x + 0.2 * s, y: P(0, 0).y), 2.4 * s, 0.32 * s, Color.black.opacity(0.1))
        // Trunk and branches.
        fill([P(-0.16, 0), P(0.16, 0), P(0.08, 1.2), P(-0.1, 1.2)].map { CGPoint(x: $0.x + 1.5, y: $0.y) }, barkShade)
        fill([P(-0.16, 0), P(0.16, 0), P(0.08, 1.2), P(-0.1, 1.2)], bark)
        stroke([P(-0.01, 1.0), P(-0.6, 1.5)], width: 0.1 * s, bark)
        stroke([P(0.0, 1.1), P(0.55, 1.65)], width: 0.09 * s, bark)
        stroke([P(0, 1.2), P(0.05, 1.9)], width: 0.08 * s, bark)
        // Canopy back to front: shade blobs, red body, orange, then light highlights on top.
        let blobs: [(dx: Double, h: Double, r: Double, c: Int)] = [
            (-0.75, 1.55, 0.55, 0), (0.8, 1.7, 0.58, 0), (0.0, 1.75, 0.7, 0), (-0.35, 2.15, 0.55, 1), (0.45, 2.2, 0.5, 1),
            (-0.85, 1.9, 0.4, 1), (0.95, 2.05, 0.4, 1), (0.0, 2.45, 0.42, 2), (-0.5, 2.0, 0.35, 2), (0.4, 1.9, 0.32, 2),
            (-0.05, 2.05, 0.3, 2),
        ]
        for b in blobs {
            let c = P(b.dx, b.h - 0.3), w = CGFloat(2 * b.r) * s, h = w * 0.82
            ellipse(CGPoint(x: c.x + 0.015 * s * 2, y: c.y + 0.04 * s), w, h, redShade)
            ellipse(c, w, h, b.c == 0 ? red : (b.c == 1 ? orange : light))
        }
        // Leaf flecks.
        for i in 0..<26 {
            let a = unitHash(0x3A91, UInt64(i * 2)) * 2 * Double.pi, d = unitHash(0x3A91, UInt64(i * 2 + 1))
            let c = P(cos(a) * d * 1.0, 1.7 + sin(a) * d * 0.55)
            ellipse(c, 0.07 * s, 0.05 * s, i % 2 == 0 ? light : redShade.opacity(0.7))
        }
    }

    /// A cloud-pruned pine: a leaning, twisting trunk with branches that carry flat, layered pads of needles.
    private func drawJapanesePine() {
        let f = japaneseFrame()
        let x = 0.8, z = -4.5
        func P(_ dx: Double, _ h: Double) -> CGPoint { f.point(x: x + dx, z: z, height: h) }
        let s = f.unitWidth(x: x, z: z)
        let bark = Color(hex: 0x6B4F3A), barkShade = Color(hex: 0x45321F)
        let needle = Color(hex: 0x3F6B4A), needleShade = Color(hex: 0x2B4C36), needleLight = Color(hex: 0x6C9B5E)
        ellipse(CGPoint(x: P(0, 0).x + 0.15 * s, y: P(0, 0).y), 1.8 * s, 0.26 * s, Color.black.opacity(0.1))
        let trunk = [P(0, 0), P(0.12, 0.5), P(-0.1, 1.0), P(0.08, 1.5), P(-0.02, 2.0)]
        stroke(trunk.map { CGPoint(x: $0.x + 1.5, y: $0.y) }, width: 0.2 * s, barkShade)
        stroke(trunk, width: 0.19 * s, bark)
        stroke(Array(trunk.suffix(3)), width: 0.1 * s, bark)
        // (x offset, height, radius) of each pad and the point on the trunk its branch leaves from.
        let pads: [(dx: Double, h: Double, r: Double, from: Double)] = [
            (-0.85, 1.05, 0.55, 0.62), (0.9, 1.3, 0.6, 0.7), (-0.35, 1.75, 0.55, 1.15), (0.5, 2.05, 0.45, 1.3), (-0.02, 2.4, 0.38, 1.7),
        ]
        for pad in pads {
            let from = P(pad.dx > 0 ? 0.05 : -0.04, pad.from)
            stroke([from, P(pad.dx * 0.6, pad.h - 0.18), P(pad.dx, pad.h - 0.06)], width: 0.07 * s, bark)
        }
        for pad in pads {
            let c = P(pad.dx, pad.h), w = CGFloat(2 * pad.r) * s, h = w * 0.34
            ellipse(CGPoint(x: c.x + 2, y: c.y + h * 0.28), w, h, needleShade)
            ellipse(c, w, h, needle)
            ellipse(CGPoint(x: c.x - w * 0.08, y: c.y - h * 0.22), w * 0.7, h * 0.5, needleLight.opacity(0.85))
            // Needle ticks along the top edge.
            for k in 0..<9 {
                let a = Double.pi * (1.08 + 0.84 * Double(k) / 8)
                let e = CGPoint(x: c.x + CGFloat(cos(a)) * w * 0.48, y: c.y + CGFloat(sin(a)) * h * 0.48)
                stroke([e, CGPoint(x: e.x + CGFloat(cos(a)) * 0.05 * s, y: e.y + CGFloat(sin(a)) * 0.05 * s)], width: 1.2, needleShade)
            }
        }
    }

    // MARK: In front of the wall

    /// A stone lantern at the left corner and a bamboo water spout at the right, on the lawn just in front of the wall.
    func drawJapaneseWallProps() {
        let f = japaneseFrame()
        let lantern = japaneseWallLantern()
        let window = drawJapaneseStoneLantern(base: lantern.base, u: lantern.u, glowing: palette.darkness)
        _ = window
        drawJapaneseShishiOdoshi(f)
    }

    /// Where the lantern in front of the wall stands, and its size.
    func japaneseWallLantern() -> (base: CGPoint, u: CGFloat) {
        let f = japaneseFrame()
        let base = f.point(x: -3.8, z: -3.05)
        return (base, 0.62 * f.unitWidth(x: -3.8, z: -3.05))
    }

    /// A small bamboo water spout beside a stone basin: a wooden stand, the pivoting bamboo tube and a thin stream.
    private func drawJapaneseShishiOdoshi(_ f: BarrierFrame) {
        let x = 3.75, z = -3.05
        let base = f.point(x: x, z: z), s = f.unitWidth(x: x, z: z)
        func P(_ dx: Double, _ h: Double) -> CGPoint { CGPoint(x: base.x + CGFloat(dx) * s, y: base.y - CGFloat(h) * s * 0.8) }
        let bamboo = Color(hex: 0x8DA85A), bambooShade = Color(hex: 0x65803F), bambooLight = Color(hex: 0xB7CD80)
        let wood = JapaneseWallColour.wood, woodShade = JapaneseWallColour.woodShade
        let stone = Color(hex: 0x9C9A92), stoneShade = Color(hex: 0x76746C), water = Color(hex: 0x8DC0D6)
        // Shadow, then the basin: a low stone bowl with water and a ripple.
        propShadow(foot: CGPoint(x: base.x, y: base.y + 0.02 * s), height: 0.5 * s, width: 1.4 * s, depth: 0.26 * s, opacity: 0.16)
        ellipse(CGPoint(x: P(0.05, 0).x, y: P(0.05, 0).y), 1.0 * s, 0.34 * s, stoneShade)
        ellipse(CGPoint(x: P(0.05, 0.03).x, y: P(0.05, 0.03).y), 1.0 * s, 0.32 * s, stone)
        ellipse(P(0.05, 0.05), 0.82 * s, 0.24 * s, water)
        ctx.stroke(Path(ellipseIn: CGRect(x: P(0.05, 0.05).x - 0.2 * s, y: P(0.05, 0.05).y - 0.045 * s, width: 0.4 * s, height: 0.09 * s)),
                   with: .color(Color.white.opacity(0.6)), lineWidth: 1)
        // Wooden stand: two posts and a cross bar the tube pivots on.
        for dx in [-0.42, -0.22] {
            stroke([P(dx, 0.02), P(dx, 0.62)], width: 0.07 * s, woodShade)
            stroke([P(dx, 0.02), P(dx, 0.62)], width: 0.045 * s, wood)
        }
        stroke([P(-0.46, 0.52), P(-0.18, 0.52)], width: 0.06 * s, wood)
        // The tube, tipped to pour into the basin, with a cut mouth, nodes and a pale highlight.
        let up = P(-0.32, 0.62), down = P(0.18, 0.3)
        stroke([P(-0.33, 0.6), down].map { CGPoint(x: $0.x + 1.2, y: $0.y + 1.2) }, width: 0.11 * s, bambooShade)
        stroke([P(-0.33, 0.6), down], width: 0.1 * s, bamboo)
        stroke([CGPoint(x: up.x + 1, y: up.y - 1), CGPoint(x: (up.x + down.x) / 2, y: (up.y + down.y) / 2 - 1.5)], width: 0.03 * s, bambooLight)
        ellipse(down, 0.07 * s, 0.1 * s, Color(hex: 0xDDE3B5))
        for t in [0.3, 0.62] {
            let c = CGPoint(x: up.x + (down.x - up.x) * t, y: up.y + (down.y - up.y) * t)
            stroke([CGPoint(x: c.x, y: c.y - 0.05 * s), CGPoint(x: c.x, y: c.y + 0.05 * s)], width: 1.2, bambooShade)
        }
        // The feeding pipe and a thin stream.
        stroke([P(-0.62, 0.78), P(-0.45, 0.76), P(-0.38, 0.7)], width: 0.05 * s, bamboo)
        stroke([P(-0.37, 0.7), P(-0.36, 0.64)], width: 1.4, water)
    }
}
