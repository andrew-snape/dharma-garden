import SwiftUI
import DharmaGardenCore

/// The Rural UK theme's ambient touches, drawn in the weather pass over the darkness overlay (so they stay bright at
/// dusk and night) and under fog and rain: a curl of chimney smoke, the cottage windows glowing as the light fades,
/// and a robin that visits the wall now and then. All of it is a pure function of the motion frame's time and wind,
/// and capped at a handful of shapes.
extension SceneCanvas {
    /// Seconds for one puff of smoke to rise and fade, and how many are in the air.
    static let ukSmokePeriod = 11.0
    static let ukSmokePuffs = 6
    /// The robin's visit: one every `ukRobinPeriod` seconds, on the wall from `ukRobinStay.lowerBound` to
    /// `.upperBound` of the way through it.
    static let ukRobinPeriod = 20.0
    static let ukRobinStay = 0.35...0.85
    /// Where the robin can perch along the wall, clear of the gate.
    static let ukRobinSpots = [1.5, 2.3, 3.1, 3.7, -4.1]

    func ukDrawAmbient() {
        // The cottage and the wall live in the fence layer, which is shifted by parallax; this pass is not.
        let saved = ctx
        let shift = motion.layerShift(.fence)
        ctx.translateBy(x: CGFloat(shift.x) * size.width, y: CGFloat(shift.y) * size.height)
        defer { ctx = saved }
        if style == .backyard {
            ukDrawWindowGlow()
            ukDrawSmoke()
        }
        ukDrawRobin()
    }

    /// Smoke rising from the chimney: puffs that grow, lean downwind and fade, each a little behind the one before.
    /// With the motion off (time zero) they hang in a static curl.
    private func ukDrawSmoke() {
        let cot = ukCottageLayout()
        let top = cot.chimneyTop
        let s = cot.s
        let n = Self.ukSmokePuffs
        let dark = palette.darkness
        let smoke = mix(0xECE8E1, 0x6D7488, dark * 0.8), smokeShade = mix(0xCFCAC4, 0x565C70, dark * 0.8)
        let lean = 0.3 + 0.7 * motion.wind
        for i in 0..<n {
            var phase = motion.time / Self.ukSmokePeriod + Double(i) / Double(n)
            phase -= floor(phase)
            let rise = phase * 0.6, sway = sin(phase * 6 + Double(i) * 1.7) * 0.05
            let c = CGPoint(x: top.x + CGFloat(phase * lean + sway) * s, y: top.y - CGFloat(rise) * s)
            let r = CGFloat(0.06 + 0.11 * phase) * s
            let alpha = min(1, phase / 0.12) * (1 - phase) * 0.9
            let w = 2 * r
            ellipse(CGPoint(x: c.x + 0.012 * s, y: c.y + 0.016 * s), w, w * 0.86, smokeShade.opacity(alpha))
            ellipse(c, w, w * 0.86, smoke.opacity(alpha))
        }
    }

