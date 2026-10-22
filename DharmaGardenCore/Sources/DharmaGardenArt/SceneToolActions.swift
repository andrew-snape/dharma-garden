import SwiftUI
import DharmaGardenCore

/// The player's tools drawn as they happen on the soil: the watering can tips and pours, the fork goes in and
/// turns the soil (and leaves lines when it is dragged), and Seasol and fertiliser fall onto the patch. Each
/// effect is a pure function of how far through its life the action is (0...1), so a frame can be drawn at any
/// moment. Picked blooms and pulled weeds hop off the soil. Sizes follow the scale at the spot's depth, like the plants do.
extension SceneCanvas {
    /// The tine positions across the fork's head, in units of the tool size.
    private static let tineOffsets: [Double] = [-0.09, -0.03, 0.03, 0.09]

    func drawToolAction(_ ring: ActiveRing) {
        let t = min(1, max(0, ring.progress))
        switch ring.kind {
        case .water: drawPouringCan(ring.point, t, showCan: ring.showsCan, continuing: ring.continuesPour)
        case .aerate: drawForkStab(ring.point, t)
        case .seasol: drawFeed(ring.point, t, radius: ring.maxRadius, liquid: true)
        case .fertilise: drawFeed(ring.point, t, radius: ring.maxRadius, liquid: false)
        case .furrow: drawFurrow(ring, t)
        case .pick: drawHop(ring.point, t, weed: false)
        case .pull: drawHop(ring.point, t, weed: true)
        case .plant, .spot: break
        }
    }

    /// A smooth 0...1 ramp of `t` between `a` and `b`.
    private static func ramp(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let x = min(1, max(0, (t - a) / (b - a)))
        return x * x * (3 - 2 * x)
    }

    /// A seed for the scatter of one action, so its bits land in the same places on every frame.
    private func actionSeed(_ c: GroundPoint) -> UInt64 {
        UInt64(truncatingIfNeeded: Int(c.x * 10_000)) &* 31 &+ UInt64(truncatingIfNeeded: Int(c.y * 10_000))
    }

    /// The size of a tool on screen at ground point `c`.
    private func toolSize(at c: GroundPoint) -> CGFloat {
        0.12 * unit * CGFloat(camera.scale(atGroundY: c.y))
    }

    // MARK: Watering can

