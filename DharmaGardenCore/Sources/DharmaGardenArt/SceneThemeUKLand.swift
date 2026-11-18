import SwiftUI
import DharmaGardenCore

/// The Rural UK theme's land: the patchwork horizon with its church and sheep, the cool lush lawn with its side
/// flowerbeds and flagstones, and the foreground props (galvanised can, wellies, clover tufts). Colours come from the
/// palette, so season, weather, dusk and night still work.
extension SceneCanvas {
    // MARK: Colours

    /// A colour a touch greyer and cooler, as English skies and distant hills are.
    func ukSoften(_ c: RGB, _ amount: Double = 0.18) -> RGB {
        let l = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
        return SceneColour.lerp(c, RGB(l * 0.98, l, l * 1.05), amount)
    }

    /// The lawn's green: the palette's grass pulled lusher and cooler.
    func ukGrass() -> RGB { SceneColour.lerp(palette.grass, RGB(0.3, 0.6, 0.34), 0.28) }

    private func ukHash(_ seed: UInt64, _ i: Int) -> Double { unitHash(seed, UInt64(i)) }

    // MARK: Horizon (hills layer)

    /// A gentle ridge: normalised y at normalised x.
    private func ukRidgeY(_ x: Double, base: Double, amp: Double, phase: Double) -> Double {
        let wave = 0.55 * sin(x * 5.2 + phase) + 0.3 * sin(x * 11 + phase * 2) + 0.55
        return base - amp * wave
    }

    private func ukRidge(base: Double, amp: Double, phase: Double, colour: RGB) {
        var pts: [CGPoint] = []
        for i in 0...60 {
            let x = -0.05 + 1.1 * Double(i) / 60
            pts.append(p(x, ukRidgeY(x, base: base, amp: amp, phase: phase)))
        }
        pts.append(p(1.05, base + 0.12))
        pts.append(p(-0.05, base + 0.12))
        fill(pts, SceneColour.color(colour))
    }

