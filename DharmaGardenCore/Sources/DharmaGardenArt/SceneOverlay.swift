import SwiftUI
import DharmaGardenCore

/// Foreground props on the lawn, then the weather and light overlays over everything.
extension SceneCanvas {
    /// A watering can on the lawn at the bottom right, and a few grass tufts at the bottom left.
    func drawForeground() {
        drawGrassTufts()
        drawRestingWateringCan()
    }

    private func drawGrassTufts() {
        let blade = SceneColour.color(SceneColour.scaled(palette.grass, 0.78))
        let spots: [(x: Double, y: Double)] = [(0.05, 0.97), (0.11, 0.99), (0.2, 0.98)]
        for spot in spots {
            let base = p(spot.x, spot.y)
            for b in 0..<5 {
                let angle = -Double.pi / 2 + (Double(b) - 2) * 0.35
                let len = 0.035 * unit * (0.8 + 0.2 * CGFloat(b % 3))
                let tip = CGPoint(x: base.x + CGFloat(cos(angle)) * len, y: base.y + CGFloat(sin(angle)) * len)
                stroke([base, tip], width: 0.004 * unit, blade)
            }
        }
    }

    /// Flat watering can (lilac by default; the Japanese garden gives it a celadon glaze): body with a shade layer, a spout, a rose and a handle. `at` is the base centre.
    func drawLilacCan(at base: CGPoint, size u: CGFloat, body: Color = Color(hex: 0xA58BD3), bodyShade: Color = Color(hex: 0x7F66B0)) {
        let drop: CGFloat = 0.03 * u
        let bodyRect = CGRect(x: base.x - 0.5 * u, y: base.y - 0.55 * u, width: 0.7 * u, height: 0.55 * u)
        ctx.fill(Path(roundedRect: bodyRect.offsetBy(dx: 0, dy: drop), cornerRadius: 0.14 * u), with: .color(bodyShade))
        ctx.fill(Path(roundedRect: bodyRect, cornerRadius: 0.14 * u), with: .color(body))

        // Handle: an arc over the top of the body.
        var handle = Path()
        handle.move(to: CGPoint(x: base.x - 0.38 * u, y: base.y - 0.5 * u))
        handle.addQuadCurve(to: CGPoint(x: base.x + 0.12 * u, y: base.y - 0.5 * u),
                            control: CGPoint(x: base.x - 0.13 * u, y: base.y - 1.05 * u))
        ctx.stroke(handle, with: .color(bodyShade), style: StrokeStyle(lineWidth: 0.1 * u, lineCap: .round))

        // Spout: from the lower right of the body up and out to the rose.
        var spout = Path()
        spout.move(to: CGPoint(x: base.x + 0.18 * u, y: base.y - 0.2 * u))
        spout.addLine(to: CGPoint(x: base.x + 0.78 * u, y: base.y - 0.78 * u))
        ctx.stroke(spout, with: .color(bodyShade), style: StrokeStyle(lineWidth: 0.13 * u, lineCap: .round))
        ctx.stroke(spout, with: .color(body), style: StrokeStyle(lineWidth: 0.07 * u, lineCap: .round))

        // Rose at the tip of the spout.
        let rose = CGRect(x: base.x + 0.7 * u, y: base.y - 0.9 * u, width: 0.2 * u, height: 0.14 * u)
        ctx.fill(Path(roundedRect: rose, cornerRadius: 0.05 * u), with: .color(bodyShade))
    }

    /// Light and weather over the whole scene: warm tint, darkness, fog and rain streaks.
    func drawWeatherOverlays() {
        if palette.overlayStrength > 0 {
            let tint = SceneColour.color(palette.overlayTint)
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(tint.opacity(palette.overlayStrength)))
        }
        if palette.darkness > 0 {
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x10172B).opacity(palette.darkness)))
        }
        drawThemeAmbient()
        if palette.fogStrength > 0 {
            let fog = palette.fogStrength * 0.45 * motion.fogPulse
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(fog)))
        }
        if palette.rainStrength > 0 {
            drawRain()
        }
    }

    /// Rain streaks falling and wrapping. Positions are deterministic per streak; density follows rainStrength
    /// and fall speed is scaled by it too. Each streak has its own speed (within about 20%).
    private func drawRain() {
        let count = Int(palette.rainStrength * 160)
        let streak = Color.white.opacity(0.4)
        let fall = motion.rainFall(strength: palette.rainStrength)
        for i in 0..<count {
            let x = unitHash(0x7A1A, UInt64(i * 3)) * size.width
            let y0 = unitHash(0x7A1A, UInt64(i * 3 + 1))
            let speed = 0.8 + 0.4 * unitHash(0x7A1A, UInt64(i * 3 + 2))
            let fraction = y0 + fall * speed
            let y = (fraction - floor(fraction)) * size.height
            let len = 0.05 * size.height
            stroke([CGPoint(x: x, y: y), CGPoint(x: x - 0.25 * len, y: y + len)], width: 1.3, streak)
        }
    }
}