    /// A can tips over the spot, a stream falls from its rose and splashes, and the soil darkens.
    private func drawPouringCan(_ c: GroundPoint, _ t: Double, showCan: Bool, continuing: Bool) {
        let base = ground(c)
        let k = toolSize(at: c)
        let seed = actionSeed(c)
        // A pour that carries on from an earlier spot (a drag) skips the tip-in, so the can stays tilted.
        let tilt = (continuing ? 1 : Self.ramp(t, 0, 0.2)) * (1 - Self.ramp(t, 0.8, 1))
        let pour = Self.ramp(t, 0.12, 0.25) * (1 - Self.ramp(t, 0.78, 0.9))
        let wet = Self.ramp(t, 0.15, 0.6) * (1 - Self.ramp(t, 0.8, 1))
        let tip = CGPoint(x: base.x - 0.05 * k, y: base.y - 0.8 * k)

        // Soil darkens where the water lands.
        let wetColour = SceneColour.color(SceneColour.scaled(palette.soil, 0.5))
        ellipse(base, 0.34 * k * CGFloat(wet), 0.14 * k * CGFloat(wet), wetColour.opacity(0.3 * wet))

        // The stream: drops fall from the rose, speeding up as they go, and ripple where they land.
        let drop = Color(red: 0.62, green: 0.82, blue: 1)
        for i in 0..<16 {
            let phase = (t * 4 + unitHash(seed, UInt64(i))).truncatingRemainder(dividingBy: 1)
            let fall = CGFloat(0.5 * phase + 0.5 * phase * phase)
            let x = tip.x + CGFloat(unitHash(seed, UInt64(100 + i)) - 0.5) * 0.1 * k + CGFloat(phase) * 0.03 * k
            let y = tip.y + (base.y - tip.y) * fall
            ellipse(CGPoint(x: x, y: y), 0.024 * k, 0.07 * k, drop.opacity(0.9 * pour))
        }
        for i in 0..<2 {
            let phase = (t * 3 + Double(i) / 2).truncatingRemainder(dividingBy: 1)
            let w = 0.34 * k * CGFloat(0.2 + phase)
            let splash = Path(ellipseIn: CGRect(x: base.x - w / 2, y: base.y - w * 0.2, width: w, height: w * 0.4))
            ctx.stroke(splash, with: .color(drop.opacity(0.7 * (1 - phase) * pour)), lineWidth: max(1, 0.012 * k))
        }

        // The can: it tips toward the spot, spout first, then rights itself.
        guard showCan, tilt > 0.01 else { return }
        let saved = ctx
        ctx.translateBy(x: tip.x, y: tip.y)
        ctx.rotate(by: .radians(0.05 + 0.4 * tilt))
        ctx.opacity = min(1, tilt * 4)
        let body = Color(hex: 0x9FB0C8), shade = Color(hex: 0x7F90A8)
        var spout = Path()
        spout.move(to: CGPoint(x: -0.32 * k, y: 0.38 * k))
        spout.addLine(to: CGPoint(x: -0.03 * k, y: 0.02 * k))
        ctx.stroke(spout, with: .color(shade), style: StrokeStyle(lineWidth: 0.06 * k, lineCap: .round))
        var handle = Path()
        handle.move(to: CGPoint(x: -0.95 * k, y: 0.08 * k))
        handle.addQuadCurve(to: CGPoint(x: -0.45 * k, y: 0.02 * k), control: CGPoint(x: -0.75 * k, y: -0.4 * k))
        ctx.stroke(handle, with: .color(shade), style: StrokeStyle(lineWidth: 0.05 * k, lineCap: .round))
        let can = CGRect(x: -1.0 * k, y: 0.02 * k, width: 0.7 * k, height: 0.56 * k)
        ctx.fill(Path(roundedRect: can, cornerRadius: 0.08 * k), with: .color(body))
        ctx.fill(Path(roundedRect: CGRect(x: can.minX, y: can.midY + 0.1 * k, width: can.width, height: can.height / 2 - 0.1 * k),
                      cornerRadius: 0.06 * k), with: .color(shade.opacity(0.7)))
        ctx.fill(Path(ellipseIn: CGRect(x: -0.07 * k, y: -0.04 * k, width: 0.12 * k, height: 0.16 * k)), with: .color(shade))
        ctx = saved
    }

    // MARK: Garden fork

