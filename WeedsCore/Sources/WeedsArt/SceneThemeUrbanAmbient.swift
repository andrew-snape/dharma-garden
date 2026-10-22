import SwiftUI
import WeedsCore

/// The Urban theme's ambient touches, drawn over the darkness overlay (so they stay lit at dusk and night) and under
/// fog and rain: string lights draped along the fence, lit windows, a cat that sits on the fence top now and then,
/// and faint smoke from a chimney pot in the skyline. Everything on the fence layer is shifted by that layer's parallax first, the
/// skyline by the hills layer's, so each stays on what it belongs to. Counts are small and fixed.
extension SceneCanvas {
    /// How long one visit cycle of the cat takes, in seconds, and when in it she sits on the fence.
    static let urbanCatCycle = 46.0

    func urbanAmbient() {
        let saved = ctx
        let frame = BarrierFrame(camera: camera, size: size, style: .timberPanel)
        let backyard = style == .backyard

        // Skyline layer: lit apartment windows (those in view) and the smoke from a chimney pot.
        let hills = motion.layerShift(.hills)
        ctx.translateBy(x: CGFloat(hills.x) * size.width, y: CGFloat(hills.y) * size.height)
        let fenceTop = frame.point(x: 0, z: Self.fenceZ, height: UrbanFence.height + 0.04).y
        urbanLitSkylineWindows(visibleAbove: fenceTop, backyard: backyard)
        urbanSmoke(from: urbanSkylineChimney, seed: 1)
        ctx = saved

        // Fence layer.
        let fence = motion.layerShift(.fence)
        ctx.translateBy(x: CGFloat(fence.x) * size.width, y: CGFloat(fence.y) * size.height)
        if backyard {
            urbanLitHouseWindows(visibleAbove: fenceTop)
        }
        urbanStringLights(frame, backyard: backyard)
        urbanCat(frame)
        ctx = saved
    }

    // MARK: Lit windows

    private var urbanWarm: Color { Color(hex: 0xFFD98A) }

    private func urbanLitSkylineWindows(visibleAbove limit: CGFloat, backyard: Bool) {
        let lit = urbanLit
        guard lit > 0 else { return }
        for (i, b) in Self.urbanBlocks.enumerated() {
            // In the backyard the houses cover every block but the one in the alley.
            if backyard && !(b.x0 > 0.38 && b.x1 < 0.58) { continue }
            for w in urbanBlockWindows(b, index: i) where w.lit && w.rect.maxY < limit - 2 {
                ctx.fill(Path(w.rect), with: .color(urbanWarm.opacity(0.85 * lit)))
            }
        }
    }

