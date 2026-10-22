import SwiftUI
import DharmaGardenCore

/// The Rural UK theme's scene hooks, called by the dispatchers in SceneTheme.swift. The land (horizon, ground,
/// foreground) is in SceneThemeUKLand.swift, the dry-stone wall and gate in SceneThemeUKWall.swift, the cottage and
/// oak in SceneThemeUKCottage.swift and the smoke, window glow and robin in SceneThemeUKAmbient.swift.
extension SceneCanvas {
    /// A little greyer and cooler than the farm's sky.
    func ukSky() {
        let top = SceneColour.color(ukSoften(palette.skyTop)), bottom = SceneColour.color(ukSoften(palette.skyBottom))
        let grad = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [top, bottom]), startPoint: p(0, 0), endPoint: p(0, fenceBaseY))
        ctx.fill(Path(bleed(CGRect(origin: .zero, size: size))), with: grad)
    }

    /// Soft cumulus with flat bottoms: more of them, and bigger, than the farm's, and greyer when it is overcast.
    func ukClouds() {
        let greyness = 1 - min(1, SceneColour.chroma(palette.skyTop) / 0.4)
        let cloudy = min(1, palette.rainStrength + palette.fogStrength * 0.4 + greyness * 0.7)
        let count = 4 + Int(cloudy * 4.99)
        let base = SceneColour.lerp(RGB(0.99, 0.98, 0.95), ukSoften(palette.skyBottom, 0.4), 0.1 + cloudy * 0.4)
        let cloud = SceneColour.color(base)
        let belly = SceneColour.color(SceneColour.lerp(base, SceneColour.scaled(base, 0.84), 0.55))
        let shade = SceneColour.color(SceneColour.lerp(SceneColour.scaled(base, 0.82), RGB(0.62, 0.67, 0.78), 0.3))
        // Fixed layout (baseline y), moved only by the motion state: each cloud drifts slowly right and wraps.
        let spots: [(x: Double, y: Double, s: Double)] = [
            (0.14, 0.13, 0.07), (0.58, 0.105, 0.085), (0.86, 0.16, 0.06), (0.36, 0.17, 0.05),
            (0.03, 0.2, 0.045), (0.72, 0.2, 0.04), (0.47, 0.065, 0.04), (0.96, 0.075, 0.05),
        ]
        let travel = motion.cloudTravel
        for (i, spot) in spots.prefix(count).enumerated() {
            let x = Self.wrapCloudX(spot.x + travel * (1 + 0.25 * Double(i % 3)))
            ukCloud(p(x, spot.y), r: spot.s * unit * 0.8, variant: i, cloud, belly, shade)
        }
    }

    /// A cumulus: round puffs standing on one flat baseline `c.y`, with a darker belly and a shade lip underneath.
    private func ukCloud(_ c: CGPoint, r: CGFloat, variant: Int, _ cloud: Color, _ belly: Color, _ shade: Color) {
        let puffs: [(dx: CGFloat, rad: CGFloat)] = variant % 2 == 0
            ? [(-1.0, 0.5), (-0.4, 0.82), (0.3, 1.0), (1.0, 0.68), (1.55, 0.4)]
            : [(-0.9, 0.42), (-0.25, 0.7), (0.45, 0.9), (1.1, 0.5)]
        let left = puffs.first!.dx, right = puffs.last!.dx
        func draw(_ o: CGFloat, _ color: Color) {
            let body = CGRect(x: c.x + left * r, y: c.y - 0.5 * r + o, width: (right - left) * r, height: 0.5 * r)
            ctx.fill(Path(body), with: .color(color))
            for puff in puffs {
                let rad = puff.rad * r
                let rect = CGRect(x: c.x + puff.dx * r - rad, y: c.y - 2 * rad + o, width: rad * 2, height: rad * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
        draw(0.07 * r, shade)
        draw(0, cloud)
        // The belly: a flat band along the bottom, inside the cloud.
        let band = CGRect(x: c.x + left * r, y: c.y - 0.2 * r, width: (right - left) * r, height: 0.2 * r)
        ctx.fill(Path(band), with: .color(belly))
    }

    func ukHorizon() { ukDrawHorizon() }
    /// Both scene styles (check `style` for the backyard extras).
    func ukGround() { ukDrawGround() }
    func ukBarrier() { ukDrawBarrier() }
    /// Backyard only.
    func ukBackdropProps() { ukDrawBackdrop() }
    /// Backyard only.
    func ukSideBarriers() { ukDrawSideWalls() }
    func ukForeground() { ukDrawForeground() }
    /// Drawn over the darkness overlay (see `drawWeatherOverlays`), so lights can glow at dusk and night.
    func ukAmbient() { ukDrawAmbient() }
}