    /// The fork goes into the soil, the soil is turned over and flung up in clods, and the fork lifts out.
    private func drawForkStab(_ c: GroundPoint, _ t: Double) {
        let base = ground(c)
        let k = toolSize(at: c)
        let seed = actionSeed(c)
        let depth = Self.ramp(t, 0, 0.3) * (1 - Self.ramp(t, 0.7, 1))       // 0 raised ... 1 in the soil
        let lever = Self.ramp(t, 0.5, 0.65) * (1 - Self.ramp(t, 0.65, 0.8))  // the handle rocks back to turn the soil
        let fade = 1 - Self.ramp(t, 0.85, 1)
        let dark = SceneColour.color(SceneColour.scaled(palette.soil, 0.4))
        let turned = SceneColour.color(SceneColour.lerp(palette.soil, RGB(0.9, 0.78, 0.6), 0.25))

        // Turned soil heaps up where the fork lifted it, and the tine holes show.
        let heap = Self.ramp(t, 0.5, 0.7) * fade
        ellipse(base, 0.3 * k, 0.11 * k, turned.opacity(0.55 * heap))
        let holes = Self.ramp(t, 0.28, 0.35) * fade
        for x in Self.tineOffsets {
            ellipse(CGPoint(x: base.x + CGFloat(x) * k, y: base.y), 0.028 * k, 0.012 * k, dark.opacity(0.75 * holes))
        }

        drawFork(at: base, k: k, lift: (1 - depth) * 0.7, lean: 0.05 + 0.3 * lever, opacity: 1)

        // Clods fly up when the handle rocks back and fall to the soil.
        for i in 0..<10 {
            let h = { unitHash(seed, UInt64(i * 4) + $0) }
            let tau = min(1, max(0, (t - 0.5 - h(0) * 0.1) / 0.35))
            guard tau > 0 else { continue }
            let peak = (0.15 + 0.25 * h(1)) * k
            let x = base.x + CGFloat(h(2) - 0.5) * 0.7 * k * CGFloat(tau)
            let y = base.y - 4 * peak * CGFloat(tau * (1 - tau)) + CGFloat(h(3) - 0.5) * 0.04 * k
            let size = (0.025 + 0.025 * h(1)) * k
            ellipse(CGPoint(x: x, y: y), size, size * 0.75, (h(3) > 0.5 ? dark : turned).opacity(fade))
        }
    }

