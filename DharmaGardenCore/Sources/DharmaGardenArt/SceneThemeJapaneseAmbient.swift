import SwiftUI
import DharmaGardenCore

/// The Japanese theme's foreground (a stone lantern and moss clumps), the lantern itself, and the ambient touches:
/// petals or maple leaves drifting across the scene, and a warm glow in the lanterns and the tea house at dusk and
/// night. The glow draws in the weather pass, over the darkness overlay, so it stays lit.
extension SceneCanvas {
    // MARK: Foreground

    /// Where the foreground lantern stands (its base centre) and its unit size, at the lower right.
    var japaneseForegroundLantern: (base: CGPoint, u: CGFloat) { (p(0.87, 0.95), 0.085 * unit) }

    func drawJapaneseForeground() {
        for (x, y, w) in [(0.05, 0.97, 0.07), (0.37, 0.992, 0.055), (0.62, 0.997, 0.05)] {
            drawJapaneseMoss(at: p(x, y), width: w * unit)
        }
        drawRestingWateringCan()
        let lantern = japaneseForegroundLantern
        drawJapaneseStoneLantern(base: lantern.base, u: lantern.u, glowing: palette.darkness)
    }

    /// A low moss clump: shade copy, body, lighter bumps and a few darker flecks. `at` is the base centre.
    private func drawJapaneseMoss(at c: CGPoint, width w: CGFloat) {
        let moss = Color(hex: 0x5F8F50), shade = Color(hex: 0x3F6A3A), light = Color(hex: 0x86B466)
        ellipse(CGPoint(x: c.x + 1.5, y: c.y + 2), w, w * 0.5, shade)
        ellipse(c, w, w * 0.5, moss)
        for (dx, dy, k) in [(-0.28, -0.12, 0.34), (0.05, -0.2, 0.4), (0.3, -0.1, 0.3), (-0.05, 0.0, 0.3)] {
            ellipse(CGPoint(x: c.x + CGFloat(dx) * w, y: c.y + CGFloat(dy) * w), w * k, w * k * 0.7, light)
        }
        for (dx, dy) in [(-0.35, 0.08), (0.2, 0.1), (0.38, 0.0)] {
            ellipse(CGPoint(x: c.x + CGFloat(dx) * w, y: c.y + CGFloat(dy) * w), w * 0.07, w * 0.05, shade)
        }
    }

