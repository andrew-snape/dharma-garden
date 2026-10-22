import SwiftUI
import DharmaGardenCore

/// Sky, clouds, hills, lawn and the back fence. These sit behind the patch.
extension SceneCanvas {
    /// Share of the scene height where the sky meets the lawn at the back fence.
    var fenceBaseY: Double { camera.project(x: 0, z: Self.fenceZ).y }
    var fenceTopY: Double { camera.upright(x: 0, z: Self.fenceZ, height: Self.fenceHeight).y }

    func drawSky() {
        let top = SceneColour.color(palette.skyTop), bottom = SceneColour.color(palette.skyBottom)
        let grad = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [top, bottom]), startPoint: p(0, 0), endPoint: p(0, fenceBaseY))
        ctx.fill(Path(bleed(CGRect(origin: .zero, size: size))), with: grad)
    }

    /// Extends a full-frame rect a little past each edge, so layers shifted by parallax leave no gap.
    func bleed(_ r: CGRect) -> CGRect { r.insetBy(dx: -0.05 * size.width, dy: -0.05 * size.height) }

    /// Flat, rounded clouds. More of them when the palette is grey (overcast, rain, fog).
    func drawClouds() {
        let greyness = 1 - min(1, SceneColour.chroma(palette.skyTop) / 0.4)
        let cloudy = min(1, palette.rainStrength + palette.fogStrength * 0.4 + greyness * 0.7)
        let count = 2 + Int(cloudy * 4.99)
        let base = SceneColour.lerp(RGB(1, 0.98, 0.93), palette.skyBottom, cloudy * 0.3)
        let cloud = SceneColour.color(base)
        let shade = SceneColour.color(SceneColour.scaled(base, 0.9))
        // Fixed layout, moved only by the motion state: each cloud drifts slowly right and wraps.
        let spots: [(x: Double, y: Double, s: Double)] = [
            (0.18, 0.14, 0.075), (0.62, 0.12, 0.09), (0.86, 0.2, 0.06),
            (0.40, 0.2, 0.05), (0.05, 0.25, 0.05), (0.74, 0.27, 0.045),
        ]
        let travel = motion.cloudTravel
        for (i, spot) in spots.prefix(count).enumerated() {
            let x = Self.wrapCloudX(spot.x + travel * (1 + 0.25 * Double(i % 3)))
            drawCloud(p(x, spot.y), r: spot.s * unit, cloud, shade)
        }
    }

    /// Same as `SceneMotion.wrapCloudX`, reachable from the scene canvas.
    static func wrapCloudX(_ x: Double) -> Double { SceneMotion.wrapCloudX(x) }

    private func drawCloud(_ c: CGPoint, r: CGFloat, _ cloud: Color, _ shade: Color) {
        let parts: [(dx: CGFloat, dy: CGFloat, rad: CGFloat)] = [(-0.55, -0.05, 0.42), (0.05, -0.28, 0.6), (0.72, -0.02, 0.4)]
        func draw(_ o: CGFloat, _ color: Color) {
            let body = CGRect(x: c.x - 1.3 * r, y: c.y - 0.35 * r + o, width: 2.6 * r, height: 0.7 * r)
            ctx.fill(Path(roundedRect: body, cornerRadius: 0.35 * r), with: .color(color))
            for part in parts {
                let rad = part.rad * r
                let rect = CGRect(x: c.x + part.dx * r - rad, y: c.y + part.dy * r - rad + o, width: rad * 2, height: rad * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
        draw(0.06 * r, shade)
        draw(0, cloud)
    }

    /// Two layers of soft hills just behind the fence. They read as a painted backdrop: a 45 degree
    /// view cannot see the true horizon, so the hills sit where the back of the garden meets the sky.
    func drawHills() {
        let far = SceneColour.lerp(palette.skyBottom, palette.grass, 0.45)
        let near = SceneColour.lerp(palette.grass, RGB(0.2, 0.3, 0.2), 0.12)
        layer(baseY: fenceTopY + 0.02, amp: 0.085, phase: 0.8, colour: far)
        layer(baseY: fenceTopY + 0.03, amp: 0.05, phase: 2.1, colour: near)
    }

    private func layer(baseY: Double, amp: Double, phase: Double, colour: RGB) {
        var pts: [CGPoint] = []
        // Runs a little past each edge so the layer still covers the frame when it is shifted by parallax.
        for i in 0...60 {
            let x = -0.05 + 1.1 * Double(i) / 60
            let wave = 0.55 * sin(x * 6.5 + phase) + 0.3 * sin(x * 14 + phase * 2) + 0.55
            pts.append(p(x, baseY - amp * wave))
        }
        pts.append(p(1.05, baseY + 0.12))
        pts.append(p(-0.05, baseY + 0.12))
        fill(pts, SceneColour.color(colour))
    }

    /// The lawn: a plain field from the back fence to the bottom, with a few soft patches of colour.
    func drawLawn() {
        let grass = palette.grass
        fillRect(-0.05, fenceBaseY - 0.005, 1.05, 1.05, SceneColour.color(grass))
        let lighter = SceneColour.color(SceneColour.lerp(grass, RGB(1, 1, 0.8), 0.12))
        let darker = SceneColour.color(SceneColour.scaled(grass, 0.92))
        let patches: [(x: Double, y: Double, w: Double, h: Double, c: Color)] = [
            (0.18, 0.46, 0.5, 0.05, lighter), (0.80, 0.56, 0.6, 0.06, darker),
            (0.3, 0.97, 0.5, 0.05, lighter), (0.92, 0.72, 0.4, 0.05, lighter),
        ]
        for patch in patches {
            ellipse(p(patch.x, patch.y), patch.w * unit, patch.h * unit, patch.c)
        }
    }

    /// The barrier across the back in `style` (the farm's is a simple wooden fence with rails and posts). The
    /// backyard's side barriers are built from the same `BarrierFrame`, so they meet this one exactly at its ends.
    func drawBarrier(_ style: BarrierStyle) {
        drawBarrierParts(BarrierFrame(camera: camera, size: size, style: style).backBarrier(), style: style)
    }

    /// Fills barrier parts in order. Every style draws as the rail fence for now (rails and posts in wood colours,
    /// each with a darker copy nudged as shade); a theme with its own style draws its parts itself.
    func drawBarrierParts(_ parts: [BarrierPart], style: BarrierStyle) {
        let board = Color(hex: 0xD9B98A), boardShade = Color(hex: 0xB08D5E)
        let post = Color(hex: 0xC49D6C), postShade = Color(hex: 0x9C7448)
        for part in parts {
            if part.isPost {
                fill(part.quad.map { CGPoint(x: $0.x + 2, y: $0.y) }, postShade)
                fill(part.quad, post)
            } else {
                fill(part.quad.map { CGPoint(x: $0.x, y: $0.y + 2) }, boardShade)
                fill(part.quad, board)
            }
        }
    }
}

/// The kinds of barrier along the back and sides of the yard. Only the rail fence is built so far: the other styles
/// are declared for the themes to fill in and return the rail fence until they do.
enum BarrierStyle: CaseIterable {
    case railFence, bambooSlat, earthWall, dryStoneWall, timberPanel
}

/// One rail or post of a barrier, as a canvas quad.
struct BarrierPart {
    let quad: [CGPoint]
    let isPost: Bool
}

/// A barrier in screen space. Every corner comes from one projection, so the back barrier and the side barriers meet
/// exactly. Heights go through `Camera.upright`: ends and post edges stay vertical on screen, and horizontal lines at
/// any height run to the same vanishing point as the lawn's edge lines. A new style builds its parts from `point(...)`
/// the same way, in the `switch` in `backBarrier()` and `sideBarrier(x:)`.
struct BarrierFrame {
    let camera: Camera
    let size: CGSize
    var style: BarrierStyle = .railFence

    /// The back fence runs from x = -halfLength to halfLength, along z = `SceneCanvas.fenceZ`.
    static let halfLength = 4.5
    /// Rails sit at these heights, each `railDepth` thick, in world units.
    static let railHeights = [0.24, 0.58, 0.92]
    static let railDepth = 0.12
    /// Posts are `postWidth` wide in world units and `postSpacing` apart along the fence.
    static let postWidth = 0.07
    static let postSpacing = 0.9
    /// The corner posts stand a little taller than the rest, so they cover where the fences meet.
    static let cornerHeight = SceneCanvas.fenceHeight + 0.1

    /// Canvas point of a fence corner at world (x, z) and height.
    func point(x: Double, z: Double, height: Double = 0) -> CGPoint {
        let q = camera.upright(x: x, z: z, height: height)
        return CGPoint(x: q.x * size.width, y: q.y * size.height)
    }

    /// Canvas points per world unit along x at (x, z): the scale a post's width follows.
    func unitWidth(x: Double, z: Double) -> CGFloat {
        abs(point(x: x + 1, z: z).x - point(x: x, z: z).x)
    }

    /// A rail from `a` to `b` at `height`, one rail thick.
    func rail(from a: (x: Double, z: Double), to b: (x: Double, z: Double), height h: Double) -> [CGPoint] {
        [point(x: a.x, z: a.z, height: h), point(x: b.x, z: b.z, height: h),
         point(x: b.x, z: b.z, height: h + Self.railDepth), point(x: a.x, z: a.z, height: h + Self.railDepth)]
    }

    /// A post standing on the ground at (x, z), up to `height`. It is centred on its base and as wide as
    /// `postWidth` at that depth.
    func post(x: Double, z: Double, height: Double) -> [CGPoint] {
        let base = point(x: x, z: z), top = point(x: x, z: z, height: height)
        let w = CGFloat(Self.postWidth) * unitWidth(x: x, z: z)
        return [CGPoint(x: base.x - w / 2, y: base.y), CGPoint(x: base.x + w / 2, y: base.y),
                CGPoint(x: base.x + w / 2, y: top.y), CGPoint(x: base.x - w / 2, y: top.y)]
    }

    /// The back barrier from one end to the other, in this frame's style.
    func backBarrier() -> [BarrierPart] {
        switch style {
        case .railFence, .bambooSlat, .earthWall, .dryStoneWall, .timberPanel: railBack()   // TODO: per theme
        }
    }

    /// A side barrier at x, from the back barrier's end toward the viewer, in this frame's style.
    func sideBarrier(x: Double) -> [BarrierPart] {
        switch style {
        case .railFence, .bambooSlat, .earthWall, .dryStoneWall, .timberPanel: railSide(x: x)   // TODO: per theme
        }
    }

    /// The rail fence across the back: its rails, then a post every `postSpacing` from one end to the other.
    private func railBack() -> [BarrierPart] {
        let z = SceneCanvas.fenceZ, h = Self.halfLength
        var parts = Self.railHeights.map { BarrierPart(quad: rail(from: (-h, z), to: (h, z), height: $0), isPost: false) }
        for x in stride(from: -h, through: h + 1e-9, by: Self.postSpacing) {
            parts.append(BarrierPart(quad: post(x: x, z: z, height: SceneCanvas.fenceHeight), isPost: true))
        }
        return parts
    }

    /// A rail side fence at x, from the back fence's end toward the viewer. Its first post is the taller corner post
    /// at the join, and the rest stand every `postSpacing` from there.
    private func railSide(x: Double) -> [BarrierPart] {
        let z0 = SceneCanvas.fenceZ, z1 = 2.9   // stops short of the camera, which sits at z = 4
        var parts = Self.railHeights.map { BarrierPart(quad: rail(from: (x, z0), to: (x, z1), height: $0), isPost: false) }
        for z in stride(from: z0 + Self.postSpacing, through: z1 + 1e-9, by: Self.postSpacing) {
            parts.append(BarrierPart(quad: post(x: x, z: z, height: SceneCanvas.fenceHeight), isPost: true))
        }
        parts.append(BarrierPart(quad: post(x: x, z: z0, height: Self.cornerHeight), isPost: true))
        return parts
    }
}
