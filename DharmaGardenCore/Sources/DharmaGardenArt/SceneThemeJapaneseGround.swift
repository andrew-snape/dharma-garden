import SwiftUI
import DharmaGardenCore

/// The Japanese theme's ground: a moss-green lawn, a raked-gravel strip (karesansui) along the front edge with a
/// rock and its ripples, border stones and a few stepping stones in the side margins. The bed fills the middle of
/// the frame, so every feature stays at the edges: the gravel hugs the bottom, the stones keep to the left and right
/// margins, and the lower-right corner is left to the foreground lantern.
extension SceneCanvas {
    /// Normalised y of the gravel strip's top edge at x: lowest in the middle, curving up toward the corners (where
    /// the bed is far away), so the strip clears the bed.
    func japaneseGravelTop(_ x: Double) -> Double {
        let centre = style == .backyard ? 0.918 : 0.947
        let d = abs(x - 0.5) * 2
        return centre - 0.15 * pow(d, 2.6)
    }

    func drawJapaneseGround() {
        drawJapaneseLawn()
        drawJapaneseGravel()
        drawJapaneseSteppingStones()
        if style == .backyard { drawJapaneseMossMounds() }
    }

    /// Moss lawn: the palette's grass cooled toward blue-green, with softly lighter and darker patches and fine moss
    /// flecks.
    private func drawJapaneseLawn() {
        let moss = SceneColour.lerp(palette.grass, RGB(0.34, 0.52, 0.38), 0.4)
        fillRect(-0.05, fenceBaseY - 0.005, 1.05, 1.05, SceneColour.color(moss))
        let lighter = SceneColour.color(SceneColour.lerp(moss, RGB(0.85, 1, 0.8), 0.14))
        let darker = SceneColour.color(SceneColour.scaled(moss, 0.9))
        let patches: [(x: Double, y: Double, w: Double, h: Double, c: Color)] = [
            (0.16, 0.46, 0.5, 0.05, lighter), (0.84, 0.54, 0.5, 0.06, darker),
            (0.3, 0.8, 0.4, 0.05, lighter), (0.92, 0.72, 0.4, 0.05, lighter), (0.5, 0.33, 0.6, 0.03, darker),
        ]
        for patch in patches { ellipse(p(patch.x, patch.y), patch.w * unit, patch.h * unit, patch.c) }
        // Flecks of lighter and darker moss, deterministic.
        for i in 0..<70 {
            let x = unitHash(0xA0551, UInt64(i * 3)), y = fenceBaseY + 0.03 + (0.85 - fenceBaseY) * unitHash(0xA0551, UInt64(i * 3 + 1))
            let c = p(x, y), w = (0.008 + 0.014 * unitHash(0xA0551, UInt64(i * 3 + 2))) * unit
            ellipse(c, w, w * 0.4, i % 2 == 0 ? lighter : darker)
        }
    }

    /// The gravel strip with its border stones, raked wavy lines and a rock with concentric ripples.
    private func drawJapaneseGravel() {
        let gravel = Color(hex: 0xDDD5C3), gravelShade = Color(hex: 0xBDB4A0), gravelLight = Color(hex: 0xF0EADB)
        let xs = (0...80).map { -0.05 + 1.1 * Double($0) / 80 }
        let top = xs.map { p($0, japaneseGravelTop($0)) }
        var region = top
        region.append(p(1.05, 1.06)); region.append(p(-0.05, 1.06))
        fill(region, gravel)
        // Raked lines, each following the strip's edge with its own gentle wave.
        let lines = style == .backyard ? 5 : 4
        for k in 0..<lines {
            let f = (Double(k) + 0.8) / (Double(lines) + 0.5)
            let pts = xs.map { x -> CGPoint in
                let t = japaneseGravelTop(x)
                let wave = 0.0042 * sin(x * 34 + Double(k) * 0.9) + 0.0016 * sin(x * 81 + Double(k) * 2.1)
                return p(x, t + f * (1.02 - t) + wave)
            }
            stroke(pts.map { CGPoint(x: $0.x, y: $0.y + 1.2) }, width: 1.4, gravelLight)
            stroke(pts, width: 1.5, gravelShade)
        }
        // The rock: the raking parts around it in rings, so the gravel under it is cleared first.
        let rx = style == .backyard ? 0.2 : 0.2
        let ry = japaneseGravelTop(rx) + (1.02 - japaneseGravelTop(rx)) * 0.52
        let rc = p(rx, ry), ru = 0.012 * unit
        ellipse(rc, ru * 11.5, ru * 4.2, gravel)
        for (i, k) in [9.5, 7.2, 5.0].enumerated() {
            let rect = CGRect(x: rc.x - ru * k / 2 * 1.5, y: rc.y - ru * k * 0.19, width: ru * k * 1.5, height: ru * k * 0.38)
            ctx.stroke(Path(ellipseIn: rect.offsetBy(dx: 0, dy: 1.2)), with: .color(gravelLight), lineWidth: 1.3)
            ctx.stroke(Path(ellipseIn: rect), with: .color(gravelShade), lineWidth: 1.5)
            _ = i
        }
        drawJapaneseRock(at: rc, size: ru * 1.5)
        drawJapaneseRock(at: CGPoint(x: rc.x + ru * 1.6, y: rc.y + ru * 0.35), size: ru * 0.8)
        // Border stones along the edge of the gravel, and a darker lip of soil.
        stroke(top.map { CGPoint(x: $0.x, y: $0.y - 1) }, width: 3, SceneColour.color(SceneColour.scaled(palette.grass, 0.62)).opacity(0.6))
        let stone = Color(hex: 0x9C9A92), stoneShade = Color(hex: 0x76746C), stoneLight = Color(hex: 0xB6B3A9)
        var x = -0.02, i = 0
        while x < 1.03 {
            let w = (0.011 + 0.009 * unitHash(0xB0DE, UInt64(i))) * unit
            let c = p(x, japaneseGravelTop(x) + 0.002)
            ellipse(CGPoint(x: c.x + 1, y: c.y + 1.6), w, w * 0.62, stoneShade)
            ellipse(c, w, w * 0.62, i % 3 == 0 ? stoneLight : stone)
            x += (w / unit) * 1.05
            i += 1
        }
    }