    /// A garden fork standing with its tines at `base`, raised by `lift` and leaning by `lean` (both in units of
    /// `k`). Only the part above the soil line shows, so the tines sink into the ground.
    private func drawFork(at base: CGPoint, k: CGFloat, lift: Double, lean: Double, opacity: Double) {
        let saved = ctx
        ctx.opacity = opacity
        ctx.clip(to: Path(CGRect(x: base.x - 2 * k, y: base.y - 4 * k, width: 4 * k, height: 4 * k + 0.01 * k)))
        func pt(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: base.x + CGFloat(x - y * lean) * k, y: base.y + CGFloat(y - lift) * k)
        }
        let metal = Color(hex: 0xB8BEC6), wood = Color(hex: 0xA9794A)
        for x in Self.tineOffsets {
            stroke([pt(x, -0.3), pt(x, 0.1)], width: 0.02 * k, metal)
        }
        stroke([pt(-0.1, -0.3), pt(0.1, -0.3)], width: 0.032 * k, metal)
        stroke([pt(0, -0.3), pt(0.02, -1.0)], width: 0.028 * k, wood)
        stroke([pt(-0.05, -1.0), pt(0.09, -1.0)], width: 0.032 * k, wood)
        ctx = saved
    }

    /// The lines a dragged fork leaves: one trench per tine from where the drag was to where it is, with a lighter
    /// ridge beside each, fading out slowly. The fork itself shows at the head for a moment.
    private func drawFurrow(_ ring: ActiveRing, _ t: Double) {
        let b = ring.point
        let a = ring.from ?? b
        let fade = 1 - Self.ramp(t, 0.55, 1)
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(1e-9, hypot(dx, dy))
        let perp = (x: -dy / len, y: dx / len)
        let s = unit * CGFloat(camera.scale(atGroundY: b.y))
        let trench = SceneColour.color(SceneColour.scaled(palette.soil, 0.42))
        let ridge = SceneColour.color(SceneColour.lerp(palette.soil, RGB(0.9, 0.78, 0.6), 0.3))
        for o in [-0.018, -0.006, 0.006, 0.018] {
            let pa = ground(GroundPoint(x: a.x + perp.x * o, y: a.y + perp.y * o))
            let pb = ground(GroundPoint(x: b.x + perp.x * o, y: b.y + perp.y * o))
            let lifted = CGFloat(0.003) * s
            stroke([CGPoint(x: pa.x, y: pa.y - lifted), CGPoint(x: pb.x, y: pb.y - lifted)],
                   width: max(1.2, 0.003 * s), ridge.opacity(0.45 * fade))
            stroke([pa, pb], width: max(1, 0.0022 * s), trench.opacity(0.7 * fade))
        }

        // The fork at the head of the line, there for an instant.
        if t < 0.05 {
            drawFork(at: ground(b), k: 0.12 * s, lift: 0, lean: 0.3, opacity: 1 - t / 0.05 * 0.4)
        }

        // A couple of clods hop off the line as the fork passes.
        let seed = actionSeed(b)
        let tau = t / 0.25
        guard tau < 1 else { return }
        for i in 0..<2 {
            let h = { unitHash(seed, UInt64(i * 3) + $0) }
            let spot = GroundPoint(x: (a.x + b.x) / 2 + perp.x * (h(0) - 0.5) * 0.05,
                                   y: (a.y + b.y) / 2 + perp.y * (h(0) - 0.5) * 0.05)
            let g = ground(spot)
            let arc = 4 * (0.1 + 0.12 * h(1)) * 0.12 * s * CGFloat(tau * (1 - tau))
            let size = (0.02 + 0.015 * h(2)) * 0.12 * s
            ellipse(CGPoint(x: g.x, y: g.y - arc), size, size * 0.75, trench.opacity(1 - tau * tau))
        }
    }

    // MARK: Seasol and fertiliser

    /// Seasol falls as dark teal drops that splash flat; fertiliser as pellets that land and bounce. Both tint
    /// the soil, and fertiliser leaves a few sparkles rising from it.
    private func drawFeed(_ c: GroundPoint, _ t: Double, radius: Double, liquid: Bool) {
        let seed = actionSeed(c) &+ (liquid ? 7 : 13)
        let k = toolSize(at: c)
        let height = 0.9 * k
        let fade = 1 - Self.ramp(t, 0.75, 1)
        let drop = Color(red: 0.3, green: 0.62, blue: 0.5)

        // The soil takes the tint.
        let tint = liquid ? drop : Color(hex: 0xB5C95A)
        let grow = Self.ramp(t, 0.3, 0.7) * (1 - Self.ramp(t, 0.8, 1))
        fill(groundCircle(c, radius: radius * 0.8), tint.opacity(0.2 * grow))

        for i in 0..<22 {
            let h = { unitHash(seed, UInt64(i * 4) + $0) }
            let delay = h(2) * 0.35
            guard t >= delay else { continue }
            let angle = h(0) * 2 * Double.pi
            let r = radius * 0.85 * h(1).squareRoot()
            let spot = ground(GroundPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r))
            let u = min(1, (t - delay) / 0.3)
            let y = spot.y - height * CGFloat(1 - u * u)
            if liquid {
                if u < 1 {
                    ellipse(CGPoint(x: spot.x, y: y), 0.022 * k, 0.07 * k, drop.opacity(0.9))
                } else {
                    ellipse(spot, 0.07 * k, 0.026 * k, drop.opacity(0.6 * fade))
                }
            } else {
                // A pellet bounces a little when it lands.
                let bounce = u < 1 ? 0 : 0.05 * k * CGFloat(sin(Double.pi * min(1, (t - delay - 0.3) / 0.15)))
                let pellet = h(3) > 0.5 ? Color(hex: 0xD9BE84) : Color(hex: 0x8B6B3E)
                ellipse(CGPoint(x: spot.x, y: y - bounce), 0.034 * k, 0.034 * k, pellet.opacity(fade))
            }
        }

        if !liquid {
            // Sparkles drift up from the fed soil.
            let rise = Self.ramp(t, 0.5, 1)
            let glow = Color(hex: 0xE8F59A).opacity(sin(Double.pi * rise))
            for i in 0..<5 {
                let spot = ground(GroundPoint(x: c.x + (unitHash(seed, UInt64(200 + i)) - 0.5) * radius,
                                              y: c.y + (unitHash(seed, UInt64(300 + i)) - 0.5) * radius))
                let top = CGPoint(x: spot.x, y: spot.y - CGFloat(rise) * 0.35 * k)
                let arm = 0.035 * k
                stroke([CGPoint(x: top.x - arm, y: top.y), CGPoint(x: top.x + arm, y: top.y)], width: max(1, 0.01 * k), glow)
                stroke([CGPoint(x: top.x, y: top.y - arm), CGPoint(x: top.x, y: top.y + arm)], width: max(1, 0.01 * k), glow)
            }
        }
    }
}

