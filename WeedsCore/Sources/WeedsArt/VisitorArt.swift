import SwiftUI
import WeedsCore

/// One visitor species, drawn flat like the plants: simple shapes with a darker shade layer under each one, no
/// outlines. The square's feet sit on the ground line (`groundLine` of its height). The picture faces right by
/// default and flips for `pose.facing`. A flyer's body rises by its pose height, and its shadow stays on the ground.
public struct VisitorArt: View, Sendable {
    /// Height of the ground line in the square, as a fraction of its side.
    public nonisolated static let groundLine = 0.9
    /// Square-side fractions that one world unit of height lifts the body by (about right for the default camera).
    public nonisolated static let liftPerWorldUnit = 1.3
    /// The flat colour of a silhouette (a species not yet spotted).
    public nonisolated static let silhouetteInk = Color(hex: 0x5A4A44)

    public var species: VisitorSpecies
    /// Side of the square, in points.
    public var size: CGFloat
    /// Flap, lift, facing, peck and opacity all come from the pose.
    public var pose: VisitorPose
    /// Draws the species as one flat dark shape (the collection book before a visitor is spotted).
    public var silhouette: Bool
    /// At night a moth gives off a faint glow.
    public var night: Bool

    public init(species: VisitorSpecies, size: CGFloat = 60, pose: VisitorPose = .resting,
                silhouette: Bool = false, night: Bool = false) {
        self.species = species
        self.size = size
        self.pose = pose
        self.silhouette = silhouette
        self.night = night
    }

    public var body: some View {
        Canvas { ctx, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            var g = ctx
            g.opacity = pose.opacity
            let painter = VisitorPainter(ctx: g, s: s, species: species, pose: pose, silhouette: silhouette, night: night)
            painter.draw()
        }
        .frame(width: size, height: size)
    }
}

/// Draws one visitor into a square of side `s`. Shapes are given in the square's 0...1 units, y down.
private final class VisitorPainter {
    let ctx: GraphicsContext
    let s: CGFloat
    let species: VisitorSpecies
    let pose: VisitorPose
    let silhouette: Bool
    let night: Bool
    /// The context the body is drawn with: lifted and flipped.
    private var g: GraphicsContext

    init(ctx: GraphicsContext, s: CGFloat, species: VisitorSpecies, pose: VisitorPose, silhouette: Bool, night: Bool) {
        self.ctx = ctx
        self.s = s
        self.species = species
        self.pose = pose
        self.silhouette = silhouette
        self.night = night
        self.g = ctx
    }

    /// How far the body is lifted off the ground, in square fractions.
    private var lift: Double { pose.height * VisitorArt.liftPerWorldUnit }

    func draw() {
        if !silhouette { drawShadow() }
        g = ctx
        g.translateBy(x: 0, y: CGFloat(-lift) * s)
        if pose.facing < 0 {
            g.translateBy(x: s / 2, y: 0)
            g.scaleBy(x: -1, y: 1)
            g.translateBy(x: -s / 2, y: 0)
        }
        switch species {
        case .bee: drawBee()
        case .cabbageWhiteButterfly: drawButterfly(wing: Ink.cream, shade: Ink.creamShade, edge: Color(hex: 0x7D766D),
                                                   tip: Color(hex: 0x4B4540), spots: false)
        case .orangeButterfly: drawButterfly(wing: Color(hex: Hue.calendula), shade: Color(hex: Hue.calendulaShade),
                                             edge: Ink.dark, tip: nil, spots: true)
        case .ladybird: drawLadybird()
        case .dragonfly: drawDragonfly()
        case .magpieLark: drawMagpieLark()
        case .willieWagtail: drawWillieWagtail()
        case .blueTongueLizard: drawLizard()
        case .snail: drawSnail()
        case .frog: drawFrog()
        case .moth: drawMoth()
        case .cockatoo: drawCockatoo()
        }
    }

    // MARK: Shared pieces

