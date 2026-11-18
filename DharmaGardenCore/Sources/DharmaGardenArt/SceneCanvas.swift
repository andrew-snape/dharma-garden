import SwiftUI
import DharmaGardenCore

/// Colour helpers for the scene, working on the RGB values from `ScenePalette`.
enum SceneColour {
    static func color(_ c: RGB) -> Color { Color(red: c.r, green: c.g, blue: c.b) }

    static func lerp(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        let k = clamp01(t)
        return RGB(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k)
    }

    static func scaled(_ c: RGB, _ f: Double) -> RGB { RGB(c.r * f, c.g * f, c.b * f) }

    static func chroma(_ c: RGB) -> Double { max(c.r, c.g, c.b) - min(c.r, c.g, c.b) }
}

/// Draws the scene in normalised coordinates (0...1, y down) onto a Canvas of `size` points.
/// Every layer uses the same camera, so everything agrees with tap hit testing.
final class SceneCanvas {
    var ctx: GraphicsContext
    let size: CGSize
    let camera: Camera
    let palette: ScenePalette
    /// Animation state for this frame (clouds, rain, fog). `.still` draws a static picture.
    let motion: SceneMotion.Frame
    /// Framing and backdrop: first person, or the backyard extras (house, tree, hoist, side fences).
    let style: SceneStyle
    /// The garden theme: which horizon, barrier, buildings and ambient touches the hooks in SceneTheme.swift draw.
    let theme: SceneTheme
    /// How far the soil of the bed sits above the lawn, in world units (see `SceneCanvas.ground`). Zero except for
    /// planter boxes.
    var soilLift: Double = 0
    /// True while the player carries the watering can: the one resting on the lawn is not drawn (see SceneWateringCan.swift).
    var wateringCanCarried = false

    init(ctx: GraphicsContext, size: CGSize, camera: Camera, palette: ScenePalette,
         motion: SceneMotion.Frame = .still, style: SceneStyle = .firstPerson, theme: SceneTheme = .farm) {
        self.ctx = ctx
        self.size = size
        self.camera = camera
        self.palette = palette
        self.motion = motion
        self.style = style
        self.theme = theme
    }

    /// World depth (z) of the back fence on the lawn, just behind the back edge of the patch.
    static let fenceZ = -3.3
    /// Fence height in world units.
    static let fenceHeight = 1.1

    /// Normalised point to canvas points.
    func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * size.width, y: y * size.height) }

    /// A world point (x across, z toward the viewer, height), in canvas points.
    func world(x: Double, z: Double, height: Double = 0) -> CGPoint {
        let q = camera.project(x: x, z: z, height: height)
        return p(q.x, q.y)
    }

    /// Width of the scene in points; used as the base unit for sizes.
    var unit: CGFloat { size.width }

    func fill(_ pts: [CGPoint], _ color: Color) {
        guard let first = pts.first else { return }
        var path = Path()
        path.move(to: first)
        for q in pts.dropFirst() { path.addLine(to: q) }
        path.closeSubpath()
        ctx.fill(path, with: .color(color))
    }

    func fillRect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ color: Color) {
        ctx.fill(Path(CGRect(origin: p(x0, y0), size: CGSize(width: (x1 - x0) * size.width, height: (y1 - y0) * size.height))),
                 with: .color(color))
    }

    func ellipse(_ c: CGPoint, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)), with: .color(color))
    }

    /// A shape with a darker copy nudged down beneath it, matching the flower style.
    func shadedFill(_ pts: [CGPoint], _ color: Color, _ shade: Color, drop: CGFloat) {
        fill(pts.map { CGPoint(x: $0.x, y: $0.y + drop) }, shade)
        fill(pts, color)
    }

    func stroke(_ pts: [CGPoint], width: CGFloat, _ color: Color) {
        guard let first = pts.first else { return }
        var path = Path()
        path.move(to: first)
        for q in pts.dropFirst() { path.addLine(to: q) }
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
}