    /// Hazy far hills with a church spire, then gentle near hills as a patchwork of fields in different greens and a
    /// gold, split by dark hedgerows, with a few sheep.
    func ukDrawHorizon() {
        let base = fenceTopY + 0.02
        let haze = ukSoften(palette.skyBottom, 0.3)
        let grass = ukGrass()

        // Far hills, with the church on the farthest ridge.
        let farA = SceneColour.lerp(haze, grass, 0.3)
        let farB = SceneColour.lerp(haze, grass, 0.5)
        ukRidge(base: base - 0.005, amp: 0.1, phase: 3.1, colour: farA)
        ukDrawChurch(base: base - 0.005, amp: 0.1, phase: 3.1, colour: SceneColour.lerp(farA, RGB(0.5, 0.5, 0.6), 0.45))
        ukRidge(base: base, amp: 0.075, phase: 0.8, colour: farB)

        // Near hills as a patchwork. Rows follow the hill's contour; each row is cut into fields by slanted hedges.
        let midBase = base + 0.03, midAmp = 0.05, midPhase = 2.1
        func top(_ x: Double) -> Double { ukRidgeY(x, base: midBase, amp: midAmp, phase: midPhase) }
        let offsets = [0.0, 0.02, 0.045, 0.08, 0.2]
        let fields = [
            grass,
            SceneColour.lerp(grass, RGB(0.85, 0.95, 0.55), 0.22),
            SceneColour.lerp(grass, RGB(0.93, 0.78, 0.3), 0.62),
            SceneColour.scaled(grass, 0.82),
            SceneColour.lerp(grass, RGB(0.7, 0.78, 0.3), 0.4),
            SceneColour.lerp(grass, RGB(0.62, 0.5, 0.32), 0.3),
        ]
        let hedge = SceneColour.color(SceneColour.lerp(SceneColour.scaled(grass, 0.5), RGB(0.1, 0.25, 0.14), 0.4))
        for j in 0..<(offsets.count - 1) {
            var xs = [-0.06], slants = [0.0]
            var x = -0.06, k = 0
            while x < 1.06 {
                x += 0.07 + 0.15 * ukHash(0xF1E1D0 + UInt64(j), k)
                xs.append(x)
                slants.append((ukHash(0xF1E1D5 + UInt64(j), k) - 0.5) * 0.05)
                k += 1
            }
            for i in 0..<(xs.count - 1) {
                let a = xs[i], b = xs[i + 1]
                let aB = a + slants[i], bB = b + slants[i + 1]
                let n = max(2, Int((b - a) / 0.02))
                var pts: [CGPoint] = []
                for t in 0...n {
                    let px = a + (b - a) * Double(t) / Double(n)
                    pts.append(p(px, top(px) + offsets[j]))
                }
                for t in (0...n).reversed() {
                    let px = aB + (bB - aB) * Double(t) / Double(n)
                    pts.append(p(px, top(px) + offsets[j + 1]))
                }
                let pick = Int(ukHash(0xF1E1DA + UInt64(j), i) * Double(fields.count)) % fields.count
                fill(pts, SceneColour.color(fields[pick]))
                // Cross hedge on the field's right edge.
                if i + 1 < xs.count - 1 {
                    stroke([p(b, top(b) + offsets[j]), p(bB, top(bB) + offsets[j + 1])], width: 1.5, hedge)
                }
            }
            // The hedge along the bottom of this row, with a tree here and there.
            if j + 1 < offsets.count - 1 {
                let line = (0...60).map { i -> CGPoint in
                    let px = -0.05 + 1.1 * Double(i) / 60
                    return p(px, top(px) + offsets[j + 1])
                }
                stroke(line, width: 2.2, hedge)
                for i in stride(from: 3, to: 60, by: 7) {
                    let px = -0.05 + 1.1 * Double(i) / 60 + 0.01 * ukHash(0xF1E1DF, i + j * 100)
                    let c = p(px, top(px) + offsets[j + 1] - 0.003)
                    ellipse(c, 0.014 * unit, 0.011 * unit, hedge)
                }
            }
        }
        // Trees along the skyline.
        for px in [0.07, 0.21, 0.66, 0.93] {
            ellipse(p(px, top(px) - 0.002), 0.016 * unit, 0.013 * unit, hedge)
        }
        // Sheep on a hillside: off-white bodies with dark faces.
        let wool = Color(hex: 0xF3F0E6), face = Color(hex: 0x3F3A36)
        for (i, px) in [0.545, 0.575, 0.6, 0.63, 0.905].enumerated() {
            let c = p(px, top(px) + 0.012 + 0.006 * Double(i % 2))
            ellipse(CGPoint(x: c.x, y: c.y + 1), 0.0125 * unit, 0.007 * unit, Color(hex: 0xC9C4B4))
            ellipse(c, 0.0125 * unit, 0.0075 * unit, wool)
            ellipse(CGPoint(x: c.x - 0.0075 * unit, y: c.y), 0.0045 * unit, 0.0045 * unit, face)
        }
    }

    /// A small church on a far ridge: a nave, a square tower and a spire.
    private func ukDrawChurch(base: Double, amp: Double, phase: Double, colour: RGB) {
        let x = 0.53
        let ground = p(x, ukRidgeY(x, base: base, amp: amp, phase: phase) + 0.004)
        let wall = SceneColour.color(colour)
        let roof = SceneColour.color(SceneColour.scaled(colour, 0.75))
        let u = unit
        // Nave and its roof.
        fill([CGPoint(x: ground.x - 0.017 * u, y: ground.y), CGPoint(x: ground.x + 0.013 * u, y: ground.y),
              CGPoint(x: ground.x + 0.013 * u, y: ground.y - 0.011 * u), CGPoint(x: ground.x - 0.017 * u, y: ground.y - 0.011 * u)], wall)
        fill([CGPoint(x: ground.x - 0.019 * u, y: ground.y - 0.011 * u), CGPoint(x: ground.x + 0.015 * u, y: ground.y - 0.011 * u),
              CGPoint(x: ground.x + 0.01 * u, y: ground.y - 0.016 * u), CGPoint(x: ground.x - 0.014 * u, y: ground.y - 0.016 * u)], roof)
        // Tower and spire, at the left end.
        let tx = ground.x - 0.021 * u
        fill([CGPoint(x: tx - 0.005 * u, y: ground.y), CGPoint(x: tx + 0.005 * u, y: ground.y),
              CGPoint(x: tx + 0.005 * u, y: ground.y - 0.028 * u), CGPoint(x: tx - 0.005 * u, y: ground.y - 0.028 * u)], wall)
        fill([CGPoint(x: tx - 0.0065 * u, y: ground.y - 0.028 * u), CGPoint(x: tx + 0.0065 * u, y: ground.y - 0.028 * u),
              CGPoint(x: tx, y: ground.y - 0.058 * u)], roof)
        fill([CGPoint(x: tx - 0.0015 * u, y: ground.y - 0.024 * u), CGPoint(x: tx + 0.0015 * u, y: ground.y - 0.024 * u),
              CGPoint(x: tx + 0.0015 * u, y: ground.y - 0.017 * u), CGPoint(x: tx - 0.0015 * u, y: ground.y - 0.017 * u)], roof)
    }