    /// A stone lantern (ishidoro): base slab, tapered post, platform, fire box with a lit window, a curved hat with a
    /// finial, and moss in the cracks. `base` is the centre of the foot and `u` the unit (about 0.87 of its height);
    /// `glowing` is the palette's darkness, which lights the window warmly. Returns the window.
    @discardableResult
    func drawJapaneseStoneLantern(base b: CGPoint, u: CGFloat, glowing darkness: Double) -> CGRect {
        let stone = Color(hex: 0xA9A79E), shade = Color(hex: 0x7E7C73), light = Color(hex: 0xC6C3B8), moss = Color(hex: 0x6E9A5A)
        let lit = smooth(darkness, 0.1, 0.3)
        func box(_ w: CGFloat, _ y0: CGFloat, _ h: CGFloat, _ cx: CGFloat = 0) {
            let r = CGRect(x: b.x + (cx - w / 2) * u, y: b.y - (y0 + h) * u, width: w * u, height: h * u)
            ctx.fill(Path(r.offsetBy(dx: 0.03 * u, dy: 0.02 * u)), with: .color(shade))
            ctx.fill(Path(r), with: .color(stone))
            ctx.fill(Path(CGRect(x: r.minX, y: r.minY, width: r.width, height: max(1, 0.025 * u))), with: .color(light))
        }
        // Ground shadow.
        propShadow(foot: CGPoint(x: b.x, y: b.y + 0.02 * u), height: 1.6 * u, width: 0.9 * u, depth: 0.2 * u, opacity: 0.16)
        // Base slab.
        let slab = CGRect(x: b.x - 0.4 * u, y: b.y - 0.09 * u, width: 0.8 * u, height: 0.09 * u)
        ctx.fill(Path(slab.offsetBy(dx: 0.03 * u, dy: 0.02 * u)), with: .color(shade))
        ctx.fill(Path(slab), with: .color(stone))
        ctx.fill(Path(CGRect(x: slab.minX, y: slab.minY, width: slab.width, height: 0.025 * u)), with: .color(light))
        // Post: slightly tapered, with a shade strip on the right.
        let post = [CGPoint(x: b.x - 0.13 * u, y: b.y - 0.09 * u), CGPoint(x: b.x + 0.13 * u, y: b.y - 0.09 * u),
                    CGPoint(x: b.x + 0.1 * u, y: b.y - 0.5 * u), CGPoint(x: b.x - 0.1 * u, y: b.y - 0.5 * u)]
        fill(post.map { CGPoint(x: $0.x + 0.025 * u, y: $0.y) }, shade)
        fill(post, stone)
        stroke([CGPoint(x: b.x - 0.1 * u, y: b.y - 0.13 * u), CGPoint(x: b.x - 0.075 * u, y: b.y - 0.46 * u)], width: max(1, 0.02 * u), light)
        // Platform and the fire box, with its window.
        box(0.62, 0.5, 0.08)
        box(0.44, 0.58, 0.3)
        let window = CGRect(x: b.x - 0.1 * u, y: b.y - 0.8 * u, width: 0.2 * u, height: 0.17 * u)
        ctx.fill(Path(window), with: .color(mix(0x34322E, 0xFFCB6E, lit)))
        ctx.fill(Path(CGRect(x: window.minX, y: window.minY, width: window.width, height: 0.025 * u)), with: .color(shade))
        // Hat: a broad hexagonal roof with curled-up eaves, in a flat trapezoid, then the jewel finial.
        let eaveY = b.y - 0.88 * u, topY = b.y - 1.1 * u
        let hat = [CGPoint(x: b.x - 0.58 * u, y: eaveY - 0.05 * u), CGPoint(x: b.x - 0.46 * u, y: eaveY + 0.03 * u),
                   CGPoint(x: b.x + 0.46 * u, y: eaveY + 0.03 * u), CGPoint(x: b.x + 0.58 * u, y: eaveY - 0.05 * u),
                   CGPoint(x: b.x + 0.12 * u, y: topY), CGPoint(x: b.x - 0.12 * u, y: topY)]
        fill(hat.map { CGPoint(x: $0.x + 0.03 * u, y: $0.y + 0.02 * u) }, shade)
        fill(hat, stone)
        fill([hat[0], hat[1], hat[2], hat[3], CGPoint(x: b.x + 0.5 * u, y: eaveY - 0.07 * u), CGPoint(x: b.x - 0.5 * u, y: eaveY - 0.07 * u)], light.opacity(0.55))
        for dx in [-0.46, -0.16, 0.16, 0.46] {
            stroke([CGPoint(x: b.x + CGFloat(dx) * u, y: eaveY), CGPoint(x: b.x + CGFloat(dx) * 0.25 * u, y: topY)], width: max(1, 0.02 * u), shade.opacity(0.6))
        }
        stroke([CGPoint(x: b.x - 0.12 * u, y: topY), CGPoint(x: b.x + 0.12 * u, y: topY)], width: max(1, 0.03 * u), light)
        let fin = CGPoint(x: b.x, y: topY - 0.06 * u)
        ellipse(CGPoint(x: fin.x + 0.01 * u, y: fin.y + 0.01 * u), 0.14 * u, 0.15 * u, shade)
        ellipse(fin, 0.14 * u, 0.15 * u, stone)
        ellipse(CGPoint(x: fin.x, y: topY + 0.01 * u), 0.16 * u, 0.05 * u, shade)
        // Moss on the slab, the platform and the hat.
        for (dx, dy, w) in [(-0.3, -0.09, 0.2), (0.28, -0.09, 0.14), (-0.2, -0.57, 0.16), (0.1, -1.02, 0.12), (-0.38, -0.9, 0.12)] {
            ellipse(CGPoint(x: b.x + CGFloat(dx) * u, y: b.y + CGFloat(dy) * u), w * u, w * u * 0.4, moss)
        }
        return window
    }

    // MARK: Ambient

    private enum JapaneseSeason { case spring, summer, autumn, winter }

    /// The season as the palette shows it: autumn foliage is orange (red above green), spring's is light and fresh,
    /// summer's a deep yellow-green and winter's grey.
    private var japaneseSeason: JapaneseSeason {
        let f = palette.foliage
        if f.r > f.g { return .autumn }
        if f.b > 0.4 && f.g > 0.7 { return .spring }
        if f.g - f.b > 0.2 { return .summer }
        return .winter
    }

    func drawJapaneseAmbient() {
        drawJapaneseGlows()
        drawJapaneseDrift()
    }

