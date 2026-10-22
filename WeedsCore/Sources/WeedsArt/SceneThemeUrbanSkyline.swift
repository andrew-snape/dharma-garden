import SwiftUI
import WeedsCore

/// The Urban theme's skyline, drawn in the hills layer behind the fence: two depth layers of buildings with haze
/// between them (mid-rise apartment blocks and a crane far back, rows of terrace rooftops nearer), and power lines
/// sagging between poles. It is the whole view in first person; in the backyard the neighbours' houses cover most of
/// it and it shows in the gap between them.
extension SceneCanvas {
    /// One apartment block in the far layer. x runs 0...1 across, `rise` is how far its top stands above the fence
    /// top (a fraction of the scene height), and the window grid is `cols` by `rows`.
    struct UrbanBlock {
        let x0: Double, x1: Double, rise: Double
        let cols: Int, rows: Int
        let wall: UInt32
    }

    static let urbanBlocks: [UrbanBlock] = [
        UrbanBlock(x0: 0.075, x1: 0.155, rise: 0.075, cols: 4, rows: 8, wall: 0xB9B3AB),
        UrbanBlock(x0: 0.225, x1: 0.285, rise: 0.05, cols: 3, rows: 5, wall: 0xC7BDB0),
        UrbanBlock(x0: 0.415, x1: 0.515, rise: 0.098, cols: 5, rows: 10, wall: 0xB4B9BF),
        UrbanBlock(x0: 0.80, x1: 0.885, rise: 0.082, cols: 4, rows: 8, wall: 0xC2B7AC),
        UrbanBlock(x0: 0.915, x1: 0.99, rise: 0.052, cols: 3, rows: 5, wall: 0xB8B6B0),
    ]

    /// Width of one terrace house in the near layer, and where the row starts.
    static let urbanRoofWidth = 0.1
    static let urbanRoofStart = -0.03

    /// A building colour seen through the haze: darkened as the evening comes on, then blended toward the sky at the
    /// horizon by `haze`.
    func urbanHazy(_ hex: UInt32, haze: Double) -> RGB {
        SceneColour.lerp(urbanRGB(hex, 1 - 0.5 * palette.darkness), palette.skyBottom, haze)
    }

    /// Screen y of the base of the skyline layers (just behind the top of the fence).
    var urbanSkylineBase: Double { urbanFenceTopY + 0.04 }

    func urbanBlockTop(_ b: UrbanBlock) -> Double { max(0.035, urbanFenceTopY - b.rise) }

    /// The window rectangles of a block (canvas points, before any layer shift) and whether each is lit tonight.
    func urbanBlockWindows(_ b: UrbanBlock, index: Int) -> [(rect: CGRect, lit: Bool)] {
        let top = urbanBlockTop(b), base = urbanSkylineBase
        let w = (b.x1 - b.x0) / Double(b.cols), h = (base - top) / Double(b.rows + 1)
        var out: [(CGRect, Bool)] = []
        for r in 0..<b.rows {
            for c in 0..<b.cols {
                let x = b.x0 + w * (Double(c) + 0.28), y = top + h * (Double(r) + 0.45)
                let lit = unitHash(0xB10C + UInt64(index), UInt64(r * 8 + c)) > 0.62
                out.append((CGRect(x: x * size.width, y: y * size.height, width: w * 0.44 * size.width, height: h * 0.5 * size.height), lit))
            }
        }
        return out
    }

    /// The crane in the far layer: mast x, top y, and the jib's reach either side.
    var urbanCrane: (mastX: Double, top: Double, left: Double, right: Double) {
        (0.535, max(0.03, urbanFenceTopY - 0.108), 0.375, 0.6)
    }

    /// Canvas point of the top of a chimney pot in the alley's gap (it shows in both views), where the smoke rises
    /// (the hills layer's coordinates).
    var urbanSkylineChimney: CGPoint {
        let i = 4
        let x = Self.urbanRoofStart + Self.urbanRoofWidth * Double(i + 1)
        return p(x, urbanFenceTopY - 0.056)
    }

    func urbanRidge(_ i: Int) -> Double {
        urbanFenceTopY - 0.031 - 0.007 * unitHash(0xA1F0, UInt64(i))
    }