    // MARK: Ground (drifted camera)

    /// The lawn, a stone-edged flowerbed down each side, and flagstones at the front. Everything stays out of the
    /// bed's way: the beds hug the side walls and the flagstones start below the front of the patch.
    func ukDrawGround() {
        let grass = ukGrass()
        fillRect(-0.05, fenceBaseY - 0.005, 1.05, 1.05, SceneColour.color(grass))
        let lighter = SceneColour.color(SceneColour.lerp(grass, RGB(0.95, 1, 0.75), 0.14))
        let darker = SceneColour.color(SceneColour.scaled(grass, 0.9))
        let patches: [(x: Double, y: Double, w: Double, h: Double, c: Color)] = [
            (0.18, 0.46, 0.5, 0.05, lighter), (0.80, 0.56, 0.6, 0.06, darker),
            (0.3, 0.97, 0.5, 0.05, lighter), (0.92, 0.72, 0.4, 0.05, lighter), (0.06, 0.66, 0.3, 0.05, darker),
        ]
        for patch in patches { ellipse(p(patch.x, patch.y), patch.w * unit, patch.h * unit, patch.c) }
        // Daisies and clover dotted over the grass.
        let daisy = Color(hex: 0xFFFDF2), centre = Color(hex: 0xF2C94C)
        for i in 0..<46 {
            let c = p(-0.02 + 1.04 * ukHash(0xDA151, i * 2), 0.31 + 0.7 * ukHash(0xDA151, i * 2 + 1))
            ellipse(c, 0.006 * unit, 0.0045 * unit, daisy)
            ellipse(c, 0.0025 * unit, 0.002 * unit, centre)
        }
        ukDrawSideBeds()
        ukDrawFlagstones()
    }

    /// A polygon blob on the ground around a world point, with a little jitter per corner.
    private func ukGroundBlob(x: Double, z: Double, rx: Double, rz: Double, seed: UInt64, _ color: Color) {
        let pts = (0..<9).map { k -> CGPoint in
            let a = Double(k) / 9 * 2 * Double.pi
            let j = 0.82 + 0.3 * ukHash(seed, k)
            return world(x: x + cos(a) * rx * j, z: z + sin(a) * rz * j)
        }
        fill(pts, color)
    }

    private func ukDrawFlagstones() {
        let stone = [Color(hex: 0xC4BEAE), Color(hex: 0xB8B1A0), Color(hex: 0xCBBFA5)]
        let shade = Color(hex: 0x9A9486)
        var n = 0
        for (row, z) in (style == .backyard ? [2.5, 2.85] : [3.0, 3.45]).enumerated() {
            for col in -1...1 {
                let x = Double(col) * 0.5 + (ukHash(0xF1A6, n) - 0.5) * 0.14 + (row % 2 == 0 ? 0.0 : 0.3)
                let zz = z + (ukHash(0xF1A7, n) - 0.5) * 0.08
                let seed = UInt64(0xF1A80 + n * 16)
                ukGroundBlob(x: x, z: zz + 0.025, rx: 0.21, rz: 0.1, seed: seed, shade)
                ukGroundBlob(x: x, z: zz, rx: 0.21, rz: 0.1, seed: seed, stone[n % stone.count])
                n += 1
            }
        }
    }