    /// The windows glowing warm as it gets dark: a soft halo and bright panes, over the darkness.
    private func ukDrawWindowGlow() {
        let lit = smooth(palette.darkness, 0.1, 0.3)
        guard lit > 0.01 else { return }
        let cot = ukCottageLayout()
        let s = cot.cs
        let warm = Color(hex: 0xFFC766)
        for (a, b, h0, h1) in UKCottage.windows {
            let tl = cot.cp(a, h1), br = cot.cp(b, h0)
            let rect = CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y)
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            let radius = 0.95 * s
            let halo = Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: 2 * radius, height: 2 * radius))
            ctx.fill(halo, with: .radialGradient(Gradient(colors: [warm.opacity(0.5 * lit), warm.opacity(0)]),
                                                 center: centre, startRadius: 0, endRadius: radius))
            // The panes and their frame, bright.
            let frame = rect.insetBy(dx: -0.04 * s, dy: -0.04 * s)
            ctx.fill(Path(frame), with: .color(Color(hex: 0xFFE9B5).opacity(lit)))
            ctx.fill(Path(rect), with: .color(Color(hex: 0xFFD98A).opacity(lit)))
            for k in 1..<3 {
                let x = rect.minX + rect.width * CGFloat(k) / 3
                stroke([CGPoint(x: x, y: rect.minY), CGPoint(x: x, y: rect.maxY)], width: 1, Color(hex: 0xFFF2D0).opacity(lit))
            }
            stroke([CGPoint(x: rect.minX, y: rect.midY), CGPoint(x: rect.maxX, y: rect.midY)], width: 1, Color(hex: 0xFFF2D0).opacity(lit))
        }
        // The little window in the door.
        let d = UKCottage.doorX
        let tl = cot.cp(d - 0.15, 0.56), br = cot.cp(d + 0.15, 0.4)
        ctx.fill(Path(CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y)), with: .color(Color(hex: 0xFFD98A).opacity(lit)))
    }

    /// A robin that drops onto the wall, bobs quietly for a while, then flits off again. It is just scenery: it is not a
    /// visitor and cannot be tapped. It keeps out of the rain and the dark.
    private func ukDrawRobin() {
        guard motion.enabled, palette.rainStrength < 0.2, palette.darkness < 0.5 else { return }
        let t = motion.time
        let visit = Int(floor(t / Self.ukRobinPeriod))
        let phase = t / Self.ukRobinPeriod - Double(visit)
        guard Self.ukRobinStay.contains(phase) else { return }
        let into = (phase - Self.ukRobinStay.lowerBound) * Self.ukRobinPeriod
        let left = (Self.ukRobinStay.upperBound - phase) * Self.ukRobinPeriod
        let spot = Self.ukRobinSpots[Int(unitHash(0x20B1, UInt64(visit)) * Double(Self.ukRobinSpots.count)) % Self.ukRobinSpots.count]
        let facing: CGFloat = unitHash(0x20B2, UInt64(visit)) < 0.5 ? -1 : 1
        let ru = 0.0125 * unit
        // Drops in from above and behind over the first half second; flits up and away in the last.
        let arrive = max(0, 1 - into / 0.5), depart = max(0, 1 - left / 0.5)
        let bob = pow(max(0, sin(t * 2.6)), 6) * 2.4
        var foot = ukWallTopPoint(x: spot)
        foot.y += 1
        foot.y -= CGFloat(arrive * arrive) * 22 + CGFloat(1 - (1 - depart) * (1 - depart)) * 24
        foot.x += facing * -CGFloat(depart) * 14
        let dim = palette.darkness * 0.85
        func col(_ hex: UInt32) -> Color { mix(hex, 0x10172B, dim) }
        func Q(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: foot.x + facing * dx * ru, y: foot.y - 0.9 * ru - bob + dy * ru) }
        let brown = col(0x8A6A4F), brownDark = col(0x6B503A), breast = col(0xE2602F), belly = col(0xE8DCC6)
        // A contact shadow, the legs and the tail.
        ellipse(CGPoint(x: foot.x, y: foot.y + 1), 2.4 * ru, 0.5 * ru, Color(hex: 0x1B2A14).opacity(0.2))
        stroke([CGPoint(x: foot.x - facing * 0.2 * ru, y: foot.y), Q(-0.2, 0.55)], width: 1, brownDark)
        stroke([CGPoint(x: foot.x + facing * 0.7 * ru, y: foot.y), Q(0.5, 0.55)], width: 1, brownDark)
        stroke([Q(-0.9, 0.1), Q(-2.2, -0.55)], width: 0.55 * ru, brownDark)
        // Body, breast, belly, head, face, eye and beak.
        ellipse(Q(0, 0), 2.4 * ru, 1.9 * ru, brown)
        ellipse(Q(0.7, 0.15), 1.4 * ru, 1.4 * ru, breast)
        ellipse(Q(0.1, 0.62), 1.6 * ru, 0.7 * ru, belly)
        ellipse(Q(1.0, -0.7), 1.35 * ru, 1.25 * ru, brown)
        ellipse(Q(1.25, -0.55), 0.85 * ru, 0.8 * ru, breast)
        ellipse(Q(1.3, -0.85), 0.25 * ru, 0.25 * ru, col(0x1E1814))
        fill([Q(1.65, -0.72), Q(2.2, -0.6), Q(1.65, -0.48)], col(0x4A3B2E))
    }
}