    /// A flat rock: shade copy, body, highlight and a dab of moss on top. `at` is its centre.
    func drawJapaneseRock(at c: CGPoint, size u: CGFloat) {
        let rock = Color(hex: 0x8F8D86), rockShade = Color(hex: 0x68665F), rockLight = Color(hex: 0xADAAA0)
        ellipse(CGPoint(x: c.x + 0.1 * u, y: c.y + 0.28 * u), u * 1.1, u * 0.52, Color.black.opacity(0.14))
        ellipse(CGPoint(x: c.x, y: c.y + 0.1 * u), u, u * 0.78, rockShade)
        ellipse(c, u, u * 0.78, rock)
        ellipse(CGPoint(x: c.x - 0.12 * u, y: c.y - 0.12 * u), u * 0.5, u * 0.3, rockLight)
        ellipse(CGPoint(x: c.x + 0.08 * u, y: c.y - 0.3 * u), u * 0.46, u * 0.2, Color(hex: 0x6E9A5A))
    }

    /// Stepping stones up the left and right margins, clear of the bed.
    private func drawJapaneseSteppingStones() {
        let stone = Color(hex: 0xBDB8A8), stoneShade = Color(hex: 0x94907F), stoneLight = Color(hex: 0xD3CFC0)
        let spots: [(x: Double, y: Double)] = [
            (0.045, 0.865), (0.032, 0.8), (0.03, 0.7), (0.028, 0.62),
            (0.955, 0.69), (0.94, 0.62), (0.96, 0.56),
        ]
        for spot in spots {
            let c = p(spot.x, spot.y)
            let w = (0.03 + 0.045 * max(0, spot.y - 0.5)) * unit, h = w * 0.55
            ellipse(CGPoint(x: c.x, y: c.y + 0.006 * unit), w, h, stoneShade)
            ellipse(c, w, h, stone)
            ellipse(CGPoint(x: c.x - w * 0.12, y: c.y - h * 0.15), w * 0.5, h * 0.4, stoneLight)
        }
    }

    /// Backyard only: a couple of rounded moss mounds with clipped azalea (satsuki) shrubs in the corners, kept to the
    /// margins beside the bed.
    private func drawJapaneseMossMounds() {
        let leaf = Color(hex: 0x4F7D55), leafShade = Color(hex: 0x3B6044), bloom = Color(hex: 0xE9779A), bloomLight = Color(hex: 0xF7B2C9)
        for (x, y, r) in [(0.035, 0.5, 0.03), (0.968, 0.46, 0.028)] {
            let c = p(x, y), w = r * 2 * unit
            ellipse(CGPoint(x: c.x, y: c.y + w * 0.32), w * 1.25, w * 0.3, Color.black.opacity(0.12))
            ellipse(CGPoint(x: c.x + 1.5, y: c.y + 2), w, w * 0.8, leafShade)
            ellipse(c, w, w * 0.8, leaf)
            for k in 0..<9 {
                let a = unitHash(0xA2A1, UInt64(k) + UInt64(x * 1000)) * 2 * Double.pi
                let d = 0.38 * unitHash(0xA2A2, UInt64(k) + UInt64(x * 1000))
                let b = CGPoint(x: c.x + CGFloat(cos(a) * d) * w, y: c.y + CGFloat(sin(a) * d) * w * 0.7 - w * 0.1)
                ellipse(b, 0.012 * unit, 0.01 * unit, k % 3 == 0 ? bloomLight : bloom)
            }
        }
    }
}