    func urbanHorizon() {
        let base = urbanSkylineBase
        // The back gardens under the fence line: a dark green-grey, so nothing leaks at the fence's feet.
        fillRect(-0.05, base - 0.02, 1.05, fenceBaseY + 0.05, SceneColour.color(urbanHazy(0x6E7A62, haze: 0.2)))

        // Far layer: blocks and the crane, most hazed.
        let farHaze = 0.6
        for (i, b) in Self.urbanBlocks.enumerated() {
            let top = urbanBlockTop(b)
            let wall = SceneColour.color(urbanHazy(b.wall, haze: farHaze))
            let shade = SceneColour.color(urbanHazy(b.wall, haze: farHaze + 0.1))
            let rect = CGRect(x: b.x0 * size.width, y: top * size.height, width: (b.x1 - b.x0) * size.width, height: (base - top) * size.height)
            ctx.fill(Path(rect), with: .color(wall))
            ctx.fill(Path(CGRect(x: rect.maxX - rect.width * 0.22, y: rect.minY, width: rect.width * 0.22, height: rect.height)), with: .color(shade))
            ctx.fill(Path(CGRect(x: rect.minX - 1, y: rect.minY - 2, width: rect.width + 2, height: 3)), with: .color(shade))
            let glass = SceneColour.color(SceneColour.lerp(urbanHazy(0x8FA9BD, haze: farHaze + 0.05), urbanHazy(b.wall, haze: farHaze), 0.2))
            for w in urbanBlockWindows(b, index: i) { ctx.fill(Path(w.rect), with: .color(glass)) }
            // A lift motor room on a couple of the roofs.
            if i % 2 == 0 {
                ctx.fill(Path(CGRect(x: rect.minX + rect.width * 0.2, y: rect.minY - 6, width: rect.width * 0.28, height: 5)), with: .color(shade))
            }
        }
        urbanDrawCrane(haze: farHaze - 0.05)

        // Near layer: terrace rooftops, in a lighter haze.
        let nearHaze = 0.3
        let count = Int((1.1 / Self.urbanRoofWidth).rounded(.up)) + 1
        let brick: [UInt32] = [0xB5654E, 0xA85B45, 0xC27A58, 0xB0614A]
        for i in 0..<count {
            let x0 = Self.urbanRoofStart + Self.urbanRoofWidth * Double(i), x1 = x0 + Self.urbanRoofWidth
            let ridge = urbanRidge(i), eave = urbanFenceTopY - 0.008
            // Wall under the roof, with a window.
            fill([p(x0, eave), p(x1, eave), p(x1, base), p(x0, base)], SceneColour.color(urbanHazy(brick[i % 4], haze: nearHaze)))
            fillRect(x0 + 0.03, eave + 0.012, x0 + 0.05, eave + 0.03, SceneColour.color(urbanHazy(0xDCE6EC, haze: nearHaze + 0.15)))
            // Roof: a shallow slate gable (the houses abut, so the gables meet at the party walls), a darker edge
            // under it, and a ridge line.
            let slate: UInt32 = i % 2 == 0 ? 0x6F7B85 : 0x7B858D
            let mid = (x0 + x1) / 2
            let roof = [p(x0, eave), p(mid, ridge), p(x1, eave)]
            fill(roof.map { CGPoint(x: $0.x, y: $0.y + 2) }, SceneColour.color(urbanHazy(0x4F5962, haze: nearHaze)))
            fill(roof, SceneColour.color(urbanHazy(slate, haze: nearHaze)))
            fill([p(mid, ridge), p(x1, eave), p(mid + (x1 - mid) * 0.5, eave - (eave - ridge) * 0.5), p(mid, ridge + 0.002)],
                 SceneColour.color(urbanHazy(0x5C6670, haze: nearHaze)))
            // A chimney stack on the party wall with two pots.
            let sx = x1, top = eave - 0.034
            fillRect(sx - 0.006, top, sx + 0.006, eave + 0.004, SceneColour.color(urbanHazy(0xA45A45, haze: nearHaze)))
            fillRect(sx - 0.0075, top - 0.003, sx + 0.0075, top, SceneColour.color(urbanHazy(0x86483A, haze: nearHaze)))
            for dx in [-0.0035, 0.0035] {
                fillRect(sx + dx - 0.0017, top - 0.011, sx + dx + 0.0017, top - 0.003, SceneColour.color(urbanHazy(0xC9703F, haze: nearHaze)))
            }
            // A TV aerial on some of the roofs.
            if unitHash(0xAE41, UInt64(i)) > 0.55 {
                let ax = x0 + 0.045, ay = ridge
                let c = SceneColour.color(urbanHazy(0x4D555C, haze: nearHaze - 0.1))
                stroke([p(ax, ay), p(ax, ay - 0.032)], width: 1.1, c)
                for k in 0..<3 {
                    let y = ay - 0.012 - Double(k) * 0.009, half = 0.007 - Double(k) * 0.0012
                    stroke([p(ax - half, y), p(ax + half, y)], width: 1.1, c)
                }
            }
        }
        urbanDrawPowerLines(haze: 0.22)
    }