    /// A stone-edged cottage flowerbed along the inside of each side wall: pebbles along the edge, then foxgloves,
    /// delphiniums and mounds of flowers from back to front.
    private func ukDrawSideBeds() {
        let soil = SceneColour.color(SceneColour.lerp(palette.soil, RGB(0.25, 0.18, 0.12), 0.25))
        let z0 = SceneCanvas.fenceZ + 0.1, z1 = 2.85
        for (side, sign) in [-1.0, 1.0].enumerated() {
            let xIn = sign * 3.85, xOut = sign * 4.42
            fill([world(x: xIn, z: z0), world(x: xOut, z: z0), world(x: xOut, z: z1), world(x: xIn, z: z1)], soil)
            // Edging stones along the inner edge.
            var z = z0 + 0.1
            var n = 0
            while z < z1 {
                let seed = UInt64(0xED6E0 + side * 100 + n)
                let tone = [Color(hex: 0xBDB8AA), Color(hex: 0xA9A294), Color(hex: 0xC9BFA6)][n % 3]
                ukGroundBlob(x: xIn, z: z + 0.015, rx: 0.1, rz: 0.1, seed: seed, Color(hex: 0x7D776A))
                ukGroundBlob(x: xIn, z: z, rx: 0.1, rz: 0.1, seed: seed, tone)
                z += 0.2 + 0.06 * ukHash(seed, 20)
                n += 1
            }
            // Flowers back to front.
            let count = 22
            for i in 0..<count {
                let t = (Double(i) + 0.7 * ukHash(0xF10E0 + UInt64(side), i)) / Double(count)
                let fz = z0 + 0.1 + (z1 - z0 - 0.2) * t
                let fx = (xIn + xOut) / 2 + (ukHash(0xF10E9 + UInt64(side), i) - 0.5) * 0.4
                ukDrawBedFlower(x: fx, z: fz, kind: Int(ukHash(0xF10EA + UInt64(side), i) * 4) % 4, i: i + side * 50)
            }
        }
    }

    private func ukDrawBedFlower(x: Double, z: Double, kind: Int, i: Int) {
        let s = screenPerUnit(x: x, y: 0, z: z)
        let g = at3(x, 0, z)
        let leaf = Color(hex: 0x4E8A44), leafShade = Color(hex: 0x3B6B35)
        func P(_ dx: Double, _ h: Double) -> CGPoint { CGPoint(x: g.x + CGFloat(dx) * s, y: g.y - CGFloat(h) * s) }
        // Leaves at the base.
        ellipse(P(0.02, 0.1), 0.62 * s, 0.34 * s, leafShade)
        ellipse(P(0, 0.12), 0.58 * s, 0.32 * s, leaf)
        let spikes: [UInt32] = [0xB45FA8, 0x5B7FD6, 0xE58FB3, 0xF2D35B]
        let heads: [UInt32] = [0xF29DB5, 0xF2C94C, 0xFFFDF2, 0xF08A4B, 0xA58BD3]
        if kind < 2 {
            // Tall spike: foxglove or delphinium.
            let colour = Color(hex: spikes[(kind + i) % 3])
            let height = 0.7 + 0.35 * ukHash(0x5B1CE, i)
            stroke([P(0, 0.1), P(0.02, height)], width: 0.035 * s, leaf)
            let bells = 7
            for b in 0..<bells {
                let t = Double(b) / Double(bells)
                let h = height * (0.4 + 0.6 * t)
                let r = (0.085 - 0.055 * t) * s
                let side: Double = b % 2 == 0 ? -0.045 : 0.05
                let c = P(side * (1 - 0.5 * t), h)
                ellipse(c, r * 2, r * 2.1, colour)
            }
        } else {
            // A mound with round flowers.
            ellipse(P(0, 0.26), 0.8 * s, 0.5 * s, leaf)
            let colour = Color(hex: heads[(i * 3 + kind) % heads.count])
            for b in 0..<7 {
                let a = ukHash(0xB10B0, i * 8 + b) * 2 * Double.pi
                let r = 0.28 * ukHash(0xB10B1, i * 8 + b)
                let c = P(cos(a) * r, 0.3 + sin(a) * r * 0.55)
                ellipse(c, 0.17 * s, 0.15 * s, colour)
                ellipse(c, 0.06 * s, 0.05 * s, Color(hex: 0xF2C94C))
            }
        }
    }

