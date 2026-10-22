import SwiftUI
import DharmaGardenCore

/// Numbers shared by the Urban theme's files: where things stand in world units.
enum UrbanScene {
    /// How far the back fence runs each way in the first-person view, which has no side fences: past both frame edges.
    static let firstPersonHalfLength = 7.5
    /// Depth (z) of the terrace houses' back walls and of the neighbour's tree, behind the fence.
    static let houseZ = -7.2
    static let treeZ = -5.6
    /// The paving strip between the back fence and the bed (z range), and the side patios (x range).
    static let backPaving = (near: -2.97, far: -3.27)
    static let sidePaving = (inner: 3.3, outer: 4.2)
}

/// The Urban theme's scene hooks, called by the dispatchers in SceneTheme.swift. The drawing is split by subject:
/// the fence in SceneThemeUrbanFence.swift, the skyline in SceneThemeUrbanSkyline.swift, the houses and tree in
/// SceneThemeUrbanHouses.swift, the clutter in SceneThemeUrbanProps.swift and the lights, cat and smoke in
/// SceneThemeUrbanAmbient.swift. All colours that follow the season, weather or time of day come from the palette.
extension SceneCanvas {
    /// A multiple of a 0xRRGGBB colour (below 1 darkens it).
    func urbanTone(_ hex: UInt32, _ f: Double = 1) -> Color {
        Color(red: min(1, Double((hex >> 16) & 255) / 255 * f), green: min(1, Double((hex >> 8) & 255) / 255 * f),
              blue: min(1, Double(hex & 255) / 255 * f))
    }

    /// The same, as an `RGB` for blending with the palette.
    func urbanRGB(_ hex: UInt32, _ f: Double = 1) -> RGB { SceneColour.scaled(RGB(hex: hex), f) }

    /// How lit the evening is: 0 by day, 1 once it is properly dark. Lights and lit windows follow it.
    var urbanLit: Double { smooth(palette.darkness, 0.1, 0.35) }

    /// Screen y of the top of the urban fence (the cap on a post) at the back.
    var urbanFenceTopY: Double { camera.upright(x: 0, z: Self.fenceZ, height: UrbanFence.height + UrbanFence.postRise).y }

    /// A canvas for things that stand on the lawn but are drawn in the fence layer (so they can sit in front of the
    /// side fences): it undoes the fence layer's parallax and uses the drifted camera, so they land exactly where
    /// the ground layer puts the lawn under them.
    func urbanGroundAligned() -> SceneCanvas {
        var g = ctx
        let s = motion.layerShift(.fence)
        g.translateBy(x: -CGFloat(s.x) * size.width, y: -CGFloat(s.y) * size.height)
        let c = SceneCanvas(ctx: g, size: size, camera: SceneMotion.camera(camera, frame: motion), palette: palette,
                            motion: motion, style: style, theme: theme)
        c.soilLift = soilLift
        return c
    }

    // MARK: Sky

    /// A paler, hazier city sky: lighter toward the horizon, where the haze gathers.
    func urbanSky() {
        let haze = RGB(0.93, 0.92, 0.89)
        // Night keeps its colour: the haze only lifts the day and the glow of dusk.
        let pale = 0.3 * (1 - min(1, palette.darkness * 1.6))
        let top = SceneColour.lerp(palette.skyTop, haze, pale * 0.55)
        let mid = SceneColour.lerp(palette.skyBottom, haze, pale)
        let band = SceneColour.lerp(palette.skyBottom, haze, min(1, pale * 1.9))
        let grad = GraphicsContext.Shading.linearGradient(
            Gradient(stops: [.init(color: SceneColour.color(top), location: 0), .init(color: SceneColour.color(mid), location: 0.6),
                             .init(color: SceneColour.color(band), location: 1)]),
            startPoint: p(0, 0), endPoint: p(0, fenceBaseY))
        ctx.fill(Path(bleed(CGRect(origin: .zero, size: size))), with: grad)
    }