// MARK: Picking and pulling

extension SceneCanvas {
    /// A picked bloom pops up off the plant, hops in an arc and fades, with a puff of soil where it came from.
    /// A pulled weed does the same with a green tuft.
    func drawHop(_ c: GroundPoint, _ t: Double, weed: Bool) {
        let base = ground(c)
        let k = 0.12 * unit * CGFloat(camera.scale(atGroundY: c.y))
        let seed = UInt64(truncatingIfNeeded: Int(c.x * 10_000)) &* 31 &+ UInt64(truncatingIfNeeded: Int(c.y * 10_000))
        let soil = SceneColour.color(SceneColour.scaled(palette.soil, 0.55))

        // The soil puffs out where the plant was.
        let puff = min(1, t / 0.4)
        for i in 0..<5 {
            let a = (Double(i) / 5 + unitHash(seed, UInt64(i)) * 0.1) * 2 * Double.pi
            let r = 0.18 * k * CGFloat(puff)
            ellipse(CGPoint(x: base.x + CGFloat(cos(a)) * r, y: base.y + CGFloat(sin(a)) * r * 0.4 - 0.05 * k * CGFloat(sin(Double.pi * puff))),
                    0.045 * k, 0.034 * k, soil.opacity(0.8 * (1 - puff)))
        }

        // The hop: up fast, over a small arc to the side, then down and away. Scale pops in first.
        let fly = min(1, t / 0.85)
        let arc = CGFloat(4 * fly * (1 - fly))
        let pop = CGFloat(min(1, t / 0.12))
        let squash = 1 + 0.25 * sin(Double.pi * min(1, t / 0.25))
        let centre = CGPoint(x: base.x + CGFloat(fly) * 0.35 * k, y: base.y - 0.3 * k - arc * 0.9 * k + CGFloat(fly) * 0.25 * k)
        let fade = 1 - Self.hopRamp(t, 0.7, 1)
        let size = (weed ? 0.1 : 0.14) * k * pop * CGFloat(squash)
        guard fade > 0 else { return }
        if weed {
            let leaf = Color(hex: 0x6FA45A)
            for i in 0..<3 {
                let lean = CGFloat(i - 1) * 0.5
                let tip = CGPoint(x: centre.x + lean * size * 1.4, y: centre.y - size * 2.2 + abs(lean) * size * 0.4)
                stroke([centre, tip], width: max(1.4, 0.45 * size), leaf.opacity(fade))
            }
            ellipse(CGPoint(x: centre.x, y: centre.y + size * 0.3), size * 1.4, size * 0.9, soil.opacity(fade))
        } else {
            // A little round bloom: petals around a warm centre, turning as it flies.
            let petal = Color(hex: 0xFFD4A0), heart = Color(hex: 0xF2A93B)
            let spin = fly * 3
            for i in 0..<6 {
                let a = Double(i) / 6 * 2 * Double.pi + spin
                ellipse(CGPoint(x: centre.x + CGFloat(cos(a)) * size * 1.1, y: centre.y + CGFloat(sin(a)) * size * 1.1),
                        size * 1.3, size * 1.3, petal.opacity(fade))
            }
            ellipse(centre, size * 1.2, size * 1.2, heart.opacity(fade))
        }
    }

    /// A smooth 0...1 ramp of `t` between `a` and `b`.
    private static func hopRamp(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let x = min(1, max(0, (t - a) / (b - a)))
        return x * x * (3 - 2 * x)
    }
}
