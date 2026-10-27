import SwiftUI
import DharmaGardenCore

/// The backyard's clutter in front of the side fences: a wheelie bin, a bike leaning on the fence and a small kettle
/// barbecue, each with a shadow on the lawn. Called on `urbanGroundAligned()`, so it sits exactly on the ground layer.
/// All of it stands clear of the bed, on the side patios beside it.
extension SceneCanvas {
    func drawUrbanProps() {
        urbanDrawBike(x: -4.02, z: -2.35)
        urbanDrawBin(x: 3.95, z: -2.55)
        urbanDrawBarbecue(x: 3.5, z: -0.95)
    }

    /// A soft contact shadow on the lawn.
    private func urbanShadow(_ c: CGPoint, w: CGFloat, h: CGFloat, height: CGFloat) {
        propShadow(foot: c, height: height, width: w * 0.8, depth: h, opacity: 0.17)
    }

    private func urbanDrawBin(x: Double, z: Double) {
        let s = screenPerUnit(x: x, y: 0, z: z)
        let body = Color(hex: 0x4E8F66), shade = Color(hex: 0x376E4B), lid = Color(hex: 0x2F5D43), lidLight = Color(hex: 0x3E7557)
        func P(_ dx: Double, _ h: Double) -> CGPoint { upright(x + dx, h, z, scale: s) }
        let base = at3(x, 0, z)
        urbanShadow(base, w: 0.9 * s, h: 0.2 * s, height: 1.0 * s)
        // Wheels behind the body's feet.
        for dx in [-0.17, 0.17] { ellipse(P(dx, 0.07), 0.15 * s, 0.15 * s, Color(hex: 0x2B2E31)) }
        // Tapered body with a darker side and moulded ribs.
        let quad = [P(-0.25, 0.05), P(0.25, 0.05), P(0.31, 0.88), P(-0.31, 0.88)]
        fill(quad, body)
        fill([P(0.12, 0.05), P(0.25, 0.05), P(0.31, 0.88), P(0.18, 0.88)], shade)
        for h in [0.3, 0.55] { stroke([P(-0.28 - h * 0.05, h), P(0.28 + h * 0.05, h)], width: 1, shade) }
        // A white house-number panel.
        fill([P(-0.12, 0.5), P(0.05, 0.5), P(0.05, 0.66), P(-0.12, 0.66)], Color(hex: 0xF1EEE4))
        stroke([P(-0.08, 0.58), P(0.01, 0.58)], width: 1.4, Color(hex: 0x6D7378))
        // Lid with an overhanging lip and a handle at the front.
        fill([P(-0.34, 0.88), P(0.34, 0.88), P(0.34, 0.97), P(-0.34, 0.97)], lid)
        fill([P(-0.34, 0.95), P(0.34, 0.95), P(0.34, 0.97), P(-0.34, 0.97)], lidLight)
        fill([P(-0.1, 0.97), P(0.1, 0.97), P(0.08, 1.02), P(-0.08, 1.02)], lid)
    }