    /// A few small flat clouds (more when the palette is grey) and a thin contrail.
    func urbanClouds() {
        let greyness = 1 - min(1, SceneColour.chroma(palette.skyTop) / 0.4)
        let cloudy = min(1, palette.rainStrength + palette.fogStrength * 0.4 + greyness * 0.7)
        let base = SceneColour.lerp(RGB(0.99, 0.98, 0.96), palette.skyBottom, 0.15 + cloudy * 0.3)
        let cloud = SceneColour.color(base), shade = SceneColour.color(SceneColour.scaled(base, 0.91))
        let spots: [(x: Double, y: Double, s: Double)] = [
            (0.2, 0.1, 0.05), (0.7, 0.07, 0.056), (0.9, 0.19, 0.04), (0.44, 0.17, 0.034), (0.07, 0.2, 0.034),
        ]
        let count = 2 + Int(cloudy * 2.99)
        let travel = motion.cloudTravel
        for (i, spot) in spots.prefix(count).enumerated() {
            let x = Self.wrapCloudX(spot.x + travel * (1 + 0.25 * Double(i % 3)))
            urbanCloud(p(x, spot.y), r: spot.s * unit, cloud, shade)
        }
        // A jet's contrail: two soft strokes that fade away behind it, hidden when it is overcast.
        let trail = (1 - cloudy) * (1 - min(1, palette.darkness * 1.5))
        if trail > 0.05 {
            let a = p(0.5, 0.215), b = p(1.04, 0.03)
            let path = Path { $0.move(to: a); $0.addLine(to: b) }
            let grad = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [Color.white.opacity(0), Color.white.opacity(0.55 * trail)]), startPoint: a, endPoint: b)
            ctx.stroke(path, with: grad, style: StrokeStyle(lineWidth: 0.012 * unit, lineCap: .round))
            ctx.stroke(path, with: .linearGradient(Gradient(colors: [Color.white.opacity(0), Color.white.opacity(0.7 * trail)]),
                                                   startPoint: a, endPoint: b),
                       style: StrokeStyle(lineWidth: 0.004 * unit, lineCap: .round))
        }
    }

    private func urbanCloud(_ c: CGPoint, r: CGFloat, _ cloud: Color, _ shade: Color) {
        let parts: [(dx: CGFloat, dy: CGFloat, rad: CGFloat)] = [(-0.5, -0.05, 0.36), (0.1, -0.25, 0.5), (0.7, -0.02, 0.34)]
        func draw(_ o: CGFloat, _ color: Color) {
            let body = CGRect(x: c.x - 1.2 * r, y: c.y - 0.3 * r + o, width: 2.4 * r, height: 0.6 * r)
            ctx.fill(Path(roundedRect: body, cornerRadius: 0.3 * r), with: .color(color))
            for part in parts {
                let rad = part.rad * r
                ctx.fill(Path(ellipseIn: CGRect(x: c.x + part.dx * r - rad, y: c.y + part.dy * r - rad + o, width: rad * 2, height: rad * 2)),
                         with: .color(color))
            }
        }
        draw(0.06 * r, shade)
        draw(0, cloud)
    }

    // MARK: Ground

    /// The lawn colour: the palette's grass, duller and greyer than the farm's.
    var urbanGrass: RGB {
        SceneColour.lerp(SceneColour.scaled(palette.grass, 0.97), RGB(0.52, 0.55, 0.46), 0.3)
    }

    /// A small lawn patch with paving around its edges: a row of slabs along the back fence, and (in the backyard) a
    /// patio down each side. Everything stays clear of the bed in the middle of the frame.
    func urbanGround() {
        let grass = urbanGrass
        fillRect(-0.05, fenceBaseY - 0.005, 1.05, 1.05, SceneColour.color(grass))
        let lighter = SceneColour.color(SceneColour.lerp(grass, RGB(1, 1, 0.85), 0.1))
        let darker = SceneColour.color(SceneColour.scaled(grass, 0.93))
        for patch in [(0.2, 0.47, 0.45, 0.045, lighter), (0.82, 0.58, 0.5, 0.05, darker), (0.32, 0.975, 0.45, 0.045, lighter)] {
            ellipse(p(patch.0, patch.1), patch.2 * unit, patch.3 * unit, patch.4)
        }
        let backyard = style == .backyard
        let half = backyard ? BarrierFrame.halfLength - 0.2 : UrbanScene.firstPersonHalfLength
        urbanPaving(x: -half...half, z: UrbanScene.backPaving.far...UrbanScene.backPaving.near, slab: (0.95, 0.45), seed: 1)
        if backyard {
            let s = UrbanScene.sidePaving
            urbanPaving(x: -s.outer ... -s.inner, z: -3.0...1.3, slab: (0.45, 0.55), seed: 2)
            urbanPaving(x: s.inner...s.outer, z: -3.0...1.3, slab: (0.45, 0.55), seed: 3)
        }
    }

    /// Concrete slabs in running bond over a range of the lawn, each a quad in perspective (so the joints converge),
    /// with a darker joint between them and a weed in a few of the cracks.
    private func urbanPaving(x xs: ClosedRange<Double>, z zs: ClosedRange<Double>, slab: (w: Double, d: Double), seed: UInt64) {
        let gap = 0.03
        let rows = max(1, Int(((zs.upperBound - zs.lowerBound) / slab.d).rounded()))
        let rowD = (zs.upperBound - zs.lowerBound) / Double(rows)
        func quad(_ x0: Double, _ x1: Double, _ z0: Double, _ z1: Double) -> [CGPoint] {
            [at3(x0, 0, z0), at3(x1, 0, z0), at3(x1, 0, z1), at3(x0, 0, z1)]
        }
        // The joint colour first, as one quad under all the slabs.
        fill(quad(xs.lowerBound, xs.upperBound, zs.lowerBound, zs.upperBound), urbanTone(0x8F8A80))
        var crossings: [(Double, Double)] = []
        for r in 0..<rows {
            let za = zs.lowerBound + Double(r) * rowD, zb = za + rowD
            var x = xs.lowerBound - (r % 2 == 0 ? 0 : slab.w / 2)
            var i = 0
            while x < xs.upperBound {
                let a = max(x, xs.lowerBound), b = min(x + slab.w, xs.upperBound)
                if b - a > 0.08 {
                    let t = unitHash(seed &* 977, UInt64(r * 40 + i))
                    let tone = 0.92 + 0.1 * t
                    let q = quad(a + gap / 2, b - gap / 2, za + gap / 2, zb - gap / 2)
                    fill(q.map { CGPoint(x: $0.x, y: $0.y + 1.4) }, urbanTone(0xA8A398, tone))
                    fill(q, urbanTone(0xD3CEC4, tone))
                    if unitHash(seed &* 31, UInt64(r * 40 + i)) > 0.8 { crossings.append((b, za)) }
                }
                x += slab.w
                i += 1
            }
        }
        // DharmaGarden in the cracks.
        let blade = SceneColour.color(SceneColour.scaled(urbanGrass, 0.85))
        for (k, c) in crossings.enumerated() where k % 2 == 0 {
            let base = at3(c.0, 0, c.1)
            let s = screenPerUnit(x: c.0, y: 0, z: c.1)
            for b in 0..<4 {
                let angle = -Double.pi / 2 + (Double(b) - 1.5) * 0.5
                let len = 0.09 * s * (0.8 + 0.2 * CGFloat(b % 2))
                stroke([base, CGPoint(x: base.x + CGFloat(cos(angle)) * len, y: base.y + CGFloat(sin(angle)) * len)],
                       width: max(1, 0.012 * s), blade)
            }
        }
    }

    // MARK: Foreground

    /// A plastic watering can and a terracotta pot plant at the lower right, and a few paving weeds at the lower left.
    func urbanForeground() {
        urbanPavingDharmaGarden()
        urbanWateringCan(at: p(0.775, 0.955), size: 0.085 * unit)
        urbanPotPlant(at: p(0.9, 0.965), size: 0.075 * unit)
    }

    /// A broken corner of paving at the bottom left, with dandelion-like weeds pushing up through the crack.
    private func urbanPavingDharmaGarden() {
        let slab = [p(-0.05, 0.965), p(0.2, 0.955), p(0.215, 1.05), p(-0.05, 1.05)]
        fill(slab.map { CGPoint(x: $0.x, y: $0.y - 2) }, urbanTone(0x8F8A80))
        fill(slab, urbanTone(0xD3CEC4))
        stroke([p(0.06, 0.957), p(0.075, 0.985), p(0.062, 1.01)], width: 1.6, urbanTone(0x8F8A80))
        let leaf = SceneColour.color(SceneColour.scaled(urbanGrass, 0.8)), leafLight = SceneColour.color(SceneColour.scaled(urbanGrass, 1.0))
        urbanWeed(at: p(0.072, 0.985), size: 0.05 * unit, leaf, leafLight, flower: true)
        urbanWeed(at: p(0.14, 0.99), size: 0.036 * unit, leaf, leafLight, flower: false)
        urbanWeed(at: p(0.035, 1.0), size: 0.03 * unit, leaf, leafLight, flower: false)
    }

    /// A weed rosette: toothed leaves fanning out of a crack, and optionally a yellow flower on a stem.
    private func urbanWeed(at base: CGPoint, size u: CGFloat, _ leaf: Color, _ light: Color, flower: Bool) {
        for b in 0..<7 {
            let angle = -Double.pi / 2 + (Double(b) - 3) * 0.42
            let len = u * (0.75 + 0.25 * CGFloat(b % 3))
            let tip = CGPoint(x: base.x + CGFloat(cos(angle)) * len, y: base.y + CGFloat(sin(angle)) * len * 0.9)
            stroke([base, tip], width: 0.2 * u, b % 2 == 0 ? leaf : light)
        }
        if flower {
            let top = CGPoint(x: base.x + 0.1 * u, y: base.y - 1.5 * u)
            stroke([base, top], width: 0.08 * u, leaf)
            ellipse(top, 0.5 * u, 0.5 * u, Color(hex: 0xE0A800))
            ellipse(CGPoint(x: top.x - 0.03 * u, y: top.y - 0.04 * u), 0.34 * u, 0.34 * u, Color(hex: 0xFFD23F))
        }
    }

    /// A flat plastic watering can in apple green: moulded body with a shade layer, a top handle, a back handle, a
    /// long spout and a rose. `at` is the base centre.
    private func urbanWateringCan(at base: CGPoint, size u: CGFloat) {
        let body = Color(hex: 0x58B880), shade = Color(hex: 0x3A9163), light = Color(hex: 0x86D4A3)
        let drop: CGFloat = 0.03 * u
        // Tapered body: wider at the base.
        let quad = [CGPoint(x: base.x - 0.52 * u, y: base.y), CGPoint(x: base.x + 0.24 * u, y: base.y),
                    CGPoint(x: base.x + 0.18 * u, y: base.y - 0.62 * u), CGPoint(x: base.x - 0.46 * u, y: base.y - 0.62 * u)]
        fill(quad.map { CGPoint(x: $0.x, y: $0.y + drop) }, shade)
        fill(quad, body)
        // Moulded rib and rim.
        stroke([CGPoint(x: base.x - 0.5 * u, y: base.y - 0.22 * u), CGPoint(x: base.x + 0.22 * u, y: base.y - 0.22 * u)], width: 0.04 * u, shade)
        ctx.fill(Path(roundedRect: CGRect(x: base.x - 0.5 * u, y: base.y - 0.68 * u, width: 0.72 * u, height: 0.08 * u), cornerRadius: 0.04 * u),
                 with: .color(light))
        // Big carry handle over the top, and a small one at the back.
        var handle = Path()
        handle.move(to: CGPoint(x: base.x - 0.4 * u, y: base.y - 0.66 * u))
        handle.addQuadCurve(to: CGPoint(x: base.x + 0.12 * u, y: base.y - 0.66 * u), control: CGPoint(x: base.x - 0.14 * u, y: base.y - 1.2 * u))
        ctx.stroke(handle, with: .color(shade), style: StrokeStyle(lineWidth: 0.1 * u, lineCap: .round))
        var back = Path()
        back.move(to: CGPoint(x: base.x - 0.48 * u, y: base.y - 0.5 * u))
        back.addQuadCurve(to: CGPoint(x: base.x - 0.5 * u, y: base.y - 0.12 * u), control: CGPoint(x: base.x - 0.78 * u, y: base.y - 0.3 * u))
        ctx.stroke(back, with: .color(shade), style: StrokeStyle(lineWidth: 0.08 * u, lineCap: .round))
        // Long spout up to the rose.
        let a = CGPoint(x: base.x + 0.2 * u, y: base.y - 0.16 * u), b = CGPoint(x: base.x + 0.92 * u, y: base.y - 0.86 * u)
        stroke([a, b], width: 0.12 * u, shade)
        stroke([a, b], width: 0.065 * u, body)
        ctx.fill(Path(roundedRect: CGRect(x: b.x - 0.07 * u, y: b.y - 0.1 * u, width: 0.24 * u, height: 0.15 * u), cornerRadius: 0.05 * u),
                 with: .color(light))
    }

    /// A terracotta pot with a bushy geranium. `at` is the base centre.
    private func urbanPotPlant(at base: CGPoint, size u: CGFloat) {
        let clay = Color(hex: 0xCF7B52), clayShade = Color(hex: 0xA55A3A), rim = Color(hex: 0xDE8D63)
        // Plant first, so the pot rim overlaps the stems.
        let leaf = SceneColour.color(SceneColour.scaled(palette.foliage, 0.92)), leafShade = SceneColour.color(SceneColour.scaled(palette.foliage, 0.72))
        let top = CGPoint(x: base.x, y: base.y - 0.85 * u)
        for (dx, dy, r) in [(-0.38, -0.42, 0.34), (0.38, -0.46, 0.32), (0.0, -0.68, 0.4), (-0.2, -0.95, 0.3), (0.24, -0.92, 0.3)] as [(CGFloat, CGFloat, CGFloat)] {
            let c = CGPoint(x: top.x + dx * u, y: top.y + dy * u + 0.5 * u)
            ellipse(CGPoint(x: c.x + 0.03 * u, y: c.y + 0.04 * u), 2 * r * u, 1.7 * r * u, leafShade)
            ellipse(c, 2 * r * u, 1.7 * r * u, leaf)
        }
        for (dx, dy) in [(-0.3, -1.05), (0.25, -1.15), (0.02, -0.82), (0.42, -0.78)] as [(CGFloat, CGFloat)] {
            let c = CGPoint(x: top.x + dx * u, y: top.y + dy * u + 0.5 * u)
            ellipse(c, 0.26 * u, 0.26 * u, Color(hex: 0xD9475A))
            ellipse(CGPoint(x: c.x - 0.03 * u, y: c.y - 0.03 * u), 0.14 * u, 0.14 * u, Color(hex: 0xF0788A))
        }
        // Tapered pot with a rim and a shade layer.
        let pot = [CGPoint(x: base.x - 0.36 * u, y: base.y - 0.62 * u), CGPoint(x: base.x + 0.36 * u, y: base.y - 0.62 * u),
                   CGPoint(x: base.x + 0.26 * u, y: base.y), CGPoint(x: base.x - 0.26 * u, y: base.y)]
        fill(pot.map { CGPoint(x: $0.x + 0.03 * u, y: $0.y) }, clayShade)
        fill(pot, clay)
        let r = CGRect(x: base.x - 0.42 * u, y: base.y - 0.76 * u, width: 0.84 * u, height: 0.17 * u)
        ctx.fill(Path(roundedRect: r.offsetBy(dx: 0.02 * u, dy: 0.03 * u), cornerRadius: 0.05 * u), with: .color(clayShade))
        ctx.fill(Path(roundedRect: r, cornerRadius: 0.05 * u), with: .color(rim))
    }
}