    /// Warm glow over the lantern windows and the lit tea house screens, from dusk. The glows sit at the scene
    /// layers' own parallax shifts (the lantern in front is in the foreground layer, the rest in the fence layer).
    private func drawJapaneseGlows() {
        let lit = smooth(palette.darkness, 0.1, 0.3)
        guard lit > 0.01 else { return }
        let warm = Color(hex: 0xFFC25E)
        let saved = ctx
        defer { ctx = saved }
        func glow(_ c: CGPoint, radius r: CGFloat, strength: Double) {
            let grad = GraphicsContext.Shading.radialGradient(
                Gradient(colors: [warm.opacity(strength * lit), warm.opacity(strength * lit * 0.35), warm.opacity(0)]),
                center: c, startRadius: 0, endRadius: r)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: grad)
        }
        let fg = motion.layerShift(.foreground)
        ctx.translateBy(x: CGFloat(fg.x) * size.width, y: CGFloat(fg.y) * size.height)
        let l = japaneseForegroundLantern
        let wc = CGPoint(x: l.base.x, y: l.base.y - 0.72 * l.u)
        glow(wc, radius: 1.5 * l.u, strength: 0.5)
        ctx.fill(Path(CGRect(x: wc.x - 0.1 * l.u, y: wc.y - 0.085 * l.u, width: 0.2 * l.u, height: 0.17 * l.u)),
                 with: .color(Color(hex: 0xFFE2A0).opacity(0.75 * lit)))
        ctx.transform = saved.transform
        guard style == .backyard else { return }
        let fence = motion.layerShift(.fence)
        ctx.translateBy(x: CGFloat(fence.x) * size.width, y: CGFloat(fence.y) * size.height)
        let w = japaneseWallLantern()
        glow(CGPoint(x: w.base.x, y: w.base.y - 0.72 * w.u), radius: 1.3 * w.u, strength: 0.45)
        for q in japaneseShojiQuads() {
            let c = CGPoint(x: q.map(\.x).reduce(0, +) / 4, y: q.map(\.y).reduce(0, +) / 4)
            glow(c, radius: 0.75 * abs(q[1].x - q[0].x), strength: 0.28)
        }
    }

    /// Petals (pink, in spring), maple leaves (autumn) and a few pale leaves otherwise, drifting down and across on the
    /// wind. Each one's path is a pure function of the motion time, so the same frame draws the same picture.
    private func drawJapaneseDrift() {
        let season = japaneseSeason
        let count: Int
        switch season {
        case .spring: count = 24
        case .autumn: count = 20
        case .summer: count = 8
        case .winter: count = 6
        }
        let t = motion.time, wind = motion.wind
        let dim = 1 - 0.45 * smooth(palette.darkness, 0.2, 0.55)
        for i in 0..<count {
            let k = UInt64(i * 6)
            let h0 = unitHash(0x1A7E, k), h1 = unitHash(0x1A7E, k + 1), h2 = unitHash(0x1A7E, k + 2)
            let h3 = unitHash(0x1A7E, k + 3), h4 = unitHash(0x1A7E, k + 4), h5 = unitHash(0x1A7E, k + 5)
            let fall = 0.022 + 0.022 * h1                       // scene heights per second
            let across = (0.014 + 0.05 * wind) * (0.6 + 0.8 * h2)   // scene widths per second
            let fy = h0 + t * fall, fx = h3 + t * across
            let y = -0.05 + 1.1 * (fy - floor(fy))
            let x = -0.05 + 1.1 * (fx - floor(fx)) + 0.012 * sin(t * 1.3 + h4 * 6.28)
            let edge = min(1, (y + 0.05) * 12, (1.05 - y) * 12)
            let spin = t * (0.7 + 1.2 * h2) + h5 * 6.28
            let u = (0.0075 + 0.004 * h5) * unit
            let c = p(x, y)
            var g = ctx
            g.translateBy(x: c.x, y: c.y)
            g.rotate(by: .radians(spin))
            // Flutter: squash one axis with time, so the piece seems to turn over as it falls.
            g.scaleBy(x: 1, y: CGFloat(0.45 + 0.55 * abs(cos(t * 1.4 + h4 * 6.28))))
            switch season {
            case .autumn:
                var leaf = Path()
                for v in 0..<10 {
                    let a = Double(v) * Double.pi / 5, r = (v % 2 == 0 ? 1.0 : 0.5) * Double(u) * 1.5
                    let q = CGPoint(x: CGFloat(cos(a) * r), y: CGFloat(sin(a) * r))
                    if v == 0 { leaf.move(to: q) } else { leaf.addLine(to: q) }
                }
                leaf.closeSubpath()
                g.fill(leaf, with: .color((i % 2 == 0 ? Color(hex: 0xD2452C) : Color(hex: 0xE88C3A)).opacity(0.9 * edge * dim)))
            case .spring, .winter:
                let petal = CGRect(x: -u * 0.9, y: -u * 0.5, width: u * 1.8, height: u)
                let pink = season == .spring ? Color(hex: i % 3 == 0 ? 0xFFD3E0 : 0xF7A9C0) : Color(hex: 0xF4F1EC)
                g.fill(Path(ellipseIn: petal), with: .color(pink.opacity(0.92 * edge * dim)))
            case .summer:
                let leaf = CGRect(x: -u * 1.0, y: -u * 0.4, width: u * 2, height: u * 0.8)
                g.fill(Path(ellipseIn: leaf), with: .color(Color(hex: 0xB5D08A).opacity(0.85 * edge * dim)))
            }
        }
    }
}