    private func urbanLitHouseWindows(visibleAbove limit: CGFloat) {
        let lit = urbanLit
        guard lit > 0 else { return }
        var g = ctx
        g.clip(to: Path(CGRect(x: -size.width, y: -size.height, width: size.width * 3, height: size.height + limit)))
        let saved = ctx
        ctx = g
        for (i, w) in urbanHouseWindows().enumerated() where w.lit {
            let r = w.rect.insetBy(dx: -1, dy: -1)
            let halo = GraphicsContext.Shading.radialGradient(
                Gradient(colors: [urbanWarm.opacity(0.4 * lit), urbanWarm.opacity(0)]),
                center: CGPoint(x: r.midX, y: r.midY), startRadius: 0, endRadius: r.width * 1.3)
            ctx.fill(Path(ellipseIn: r.insetBy(dx: -r.width * 1.1, dy: -r.height * 0.9)), with: halo)
            ctx.fill(Path(r), with: .color(urbanWarm.opacity(0.9 * lit)))
            // Curtains stay drawn as soft shapes at the sides, and the glazing bars on top.
            let curtain = [0xE8A6A0, 0x9CC8B4, 0xF2D27A, 0xA9B5E0, 0xE9E1D3][i % 5] as UInt32
            let cw = r.width * 0.3
            ctx.fill(Path(CGRect(x: r.minX, y: r.minY, width: cw, height: r.height)), with: .color(mix(0xFFD98A, curtain, 0.45).opacity(0.9 * lit)))
            ctx.fill(Path(CGRect(x: r.maxX - cw, y: r.minY, width: cw, height: r.height)), with: .color(mix(0xFFD98A, curtain, 0.45).opacity(0.9 * lit)))
            stroke([CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.midX, y: r.maxY)], width: 1, Color(hex: 0xFBF6EA).opacity(0.9 * lit))
        }
        ctx = saved
    }

    // MARK: String lights

    /// Fairy lights swagged between the fence posts, along the back fence and (in the backyard) down both sides. They
    /// show as a plain cord with pale bulbs by day, and glow warmly and twinkle as it gets dark.
    private func urbanStringLights(_ frame: BarrierFrame, backyard: Bool) {
        let lit = urbanLit
        let z0 = Self.fenceZ
        let h = UrbanFence.height - 0.14
        let half = backyard ? BarrierFrame.halfLength : UrbanScene.firstPersonHalfLength
        let panels = Int((2 * half / UrbanFence.panelWidth).rounded())
        var swags: [(CGPoint, CGPoint, CGFloat)] = []
        func rise(_ x: Double, _ z: Double) -> CGFloat { abs(frame.point(x: x, z: z, height: 1).y - frame.point(x: x, z: z).y) }
        for k in 0..<panels {
            let a = -half + Double(k) * UrbanFence.panelWidth, b = a + UrbanFence.panelWidth
            swags.append((frame.point(x: a, z: z0, height: h), frame.point(x: b, z: z0, height: h), rise(a, z0)))
        }
        if backyard {
            for x in [-BarrierFrame.halfLength, BarrierFrame.halfLength] {
                var z = z0
                while z + UrbanFence.panelWidth <= UrbanFence.sideEnd + 1e-9 {
                    swags.append((frame.point(x: x, z: z, height: h), frame.point(x: x, z: z + UrbanFence.panelWidth, height: h), rise(x, z)))
                    z += UrbanFence.panelWidth
                }
            }
        }
        let cord = Color(hex: 0x2F3033).opacity(0.75)
        let colours: [UInt32] = [0xFFD98A, 0xFFB86B, 0xFFE9B8, 0xFFC76E]
        var bulb = 0
        for (a, b, r) in swags {
            let n = 6
            var pts: [CGPoint] = []
            for i in 0...n {
                let t = Double(i) / Double(n)
                pts.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t + r * 0.16 * 4 * t * (1 - t)))
            }
            // A smooth cord through the bulb points.
            var path = Path()
            path.move(to: pts[0])
            for p in pts.dropFirst() { path.addLine(to: p) }
            ctx.stroke(path, with: .color(cord), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
            for (i, p) in pts.enumerated() where i > 0 && i < n {
                let twinkle = motion.enabled ? 0.82 + 0.18 * sin(motion.time * 2.3 + Double(bulb) * 1.7) : 1
                let on = lit * twinkle
                if on > 0.02 {
                    let glow = GraphicsContext.Shading.radialGradient(
                        Gradient(colors: [urbanWarm.opacity(0.55 * on), urbanWarm.opacity(0)]),
                        center: p, startRadius: 0, endRadius: r * 0.22)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.22, y: p.y - r * 0.22, width: r * 0.44, height: r * 0.44)), with: glow)
                }
                let c = mix(0xE9E4D6, colours[bulb % colours.count], on)
                ellipse(CGPoint(x: p.x, y: p.y + r * 0.03), r * 0.07, r * 0.09, c)
                bulb += 1
            }
        }
    }

    // MARK: The cat

    /// A ginger cat that sits on the fence top for a while each cycle, tail flicking now and then. She fades in and out
    /// rather than leaping, and is dimmed with the evening because she is drawn above the darkness overlay.
    private func urbanCat(_ frame: BarrierFrame) {
        let phase = motion.enabled ? motion.time.truncatingRemainder(dividingBy: Self.urbanCatCycle) : 12
        let visible = smooth(phase, 3, 4.5) * (1 - smooth(phase, 31, 33))
        guard visible > 0.01 else { return }
        let x = -1.55
        let top = frame.point(x: x, z: Self.fenceZ, height: UrbanFence.height + 0.04)
        let s = abs(frame.point(x: x, z: Self.fenceZ, height: 1).y - frame.point(x: x, z: Self.fenceZ).y)
        func dim(_ hex: UInt32) -> Color { mix(hex, 0x10172B, palette.darkness * 0.75) }
        let fur = dim(0xDC8A3F), stripe = dim(0xB5651F), belly = dim(0xF0C58E), ear = dim(0xE79AA0)
        func P(_ dx: Double, _ h: Double) -> CGPoint { CGPoint(x: top.x + CGFloat(dx) * s, y: top.y - CGFloat(h) * s) }
        let saved = ctx
        ctx.opacity = visible

        // Tail: curls up behind her and flicks in short bursts.
        let t = motion.enabled ? motion.time : 12.4
        let burst = t.truncatingRemainder(dividingBy: 6.5)
        let flick = (burst > 1.2 && burst < 2.6) ? sin(burst * 13) * 0.2 : sin(t * 1.1) * 0.04
        var tail = Path()
        tail.move(to: P(-0.17, 0.08))
        tail.addQuadCurve(to: P(-0.36 + flick, 0.42), control: P(-0.42, 0.06))
        ctx.stroke(tail, with: .color(stripe), style: StrokeStyle(lineWidth: 0.075 * s, lineCap: .round))
        ctx.stroke(tail, with: .color(fur), style: StrokeStyle(lineWidth: 0.05 * s, lineCap: .round))

        // Body, haunch, front legs, chest and head.
        let body = CGRect(x: P(-0.2, 0.3).x, y: P(0, 0.3).y, width: 0.4 * s, height: 0.3 * s)
        ctx.fill(Path(ellipseIn: body.offsetBy(dx: 0.012 * s, dy: 0.015 * s)), with: .color(stripe))
        ctx.fill(Path(ellipseIn: body), with: .color(fur))
        ellipse(P(-0.06, 0.12), 0.24 * s, 0.24 * s, fur)
        ctx.fill(Path(roundedRect: CGRect(x: P(0.06, 0.2).x, y: P(0, 0.2).y, width: 0.08 * s, height: 0.2 * s), cornerRadius: 0.04 * s), with: .color(belly))
        ellipse(P(0.13, 0.33), 0.2 * s, 0.26 * s, belly)
        let head = P(0.16, 0.44)
        ellipse(CGPoint(x: head.x + 0.01 * s, y: head.y + 0.012 * s), 0.25 * s, 0.22 * s, stripe)
        ellipse(head, 0.25 * s, 0.22 * s, fur)
        // Ears (one twitches), eye and nose.
        let twitch = (burst > 3.4 && burst < 3.7) ? 0.025 : 0
        fill([P(0.07, 0.52), P(0.11, 0.64 - twitch), P(0.17, 0.54)], fur)
        fill([P(0.16, 0.54), P(0.23, 0.64), P(0.26, 0.5)], fur)
        fill([P(0.09, 0.53), P(0.11, 0.6), P(0.15, 0.545)], ear)
        stroke([P(0.17, 0.46), P(0.215, 0.46)], width: max(1, 0.02 * s), dim(0x2A2A2A))
        ellipse(P(0.27, 0.42), 0.035 * s, 0.03 * s, ear)
        // A couple of stripes on the back.
        for dx in [-0.12, -0.05] { stroke([P(dx, 0.29), P(dx + 0.02, 0.2)], width: max(1, 0.03 * s), stripe) }
        ctx = saved
    }

    // MARK: Smoke

    /// A faint column of smoke from a chimney pot: six soft puffs that rise, drift with the wind, grow and fade. The
    /// pot is at `origin` (canvas points, in the layer already shifted).
    private func urbanSmoke(from origin: CGPoint, seed: UInt64) {
        let k = size.width / 960
        let drift = 14 + 50 * motion.wind
        for i in 0..<6 {
            let base = motion.enabled ? motion.time * 0.07 + Double(i) / 6 + Double(seed) * 0.37 : (Double(i) + 0.5) / 6
            let phase = base - floor(base)
            let x = origin.x + CGFloat(phase * drift) * k + CGFloat(sin(phase * 6 + Double(i))) * 3 * k
            let y = origin.y - CGFloat(phase) * 62 * k
            let r = CGFloat(3 + phase * 9) * k
            let opacity = 0.34 * (1 - phase) * smooth(phase, 0, 0.12)
            let colour = SceneColour.color(SceneColour.lerp(SceneColour.lerp(RGB(hex: 0xF4F2EC), RGB(hex: 0xA3A9B2), phase),
                                                            RGB(hex: 0x1A2238), palette.darkness * 0.6))
            ellipse(CGPoint(x: x, y: y), 2 * r, 1.8 * r, colour.opacity(opacity))
        }
    }
}
