import SwiftUI
import DharmaGardenCore

/// The watering can: one piece of art per theme (lilac on the farm, celadon in the Japanese garden, galvanised in the
/// rural UK, apple green in the city). It rests on the lawn at the bottom right as a foreground prop, the pouring can
/// of the water tool is the same drawing turned about its rose, and the player can carry it (the scene then leaves
/// the resting one out and draws the carried one at the pointer).
extension SceneCanvas {
    /// Where the can rests: the base centre in normalised scene coordinates, and its size as a share of the scene
    /// width. Set on open lawn beside the bed's right-front corner, in the middle band of the scene that a window
    /// never crops and above the bottom tool bar, clear of the sundial, the pot and the lantern.
    static func wateringCanSpot(theme: SceneTheme) -> (x: Double, y: Double, size: Double) {
        switch theme {
        case .farm: (0.84, 0.79, 0.08)
        case .japanese: (0.84, 0.79, 0.08)
        case .ruralUK: (0.84, 0.79, 0.08)
        case .urban: (0.84, 0.79, 0.08)
        }
    }

    /// Where the rose sits on the can, from the base centre in units of its size (y is up, so negative).
    static func wateringCanRose(theme: SceneTheme) -> CGPoint {
        switch theme {
        case .farm, .japanese: CGPoint(x: 0.8, y: -0.83)
        case .ruralUK: CGPoint(x: 0.92, y: -0.88)
        case .urban: CGPoint(x: 0.98, y: -0.88)
        }
    }

    /// The can drawn upright with its base centre at `base`, `u` points across.
    func drawWateringCanArt(at base: CGPoint, size u: CGFloat) {
        switch theme {
        case .farm: drawLilacCan(at: base, size: u)
        case .japanese: drawLilacCan(at: base, size: u, body: Color(hex: 0x8FBBA4), bodyShade: Color(hex: 0x62907B))
        case .ruralUK: ukDrawWateringCan(at: base, size: u)
        case .urban: urbanWateringCan(at: base, size: u)
        }
    }

    /// The can turned `tilt` radians clockwise about its rose, with the rose at `rose`.
    func drawWateringCan(roseAt rose: CGPoint, size u: CGFloat, tilt: Double) {
        let anchor = Self.wateringCanRose(theme: theme)
        let saved = ctx
        ctx.translateBy(x: rose.x, y: rose.y)
        ctx.rotate(by: .radians(tilt))
        ctx.translateBy(x: -anchor.x * u, y: -anchor.y * u)
        drawWateringCanArt(at: .zero, size: u)
        ctx = saved
    }

    /// The can on the lawn, unless the player is carrying it. Part of every theme's foreground.
    func drawRestingWateringCan() {
        guard !wateringCanCarried else { return }
        let spot = Self.wateringCanSpot(theme: theme)
        propShadow(foot: p(spot.x, spot.y), height: 0.9 * spot.size * unit, width: 0.8 * spot.size * unit,
                   depth: 0.16 * spot.size * unit, opacity: 0.16)
        drawWateringCanArt(at: p(spot.x, spot.y), size: spot.size * unit)
    }

    /// The carried can: upright, a little lifted, its body centred under `point` (the pointer). Drawn above everything.
    func drawCarriedWateringCan(at point: CGPoint) {
        let u = Self.wateringCanSpot(theme: theme).size * unit
        let lift = 0.12 * u
        // A soft shadow on the ground beneath, then the can hanging just above it.
        propShadow(foot: CGPoint(x: point.x, y: point.y + 0.04 * u), height: 0.9 * u, width: 0.8 * u, depth: 0.16 * u, opacity: 0.2)
        drawWateringCanArt(at: CGPoint(x: point.x, y: point.y - lift), size: u)
    }
}

extension SceneContent {
    /// The resting can's footprint on screen in the scene's own coordinates (points). `layerShift` is the foreground
    /// parallax at the moment of the press (zero when the drift is off).
    static func wateringCanRect(size: CGSize, theme: SceneTheme, layerShift: CGSize = .zero) -> CGRect {
        let spot = SceneCanvas.wateringCanSpot(theme: theme)
        let u = spot.size * Double(size.width)
        let bx = spot.x * Double(size.width) + Double(layerShift.width)
        let by = spot.y * Double(size.height) + Double(layerShift.height)
        // From the back handle to past the rose, and from the top of the handle to the base.
        return CGRect(x: bx - 0.8 * u, y: by - 1.3 * u, width: 1.9 * u, height: 1.35 * u)
    }
}