    // MARK: Foreground (foreground layer)

    func ukDrawForeground() {
        ukDrawTufts()
        ukDrawWellies(at: p(0.92, 0.955), size: 0.1 * unit)
        drawRestingWateringCan()
    }

    /// Clover leaves and a few daisies at the bottom left, in place of the farm's grass tufts.
    private func ukDrawTufts() {
        let blade = SceneColour.color(SceneColour.scaled(ukGrass(), 0.7))
        let clover = SceneColour.color(SceneColour.scaled(ukGrass(), 0.82))
        let spots: [(x: Double, y: Double)] = [(0.05, 0.97), (0.11, 0.99), (0.2, 0.98)]
        for (n, spot) in spots.enumerated() {
            let base = p(spot.x, spot.y)
            for b in 0..<5 {
                let angle = -Double.pi / 2 + (Double(b) - 2) * 0.38
                let len = 0.03 * unit * (0.8 + 0.2 * CGFloat(b % 3))
                let tip = CGPoint(x: base.x + CGFloat(cos(angle)) * len, y: base.y + CGFloat(sin(angle)) * len)
                stroke([base, tip], width: 0.004 * unit, blade)
                // A clover leaf (three little lobes) at the tip of some blades.
                if b % 2 == 0 {
                    for k in 0..<3 {
                        let a = Double(k) * 2 * Double.pi / 3 - Double.pi / 2
                        ellipse(CGPoint(x: tip.x + CGFloat(cos(a)) * 0.006 * unit, y: tip.y + CGFloat(sin(a)) * 0.006 * unit - 0.004 * unit),
                                0.009 * unit, 0.008 * unit, clover)
                    }
                }
            }
            // A daisy on a stem beside the tuft.
            let stem = CGPoint(x: base.x + (n % 2 == 0 ? 0.02 : -0.02) * unit, y: base.y - 0.045 * unit)
            stroke([CGPoint(x: base.x + (n % 2 == 0 ? 0.008 : -0.008) * unit, y: base.y), stem], width: 0.0025 * unit, blade)
            for k in 0..<7 {
                let a = Double(k) / 7 * 2 * Double.pi
                ellipse(CGPoint(x: stem.x + CGFloat(cos(a)) * 0.007 * unit, y: stem.y + CGFloat(sin(a)) * 0.007 * unit),
                        0.0075 * unit, 0.0055 * unit, Color(hex: 0xFFFDF2))
            }
            ellipse(stem, 0.007 * unit, 0.006 * unit, Color(hex: 0xF2C94C))
        }
    }