    /// A bike seen from the side, parked leaning on the left fence, tilted about its wheels' contact point.
    private func urbanDrawBike(x: Double, z: Double) {
        let s = screenPerUnit(x: x, y: 0, z: z)
        let base = at3(x, 0, z)
        urbanShadow(base, w: 1.5 * s, h: 0.22 * s, height: 0.9 * s)
        let frame = Color(hex: 0xD9534F), dark = Color(hex: 0x2B2D30), grey = Color(hex: 0x8B9096)
        let saved = ctx
        ctx.translateBy(x: base.x, y: base.y)
        ctx.rotate(by: .degrees(-14))
        // Local coordinates: u world units, y up the screen from the ground contact.
        func L(_ lx: Double, _ ly: Double) -> CGPoint { CGPoint(x: CGFloat(lx) * s, y: -CGFloat(ly) * s) }
        let r = 0.36
        let rear = L(-0.52, r), front = L(0.52, r)
        for c in [rear, front] {
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - CGFloat(r) * s, y: c.y - CGFloat(r) * s, width: 2 * CGFloat(r) * s, height: 2 * CGFloat(r) * s)),
                       with: .color(dark), style: StrokeStyle(lineWidth: 0.06 * s))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - CGFloat(r - 0.045) * s, y: c.y - CGFloat(r - 0.045) * s,
                                              width: 2 * CGFloat(r - 0.045) * s, height: 2 * CGFloat(r - 0.045) * s)),
                       with: .color(grey.opacity(0.7)), style: StrokeStyle(lineWidth: 0.012 * s))
            ellipse(c, 0.07 * s, 0.07 * s, grey)
        }
        let bb = L(-0.05, 0.3), seat = L(-0.2, 0.84), head = L(0.4, 0.8)
        let w = max(1.6, 0.05 * s)
        // Frame tubes, then the fork, handlebar and saddle.
        stroke([bb, seat], width: w, frame)
        stroke([seat, head], width: w, frame)
        stroke([bb, head], width: w, frame)
        stroke([bb, rear], width: w * 0.8, frame)
        stroke([seat, rear], width: w * 0.8, frame)
        stroke([head, front], width: w * 0.8, grey)
        stroke([head, L(0.36, 0.92), L(0.5, 0.95)], width: w * 0.8, dark)
        stroke([seat, L(-0.22, 0.92)], width: w * 0.8, grey)
        ctx.fill(Path(roundedRect: CGRect(x: L(-0.36, 0.95).x, y: L(-0.36, 0.95).y, width: 0.3 * s, height: 0.07 * s), cornerRadius: 0.03 * s),
                 with: .color(dark))
        // Crank and pedal.
        stroke([bb, L(0.02, 0.2)], width: w * 0.6, dark)
        stroke([L(-0.02, 0.2), L(0.12, 0.2)], width: w * 0.8, dark)
        ctx = saved
    }

    /// A kettle barbecue on three legs: a black bowl and a domed lid with a vent and a handle.
    private func urbanDrawBarbecue(x: Double, z: Double) {
        let s = screenPerUnit(x: x, y: 0, z: z)
        let base = at3(x, 0, z)
        func P(_ dx: Double, _ h: Double) -> CGPoint { upright(x + dx, h, z, scale: s) }
        urbanShadow(base, w: 0.8 * s, h: 0.18 * s, height: 0.95 * s)
        let black = Color(hex: 0x2B2D31), blackShade = Color(hex: 0x1D1F22), lid = Color(hex: 0x3A3E44), metal = Color(hex: 0x9A9EA4)
        // Legs.
        for dx in [-0.24, 0.0, 0.24] { stroke([P(dx * 0.4, 0.5), P(dx, 0)], width: max(1.5, 0.035 * s), blackShade) }
        stroke([P(-0.2, 0.18), P(0.2, 0.18)], width: max(1.2, 0.025 * s), blackShade)
        // Bowl (a half-ellipse hanging from the rim) and the lid dome above.
        let rim = P(0, 0.62)
        let bowl = CGRect(x: rim.x - 0.31 * s, y: rim.y - 0.14 * s, width: 0.62 * s, height: 0.52 * s)
        ctx.fill(Path(ellipseIn: bowl.offsetBy(dx: 0.02 * s, dy: 0.02 * s)), with: .color(blackShade))
        ctx.fill(Path(ellipseIn: bowl), with: .color(black))
        var dome = Path()
        dome.addArc(center: CGPoint(x: rim.x, y: rim.y), radius: 0.32 * s, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        dome.closeSubpath()
        ctx.fill(dome.applying(CGAffineTransform(translationX: 0.02 * s, y: 0.02 * s)), with: .color(blackShade))
        ctx.fill(dome, with: .color(lid))
        // A chrome rim, a vent on top and a handle.
        stroke([CGPoint(x: rim.x - 0.32 * s, y: rim.y), CGPoint(x: rim.x + 0.32 * s, y: rim.y)], width: max(1.5, 0.03 * s), metal)
        ellipse(CGPoint(x: rim.x, y: rim.y - 0.33 * s), 0.1 * s, 0.05 * s, metal)
        stroke([CGPoint(x: rim.x + 0.28 * s, y: rim.y - 0.07 * s), CGPoint(x: rim.x + 0.4 * s, y: rim.y - 0.14 * s)], width: max(1.5, 0.03 * s), metal)
    }
}
