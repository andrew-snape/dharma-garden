import SwiftUI
import DharmaGardenCore

/// The Japanese theme's scene hooks, called by the dispatchers in SceneTheme.swift. The drawing lives in this file
/// (sky, clouds, mountains) and in the `SceneThemeJapanese*` files beside it: the wall (`...Wall`), the tea house and
/// trees (`...Backdrop`), the gravel and stones (`...Ground`) and the lantern, moss and drifting petals (`...Ambient`).
/// Colours come from the palette, so season, weather, dusk and night still work.
extension SceneCanvas {
    func japaneseSky() {
        // Paler, slightly warmer and a touch greyer than the farm's sky; the warm lift fades as the light does.
        let day = 1 - min(1, palette.darkness * 2.2)
        func soft(_ c: RGB, _ warm: Double) -> RGB {
            let l = 0.3 * c.r + 0.59 * c.g + 0.11 * c.b
            let grey = SceneColour.lerp(c, RGB(l, l, l), 0.18)
            return SceneColour.lerp(grey, RGB(1, 0.95, 0.88), warm * day)
        }
        let top = soft(palette.skyTop, 0.2), bottom = soft(palette.skyBottom, 0.32)
        let mid = SceneColour.lerp(top, bottom, 0.55)
        let grad = GraphicsContext.Shading.linearGradient(
            Gradient(stops: [.init(color: SceneColour.color(top), location: 0), .init(color: SceneColour.color(mid), location: 0.55),
                             .init(color: SceneColour.color(bottom), location: 1)]),
            startPoint: p(0, 0), endPoint: p(0, fenceBaseY))
        ctx.fill(Path(bleed(CGRect(origin: .zero, size: size))), with: grad)
    }