    /// A galvanised watering can: a tapered zinc body with ribs and a highlight, a big arch handle, a back handle
    /// and a long spout with a rose. `at` is the base centre.
    func ukDrawWateringCan(at base: CGPoint, size u: CGFloat) {
        let zinc = Color(hex: 0xB9C4CB), zincShade = Color(hex: 0x8794A0), rib = Color(hex: 0xA0ACB6), shine = Color(hex: 0xDDE5E9)
        func P(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: base.x + dx * u, y: base.y + dy * u) }
        let body = [P(-0.36, 0), P(0.36, 0), P(0.31, -0.58), P(-0.31, -0.58)]
        // Spout first, so the body sits over its root.
        var spout = Path()
        spout.move(to: P(0.26, -0.14))
        spout.addLine(to: P(0.92, -0.82))
        ctx.stroke(spout, with: .color(zincShade), style: StrokeStyle(lineWidth: 0.13 * u, lineCap: .round))
        ctx.stroke(spout, with: .color(zinc), style: StrokeStyle(lineWidth: 0.075 * u, lineCap: .round))
        let rose = CGRect(x: base.x + 0.82 * u, y: base.y - 0.95 * u, width: 0.2 * u, height: 0.15 * u)
        ctx.fill(Path(roundedRect: rose, cornerRadius: 0.05 * u), with: .color(zincShade))
        ctx.fill(Path(roundedRect: rose.insetBy(dx: 0.02 * u, dy: 0.02 * u), cornerRadius: 0.04 * u), with: .color(zinc))
        // Handles behind the body.
        var arch = Path()
        arch.move(to: P(-0.27, -0.56))
        arch.addQuadCurve(to: P(0.27, -0.56), control: P(0, -1.3))
        ctx.stroke(arch, with: .color(zincShade), style: StrokeStyle(lineWidth: 0.075 * u, lineCap: .round))
        var back = Path()
        back.move(to: P(-0.33, -0.1))
        back.addQuadCurve(to: P(-0.31, -0.5), control: P(-0.7, -0.3))
        ctx.stroke(back, with: .color(zincShade), style: StrokeStyle(lineWidth: 0.07 * u, lineCap: .round))
        // Body: shade layer, body, ribs, a highlight stripe and the open top.
        fill(body.map { CGPoint(x: $0.x + 0.03 * u, y: $0.y + 0.03 * u) }, zincShade)
        fill(body, zinc)
        for y in [-0.18, -0.4] as [CGFloat] { stroke([P(-0.34 + (-y - 0.18) * 0.1, y), P(0.34 - (-y - 0.18) * 0.1, y)], width: 0.035 * u, rib) }
        stroke([P(-0.22, -0.08), P(-0.2, -0.5)], width: 0.05 * u, shine)
        ellipse(P(0, -0.58), 0.62 * u, 0.12 * u, rib)
        ellipse(P(0, -0.58), 0.5 * u, 0.08 * u, Color(hex: 0x56626D))
    }

    /// A pair of green wellies standing side by side, toes to the left.
    private func ukDrawWellies(at base: CGPoint, size u: CGFloat) {
        let green = Color(hex: 0x5E8F4A), shade = Color(hex: 0x426B33), rim = Color(hex: 0x7DAE62)
        let sole = Color(hex: 0x2E3B25), shine = Color(hex: 0x8FBF74)
        for (i, dx) in [CGFloat(0.0), 0.3].enumerated() {
            let o = CGPoint(x: base.x + dx * u, y: base.y - (i == 1 ? 0.012 * u : 0))
            func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * u, y: o.y + y * u) }
            var boot = Path()
            boot.move(to: P(0.12, 0))
            boot.addLine(to: P(-0.24, 0))
            boot.addQuadCurve(to: P(-0.3, -0.13), control: P(-0.31, -0.01))
            boot.addQuadCurve(to: P(-0.1, -0.22), control: P(-0.2, -0.2))
            boot.addLine(to: P(-0.09, -0.78))
            boot.addLine(to: P(0.12, -0.78))
            boot.closeSubpath()
            ctx.fill(boot.offsetBy(dx: 0.025 * u, dy: 0.02 * u), with: .color(shade))
            ctx.fill(boot, with: .color(green))
            // Sole, the top rim and a highlight down the shaft.
            ctx.fill(Path(roundedRect: CGRect(x: o.x - 0.31 * u, y: o.y - 0.045 * u, width: 0.43 * u, height: 0.045 * u),
                          cornerRadius: 0.02 * u), with: .color(sole))
            ctx.fill(Path(roundedRect: CGRect(x: o.x - 0.1 * u, y: o.y - 0.78 * u, width: 0.22 * u, height: 0.07 * u),
                          cornerRadius: 0.025 * u), with: .color(rim))
            stroke([P(-0.05, -0.65), P(-0.05, -0.3)], width: 0.03 * u, shine)
        }
        // A contact shadow under the pair.
        propShadow(foot: CGPoint(x: base.x + 0.1 * u, y: base.y + 0.04 * u), height: 0.8 * u, width: 0.9 * u, depth: 0.07 * u, opacity: 0.12)
    }
}