    private func urbanDrawCrane(haze: Double) {
        let c = urbanCrane, base = urbanSkylineBase
        let colour = SceneColour.color(urbanHazy(0xD9A441, haze: haze)), dark = SceneColour.color(urbanHazy(0x8F7A4C, haze: haze))
        // Lattice mast: two legs with zigzag bracing.
        let w = 0.005
        stroke([p(c.mastX - w, base), p(c.mastX - w, c.top)], width: 1.4, colour)
        stroke([p(c.mastX + w, base), p(c.mastX + w, c.top)], width: 1.4, colour)
        let steps = 12
        var zig: [CGPoint] = []
        for k in 0...steps {
            let y = base + (c.top - base) * Double(k) / Double(steps)
            zig.append(p(c.mastX + (k % 2 == 0 ? -w : w), y))
        }
        stroke(zig, width: 0.8, dark)
        // Jib out over the block, counter-jib behind with its weight, the tower top and the tie lines.
        let jibY = c.top + 0.012
        stroke([p(c.left, jibY), p(c.right, jibY)], width: 2, colour)
        stroke([p(c.left, jibY + 0.004), p(c.right, jibY + 0.004)], width: 0.8, dark)
        stroke([p(c.mastX, c.top - 0.014), p(c.right, jibY)], width: 0.8, dark)
        stroke([p(c.mastX, c.top - 0.014), p(c.left, jibY)], width: 0.8, dark)
        stroke([p(c.mastX, c.top - 0.014), p(c.mastX, jibY)], width: 1.4, colour)
        fillRect(c.left, jibY, c.left + 0.014, jibY + 0.011, dark.opacity(1))
        fillRect(c.mastX - 0.009, jibY + 0.004, c.mastX + 0.009, jibY + 0.014, colour)
        // Hook line and a load.
        let hx = c.mastX - 0.1
        stroke([p(hx, jibY), p(hx, jibY + 0.04)], width: 0.7, dark)
        fillRect(hx - 0.006, jibY + 0.04, hx + 0.006, jibY + 0.05, dark)
    }

    /// Three poles with cross-arms and wires sagging between them. The poles stand in the near layer's haze.
    private func urbanDrawPowerLines(haze: Double) {
        let pole = SceneColour.color(urbanHazy(0x4A4540, haze: haze)), wire = SceneColour.color(urbanHazy(0x3A3A3E, haze: haze + 0.05))
        let xs = [0.145, 0.585, 1.02]
        let topY = urbanFenceTopY - 0.07
        for x in xs {
            stroke([p(x, urbanSkylineBase), p(x, topY)], width: 2.6, pole)
            stroke([p(x - 0.017, topY + 0.008), p(x + 0.017, topY + 0.008)], width: 2, pole)
            stroke([p(x - 0.011, topY + 0.026), p(x + 0.011, topY + 0.026)], width: 1.6, pole)
        }
        // Wires between neighbouring poles (and off the left edge), three of them, each with its own sag.
        let all = [-0.29] + xs
        for (a, b) in zip(all, all.dropFirst()) {
            for (dx, dy) in [(-0.017, 0.008), (0.017, 0.008), (0.0, 0.026)] {
                var pts: [CGPoint] = []
                let steps = 16
                for s in 0...steps {
                    let t = Double(s) / Double(steps)
                    pts.append(p(a + (b - a) * t + dx, topY + dy + 0.018 * 4 * t * (1 - t) * (b - a) / 0.44))
                }
                stroke(pts, width: 0.9, wire)
            }
        }
    }
}