    /// Long thin stratus: each cloud is a few stacked, slightly offset capsules, with a shade copy underneath. More
    /// of them, and thicker, when the palette is grey (overcast, rain, fog).
    func japaneseClouds() {
        let greyness = 1 - min(1, SceneColour.chroma(palette.skyTop) / 0.4)
        let cloudy = min(1, palette.rainStrength + palette.fogStrength * 0.4 + greyness * 0.7)
        let count = 3 + Int(cloudy * 3.99)
        let base = SceneColour.lerp(RGB(1, 0.97, 0.92), palette.skyBottom, cloudy * 0.3)
        let cloud = SceneColour.color(base), shade = SceneColour.color(SceneColour.scaled(base, 0.92))
        // x, y, length (of the width), thickness (of the width)
        let spots: [(x: Double, y: Double, len: Double, thick: Double)] = [
            (0.22, 0.08, 0.2, 0.011), (0.7, 0.05, 0.26, 0.012), (0.5, 0.14, 0.15, 0.009),
            (0.92, 0.12, 0.17, 0.01), (0.06, 0.15, 0.13, 0.009), (0.38, 0.03, 0.12, 0.008), (0.8, 0.17, 0.12, 0.009),
        ]
        let travel = motion.cloudTravel
        for (i, spot) in spots.prefix(count).enumerated() {
            let x = Self.wrapCloudX(spot.x + travel * (0.6 + 0.2 * Double(i % 3)))
            let c = p(x, spot.y), len = spot.len * unit, t = spot.thick * unit * (1 + cloudy * 0.7)
            let bands: [(dx: Double, dy: Double, l: Double, k: Double)] = [
                (0, 0, 1, 1), (0.28, -0.85, 0.55, 0.8), (-0.3, 0.8, 0.42, 0.7),
            ]
            for layer in [(shade, 0.35), (cloud, 0.0)] {
                for b in bands {
                    let w = len * b.l, h = t * b.k
                    let rect = CGRect(x: c.x + b.dx * len - w / 2, y: c.y + b.dy * t - h / 2 + layer.1 * t, width: w, height: h)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: h / 2), with: .color(layer.0))
                }
            }
        }
    }

    /// Soft mountains in three layers with haze between them (mist pools at each layer's foot, so the far ones fade
    /// out), and the silhouette of a pagoda on the middle ridge.
    func japaneseHorizon() {
        let day = 1 - min(1, palette.darkness * 1.6)
        func tint(_ c: RGB) -> RGB { SceneColour.scaled(c, 0.55 + 0.45 * day) }
        let haze = SceneColour.lerp(palette.skyBottom, RGB(1, 1, 1), 0.35)
        let far = SceneColour.lerp(palette.skyBottom, tint(RGB(0.46, 0.57, 0.72)), 0.62)
        let mid = SceneColour.lerp(far, tint(RGB(0.4, 0.52, 0.64)), 0.55)
        let near = SceneColour.lerp(palette.grass, tint(RGB(0.28, 0.42, 0.42)), 0.62)
        let top = fenceTopY

        japaneseMountainLayer(baseY: top + 0.0, amp: 0.15, peaks: (4.6, 11.0), phase: 0.6, sharp: 1.5, colour: far, haze: haze, hazeAmount: 0.78)
        japaneseMistStreak(y: top - 0.015, x: 0.3, width: 0.5, haze: haze, speed: 0.7)
        japaneseMountainLayer(baseY: top + 0.015, amp: 0.1, peaks: (6.2, 15.0), phase: 2.3, sharp: 1.25, colour: mid, haze: haze, hazeAmount: 0.7)
        // The pagoda stands on the middle ridge.
        let px = 0.9
        let ridgeY = Self.japaneseRidgeY(px, baseY: top + 0.015, amp: 0.1, peaks: (6.2, 15.0), phase: 2.3, sharp: 1.25)
        drawJapanesePagodaSilhouette(base: p(px, ridgeY + 0.004), height: 0.05 * unit, colour: SceneColour.scaled(mid, 0.84))
        japaneseMistStreak(y: top + 0.012, x: 0.78, width: 0.55, haze: haze, speed: 1.1)
        japaneseMountainLayer(baseY: top + 0.04, amp: 0.045, peaks: (3.4, 8.0), phase: 4.1, sharp: 0.7, colour: near, haze: haze, hazeAmount: 0.4)
    }

    /// Height (normalised y) of a ridge at x: sharp peaks from `|sin|`, plus a smaller ripple.
    static func japaneseRidgeY(_ x: Double, baseY: Double, amp: Double, peaks: (Double, Double), phase: Double,
                               sharp: Double) -> Double {
        let main = pow(1 - abs(sin(x * peaks.0 + phase)), sharp)
        let ripple = 0.5 + 0.5 * sin(x * peaks.1 + phase * 2.3)
        return baseY - amp * (0.72 * main + 0.28 * ripple)
    }

    private func japaneseMountainLayer(baseY: Double, amp: Double, peaks: (Double, Double), phase: Double, sharp: Double,
                                       colour: RGB, haze: RGB, hazeAmount: Double) {
        var pts: [CGPoint] = []
        // Runs a little past each edge so the layer still covers the frame when it is shifted by parallax.
        for i in 0...90 {
            let x = -0.05 + 1.1 * Double(i) / 90
            pts.append(p(x, Self.japaneseRidgeY(x, baseY: baseY, amp: amp, peaks: peaks, phase: phase, sharp: sharp)))
        }
        pts.append(p(1.05, baseY + 0.14))
        pts.append(p(-0.05, baseY + 0.14))
        fill(pts, SceneColour.color(colour))
        // Mist rising from the foot of the layer.
        var path = Path()
        path.move(to: pts[0])
        for q in pts.dropFirst() { path.addLine(to: q) }
        path.closeSubpath()
        let hz = SceneColour.color(haze)
        let grad = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [hz.opacity(0), hz.opacity(hazeAmount)]),
            startPoint: p(0, baseY - amp * 0.7), endPoint: p(0, baseY + 0.01))
        ctx.fill(path, with: grad)
    }

    /// A thin drifting band of mist between two layers.
    private func japaneseMistStreak(y: Double, x: Double, width: Double, haze: RGB, speed: Double) {
        let cx = Self.wrapCloudX(x + motion.cloudTravel * speed)
        let c = p(cx, y), w = width * unit
        let colour = SceneColour.color(haze)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - w / 2, y: c.y - 0.012 * unit, width: w, height: 0.024 * unit)),
                 with: .color(colour.opacity(0.4)))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - w * 0.3, y: c.y - 0.007 * unit, width: w * 0.6, height: 0.014 * unit)),
                 with: .color(colour.opacity(0.35)))
    }

    /// A five-storey-style pagoda reduced to a silhouette: three stacked tiers with upturned eaves and a spire.
    private func drawJapanesePagodaSilhouette(base: CGPoint, height h: CGFloat, colour: RGB) {
        let c = SceneColour.color(colour)
        let tiers = 3
        let tierH = h * 0.26
        var y = base.y
        for i in 0..<tiers {
            let k = 1 - 0.2 * CGFloat(i)
            let bodyW = h * 0.3 * k, roofW = h * 0.62 * k
            // Body.
            ctx.fill(Path(CGRect(x: base.x - bodyW / 2, y: y - tierH * 0.6, width: bodyW, height: tierH * 0.6)), with: .color(c))
            // Roof with curled-up corners.
            var roof = Path()
            let eaveY = y - tierH * 0.55, topY = y - tierH * 1.05
            roof.move(to: CGPoint(x: base.x - roofW / 2 - h * 0.03, y: eaveY - h * 0.03))
            roof.addQuadCurve(to: CGPoint(x: base.x + roofW / 2 + h * 0.03, y: eaveY - h * 0.03),
                              control: CGPoint(x: base.x, y: eaveY + h * 0.05))
            roof.addLine(to: CGPoint(x: base.x + bodyW * 0.3, y: topY))
            roof.addLine(to: CGPoint(x: base.x - bodyW * 0.3, y: topY))
            roof.closeSubpath()
            ctx.fill(roof, with: .color(c))
            y -= tierH
        }
        ctx.stroke(Path { $0.move(to: CGPoint(x: base.x, y: y + tierH * 0.1)); $0.addLine(to: CGPoint(x: base.x, y: y - h * 0.14)) },
                   with: .color(c), style: StrokeStyle(lineWidth: max(1, h * 0.03), lineCap: .round))
    }

    /// Both scene styles (check `style` for the backyard extras).
    func japaneseGround() { drawJapaneseGround() }
    func japaneseBarrier() { drawJapaneseBarrier() }
    /// Backyard only.
    func japaneseBackdropProps() { drawJapaneseBackdrop() }
    /// Backyard only.
    func japaneseSideBarriers() { drawJapaneseSideWalls() }
    func japaneseForeground() { drawJapaneseForeground() }
    /// Drawn over the darkness overlay (see `drawWeatherOverlays`), so lights can glow at dusk and night.
    func japaneseAmbient() { drawJapaneseAmbient() }
}