    /// Soft flat shadow on the ground under the visitor. It fades as the visitor rises.
    private func drawShadow() {
        let opacity = 0.22 * max(0.3, 1 - lift * 2)
        var path = Path()
        path.addEllipse(in: CGRect(x: 0.3 * s, y: (VisitorArt.groundLine - 0.035) * s, width: 0.4 * s, height: 0.07 * s))
        ctx.fill(path, with: .color(Color.black.opacity(opacity)))
    }

    private func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * s, y: y * s) }

    /// The colour to use: every shape is one dark colour in silhouette mode.
    private func ink(_ c: Color) -> Color { silhouette ? VisitorArt.silhouetteInk : c }

    /// An ellipse, optionally tilted about its centre.
    private func oval(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, angle: Double = 0) -> Path {
        var path = Path(ellipseIn: CGRect(x: (cx - rx) * s, y: (cy - ry) * s, width: 2 * rx * s, height: 2 * ry * s))
        if angle != 0 {
            let c = p(cx, cy)
            let a = CGFloat(angle)
            let cosA = cos(a), sinA = sin(a)
            // Rotation about the centre: x' = R x + (c - R c).
            let t = CGAffineTransform(a: cosA, b: sinA, c: -sinA, d: cosA,
                                      tx: c.x - (cosA * c.x - sinA * c.y), ty: c.y - (sinA * c.x + cosA * c.y))
            path = path.applying(t)
        }
        return path
    }

    private func poly(_ pts: [(Double, Double)]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: p(first.0, first.1))
        for q in pts.dropFirst() { path.addLine(to: p(q.0, q.1)) }
        path.closeSubpath()
        return path
    }

    /// A filled shape with a darker copy nudged down beneath it.
    private func fill(_ path: Path, _ colour: Color, shade: Color? = nil) {
        if let shade, !silhouette {
            g.fill(path.offsetBy(dx: 0, dy: 0.025 * s), with: .color(shade))
        }
        g.fill(path, with: .color(ink(colour)))
    }

    /// A stroked line (legs, antennae, stripes).
    private func line(_ pts: [(Double, Double)], _ width: Double, _ colour: Color) {
        guard let first = pts.first else { return }
        var path = Path()
        path.move(to: p(first.0, first.1))
        for q in pts.dropFirst() { path.addLine(to: p(q.0, q.1)) }
        g.stroke(path, with: .color(ink(colour)), style: StrokeStyle(lineWidth: CGFloat(width) * s, lineCap: .round, lineJoin: .round))
    }

    /// Wing or body flap, 0.3 (closed) to 1 (open), at `rate` flaps per second.
    private func flap(_ rate: Double) -> Double {
        0.3 + 0.7 * abs(cos(Double.pi * rate * pose.phase))
    }

    /// Head dip of a bird pecking on the lawn: 0 most of the time, a quick dip at the start of each cycle.
    private func peck(period: Double) -> Double {
        guard !pose.isMoving else { return 0 }
        let c = pose.phase / period
        let cycle = c - floor(c)
        return cycle < 0.35 ? sin(Double.pi * cycle / 0.35) : 0
    }

    // MARK: Species

    private func drawBee() {
        let w = flap(9)
        let wing = Color(hex: 0xEAF6FF)
        fill(oval(0.46, 0.4, 0.13, 0.11 * w, angle: -0.3), wing.opacity(0.85), shade: Color(hex: 0xB9D6EA))
        fill(oval(0.56, 0.4, 0.1, 0.09 * w, angle: 0.25), wing.opacity(0.85), shade: Color(hex: 0xB9D6EA))
        line([(0.66, 0.5), (0.7, 0.36)], 0.012, Ink.brown)
        line([(0.72, 0.5), (0.78, 0.38)], 0.012, Ink.brown)
        fill(oval(0.7, 0.36, 0.014, 0.014), Ink.brown)
        fill(oval(0.78, 0.38, 0.014, 0.014), Ink.brown)
        fill(poly([(0.3, 0.6), (0.2, 0.58), (0.3, 0.66)]), Ink.brown)
        fill(oval(0.5, 0.6, 0.2, 0.13), Ink.sunPetal, shade: Ink.sunPetalShade)
        fill(oval(0.44, 0.6, 0.035, 0.115), Ink.brown)
        fill(oval(0.55, 0.6, 0.035, 0.115), Ink.brown)
        fill(oval(0.7, 0.58, 0.09, 0.09), Ink.brown, shade: Ink.brownShade)
        fill(oval(0.73, 0.555, 0.025, 0.025), .white)
    }

    /// Both butterflies share one layout: four wings that open and close, a thin body and two antennae. `edge` is a
    /// darker rim round each wing (drawn first, so it shows as a border); `spots` adds pale dots near the outer edge.
    private func drawButterfly(wing: Color, shade: Color, edge: Color, tip: Color?, spots: Bool) {
        let open = flap(2.5)
        let span = 0.27 * open
        for side in [-1.0, 1.0] {
            let fx = 0.5 + side * span * 0.55
            let hx = 0.5 + side * span * 0.42
            fill(oval(fx, 0.4, span * 0.64, 0.175, angle: side * -0.35), edge)
            fill(oval(hx, 0.58, span * 0.5, 0.135, angle: side * 0.25), edge)
            fill(oval(hx, 0.58, span * 0.45, 0.11, angle: side * 0.25), wing, shade: shade)
            fill(oval(fx, 0.4, span * 0.58, 0.15, angle: side * -0.35), wing, shade: shade)
            if let tip {
                fill(oval(0.5 + side * span * 0.95, 0.33, 0.04, 0.035), tip)
            }
            if spots {
                fill(oval(0.5 + side * span * 0.8, 0.27, 0.025, 0.025), .white)
                fill(oval(0.5 + side * span * 0.66, 0.62, 0.022, 0.022), .white)
            }
        }
        line([(0.49, 0.36), (0.44, 0.24)], 0.01, Ink.dark)
        line([(0.51, 0.36), (0.56, 0.24)], 0.01, Ink.dark)
        fill(oval(0.44, 0.235, 0.014, 0.014), Ink.dark)
        fill(oval(0.56, 0.235, 0.014, 0.014), Ink.dark)
        fill(oval(0.5, 0.52, 0.026, 0.17), Color(hex: 0x4B3B35))
        fill(oval(0.5, 0.36, 0.03, 0.03), Color(hex: 0x4B3B35))
    }

    private func drawLadybird() {
        let walk = pose.isMoving ? 1.0 : 0.0
        // Six short legs under the shell, swinging when it walks.
        for i in 0..<3 {
            let x = 0.36 + 0.13 * Double(i)
            let swing = 0.012 * sin(pose.phase * 14 + Double(i) * 2) * walk
            line([(x, 0.8), (x + swing, 0.9)], 0.014, Ink.dark)
            line([(x + 0.04, 0.8), (x + 0.04 - swing, 0.9)], 0.014, Ink.dark)
        }
        fill(oval(0.46, 0.66, 0.22, 0.19), Color(hex: 0xD9352A), shade: Color(hex: 0xA8261E))
        line([(0.3, 0.66), (0.64, 0.66)], 0.012, Color(hex: 0x2B211E))
        for (x, y) in [(0.36, 0.58), (0.5, 0.56), (0.4, 0.74), (0.55, 0.74), (0.28, 0.66)] {
            fill(oval(x, y, 0.03, 0.03), Color(hex: 0x2B211E))
        }
        line([(0.74, 0.56), (0.8, 0.44)], 0.01, Color(hex: 0x2B211E))
        line([(0.76, 0.58), (0.86, 0.5)], 0.01, Color(hex: 0x2B211E))
        fill(oval(0.72, 0.62, 0.085, 0.07), Color(hex: 0x2B211E))
        fill(oval(0.745, 0.6, 0.016, 0.016), .white)
    }

    private func drawDragonfly() {
        let w1 = flap(10), w2 = flap(10 * 0.9)
        let wing = Color(hex: 0xCFEFFF).opacity(0.7)
        fill(oval(0.6, 0.4, 0.2, 0.05 * w1, angle: -0.12), wing)
        fill(oval(0.5, 0.42, 0.19, 0.045 * w2, angle: -0.05), wing)
        fill(oval(0.6, 0.62, 0.2, 0.05 * w2, angle: 0.12), wing)
        fill(oval(0.5, 0.6, 0.19, 0.045 * w1, angle: 0.05), wing)
        fill(poly([(0.2, 0.56), (0.12, 0.5), (0.1, 0.56), (0.12, 0.6)]), Color(hex: 0x2F8FA8))
        line([(0.18, 0.555), (0.68, 0.52)], 0.03, Color(hex: 0x2F8FA8))
        fill(oval(0.66, 0.52, 0.09, 0.06), Color(hex: 0x2F8FA8), shade: Color(hex: 0x23738A))
        fill(oval(0.78, 0.5, 0.06, 0.055), Color(hex: 0x3DA5A0))
        fill(oval(0.8, 0.46, 0.05, 0.045), Color(hex: 0x4B7BD6))
        fill(oval(0.815, 0.44, 0.015, 0.015), .white)
    }

    private func drawMagpieLark() {
        let dip = peck(period: 1.6)
        let hx = 0.7 + 0.02 * dip, hy = 0.45 + 0.13 * dip
        let black = Color(hex: 0x2E2622)
        fill(poly([(0.3, 0.55), (0.1, 0.5), (0.14, 0.62), (0.3, 0.64)]), black)
        fill(oval(0.5, 0.6, 0.24, 0.15), black, shade: Color(hex: 0x17110F))
        fill(oval(0.5, 0.72, 0.2, 0.08), Ink.cream)
        fill(oval(0.44, 0.58, 0.17, 0.07, angle: -0.1), Color(hex: 0x1A1412))
        line([(0.46, 0.74), (0.45, 0.9)], 0.018, Color(hex: 0x7A5238))
        line([(0.56, 0.74), (0.58, 0.9)], 0.018, Color(hex: 0x7A5238))
        fill(oval(hx, hy, 0.1, 0.1), black)
        line([(hx - 0.04, hy - 0.03), (hx + 0.04, hy - 0.04)], 0.018, Ink.cream)
        fill(poly([(hx + 0.07, hy - 0.01), (hx + 0.17, hy + 0.02), (hx + 0.07, hy + 0.04)]), Color(hex: 0x4A4440))
        fill(oval(hx + 0.03, hy - 0.01, 0.014, 0.014), .white)
    }

    private func drawWillieWagtail() {
        let dip = peck(period: 1.4)
        let flick = 0.5 + 0.5 * sin(2 * Double.pi * pose.phase / 1.2)
        let tailTip = 0.26 + 0.12 * flick
        let black = Color(hex: 0x2A2320)
        // Long fanned tail, flicked up and down.
        fill(poly([(0.38, 0.54), (0.12, tailTip - 0.04), (0.08, tailTip + 0.04), (0.2, tailTip + 0.13), (0.38, 0.62)]), black)
        line([(0.1, tailTip + 0.0), (0.16, tailTip + 0.1)], 0.014, Ink.cream)
        fill(oval(0.46, 0.6, 0.18, 0.12), black, shade: Color(hex: 0x17110F))
        fill(oval(0.5, 0.7, 0.14, 0.06), Ink.cream)
        line([(0.48, 0.72), (0.46, 0.9)], 0.014, Color(hex: 0x7A5238))
        line([(0.53, 0.72), (0.55, 0.9)], 0.014, Color(hex: 0x7A5238))
        let hx = 0.64 + 0.02 * dip, hy = 0.46 + 0.1 * dip
        fill(oval(hx, hy, 0.09, 0.09), black)
        fill(oval(hx - 0.01, hy + 0.04, 0.04, 0.03), Ink.cream)
        line([(hx - 0.03, hy - 0.035), (hx + 0.05, hy - 0.04)], 0.016, Ink.cream)
        fill(poly([(hx + 0.08, hy - 0.01), (hx + 0.16, hy + 0.01), (hx + 0.08, hy + 0.03)]), Color(hex: 0x4A4440))
        fill(oval(hx + 0.03, hy - 0.02, 0.014, 0.014), .white)
    }

    private func drawLizard() {
        let body = Color(hex: 0x8D7158)
        let shade = Color(hex: 0x6A5340)
        // The blue tongue flicks out now and then while it basks.
        let c = pose.phase / 3.2
        let cycle = c - floor(c)
        if !pose.isMoving && cycle > 0.08 && cycle < 0.2 {
            line([(0.84, 0.69), (0.94, 0.7)], 0.016, Color(hex: 0x2F6BD6))
            line([(0.94, 0.7), (0.98, 0.66)], 0.012, Color(hex: 0x2F6BD6))
            line([(0.94, 0.7), (0.98, 0.74)], 0.012, Color(hex: 0x2F6BD6))
        }
        fill(poly([(0.28, 0.68), (0.06, 0.72), (0.28, 0.76)]), body, shade: shade)
        for x in [0.6, 0.66, 0.72] {
            line([(0.4 + (x - 0.6) * 0.5, 0.74), (0.6, 0.76)], 0.03, shade)
        }
        for (x, end) in [(0.4, 0.9), (0.6, 0.9)] {
            line([(x, 0.76), (x - 0.03, end)], 0.03, shade)
            line([(x + 0.14, 0.76), (x + 0.17, end)], 0.03, shade)
        }
        fill(oval(0.5, 0.7, 0.24, 0.1), body, shade: shade)
        for x in [0.42, 0.52, 0.6] {
            line([(x, 0.63), (x + 0.01, 0.77)], 0.014, shade)
        }
        fill(oval(0.74, 0.66, 0.11, 0.09), body, shade: shade)
        fill(oval(0.78, 0.63, 0.014, 0.014), Color(hex: 0x2B211E))
    }

    private func drawSnail() {
        // The foot, then the shell, then the head and eye stalks.
        fill(oval(0.48, 0.84, 0.3, 0.05), Color(hex: 0xD8C8A8), shade: Color(hex: 0xB3A184))
        line([(0.73, 0.68), (0.76, 0.52)], 0.014, Color(hex: 0xD8C8A8))
        line([(0.7, 0.68), (0.68, 0.55)], 0.014, Color(hex: 0xD8C8A8))
        fill(oval(0.76, 0.5, 0.02, 0.02), Ink.dark)
        fill(oval(0.68, 0.53, 0.02, 0.02), Ink.dark)
        fill(oval(0.71, 0.74, 0.08, 0.07), Color(hex: 0xD8C8A8))
        fill(oval(0.42, 0.6, 0.2, 0.2), Color(hex: 0xB7814F), shade: Color(hex: 0x8E5E33))
        fill(oval(0.42, 0.6, 0.13, 0.13), Color(hex: 0xD9A56B))
        fill(oval(0.42, 0.6, 0.06, 0.06), Color(hex: 0x9C6A3C))
    }

    private func drawFrog() {
        let green = Color(hex: 0x7FB35A), shade = Color(hex: 0x5F9243)
        // Hind legs folded beside the body, front legs down.
        fill(oval(0.26, 0.8, 0.12, 0.06), green, shade: shade)
        fill(oval(0.74, 0.8, 0.12, 0.06), green, shade: shade)
        line([(0.4, 0.74), (0.36, 0.88)], 0.03, green)
        line([(0.6, 0.74), (0.64, 0.88)], 0.03, green)
        fill(oval(0.5, 0.64, 0.24, 0.17), green, shade: shade)
        // The throat swells a little when it calls at night.
        let call = night && !pose.isMoving ? 0.02 * sin(pose.phase * 3) : 0
        fill(oval(0.52, 0.74, 0.14 + call, 0.08 + call / 2), Color(hex: 0xD8E8A0))
        fill(oval(0.4, 0.44, 0.07, 0.07), green, shade: shade)
        fill(oval(0.6, 0.44, 0.07, 0.07), green, shade: shade)
        fill(oval(0.4, 0.43, 0.045, 0.045), Color(hex: 0xFFF6E0))
        fill(oval(0.6, 0.43, 0.045, 0.045), Color(hex: 0xFFF6E0))
        fill(oval(0.41, 0.43, 0.02, 0.02), Ink.dark)
        fill(oval(0.61, 0.43, 0.02, 0.02), Ink.dark)
        fill(oval(0.42, 0.66, 0.02, 0.02), shade)
        fill(oval(0.6, 0.6, 0.02, 0.02), shade)
    }

    private func drawMoth() {
        let w = flap(4)
        if night {
            let glow = Gradient(colors: [Color(hex: 0xFFE9A8).opacity(0.45), Color(hex: 0xFFE9A8).opacity(0)])
            let centre = p(0.5, 0.5)
            g.fill(Path(CGRect(x: 0, y: 0, width: s, height: s)),
                   with: .radialGradient(glow, center: centre, startRadius: 0, endRadius: 0.5 * s))
        }
        let brown = Color(hex: 0x9C8062), brownShade = Color(hex: 0x6E5A44)
        fill(oval(0.64, 0.6, 0.14 * w + 0.04, 0.1), brown, shade: brownShade)
        fill(oval(0.36, 0.6, 0.14 * w + 0.04, 0.1), brown, shade: brownShade)
        fill(oval(0.36, 0.46, 0.2 * w + 0.04, 0.15, angle: 0.4), brown, shade: brownShade)
        fill(oval(0.64, 0.46, 0.2 * w + 0.04, 0.15, angle: -0.4), brown, shade: brownShade)
        fill(oval(0.31, 0.44, 0.03, 0.03), Ink.cream)
        fill(oval(0.69, 0.44, 0.03, 0.03), Ink.cream)
        line([(0.48, 0.37), (0.4, 0.22)], 0.01, Color(hex: 0x6E5A44))
        line([(0.52, 0.37), (0.6, 0.22)], 0.01, Color(hex: 0x6E5A44))
        fill(oval(0.5, 0.6, 0.06, 0.18), Color(hex: 0x6E5A44), shade: Color(hex: 0x4D3D2E))
        fill(oval(0.5, 0.4, 0.05, 0.05), Color(hex: 0x6E5A44))
    }

    private func drawCockatoo() {
        let dip = peck(period: 2.0)
        let hx = 0.7 + 0.03 * dip, hy = 0.44 + 0.12 * dip
        let grey = Color(hex: 0xB9B2A8)
        fill(poly([(0.28, 0.6), (0.1, 0.72), (0.14, 0.8), (0.32, 0.66)]), grey)
        line([(0.46, 0.74), (0.45, 0.9)], 0.016, Color(hex: 0x7A726A))
        line([(0.54, 0.74), (0.56, 0.9)], 0.016, Color(hex: 0x7A726A))
        fill(oval(0.5, 0.6, 0.24, 0.16), Ink.cream, shade: Ink.creamShade)
        fill(oval(0.44, 0.6, 0.2, 0.1, angle: 0.1), Color(hex: 0xE9D9B5))
        fill(oval(hx, hy, 0.12, 0.11), Ink.cream, shade: Ink.creamShade)
        // Yellow crest, raised at the back of the head.
        fill(poly([(hx - 0.05, hy - 0.06), (hx - 0.12, hy - 0.26), (hx - 0.04, hy - 0.2),
                   (hx, hy - 0.3), (hx + 0.06, hy - 0.08)]), Ink.sunPetal, shade: Ink.sunPetalShade)
        fill(oval(hx + 0.02, hy + 0.02, 0.05, 0.03), Color(hex: 0xF2C7A0))
        fill(oval(hx + 0.04, hy - 0.02, 0.014, 0.014), Ink.dark)
        fill(poly([(hx + 0.1, hy - 0.02), (hx + 0.2, hy + 0.0), (hx + 0.2, hy + 0.06), (hx + 0.12, hy + 0.04)]),
             Color(hex: 0x4A4440))
    }
}
