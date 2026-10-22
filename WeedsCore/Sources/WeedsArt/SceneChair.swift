import SwiftUI
import WeedsCore

/// The reading chair: a wooden garden chair with a book on its seat, standing on the lawn beside the bed. Pressing it
/// opens the reading list (see `SceneContent.onSitInChair`). It is placed in world space and drawn with the drifted
/// camera, so it sits on the lawn with the patch; the hit test uses the same projection.
extension SceneCanvas {
    /// Where the chair stands: world x across the yard, world z toward the viewer. Clear of the bed and every
    /// theme's side props.
    static let chairX = -2.62
    static let chairZ = 1.0

    /// Size of the chair against the world: a little under life size, so it stays small beside the bed.
    static let chairScale = 0.8

    /// Chair height in world units (to the top of the backrest).
    private static let chairHeight = 1.05

    func drawChair() {
        let x = Self.chairX, z = Self.chairZ
        let s = screenPerUnit(x: x, y: 0, z: z) * CGFloat(Self.chairScale)
        func P(_ dx: Double, _ h: Double) -> CGPoint { upright(x + dx * Self.chairScale, h, z, scale: s) }
        let wood = Color(hex: 0xC99B66), woodShade = Color(hex: 0x9A6F45), woodLight = Color(hex: 0xDDB680)
        let cushion = Color(hex: 0x6FA8A0), cushionShade = Color(hex: 0x558C85)
        let base = at3(x, 0, z)
        ellipse(CGPoint(x: base.x + 0.08 * s, y: base.y), 1.1 * s, 0.26 * s, Color.black.opacity(0.15))
        let leg = max(2, 0.07 * s)
        // Back legs and the posts of the backrest.
        for dx in [-0.34, 0.34] { stroke([P(dx, 0), P(dx, 0.5)], width: leg, woodShade) }
        for dx in [-0.36, 0.36] { stroke([P(dx, 0.5), P(dx, Self.chairHeight)], width: leg, woodShade) }
        // Backrest: a panel of slats under a top rail.
        fill([P(-0.36, 0.62), P(0.36, 0.62), P(0.36, 0.96), P(-0.36, 0.96)], wood)
        for dx in [-0.18, 0.0, 0.18] { stroke([P(dx, 0.62), P(dx, 0.96)], width: max(1, 0.025 * s), woodShade) }
        fill([P(-0.4, 0.96), P(0.4, 0.96), P(0.4, Self.chairHeight), P(-0.4, Self.chairHeight)], woodLight)
        // Seat: the top face recedes upward on screen, then the front edge, then the legs in front of it.
        fill([P(-0.38, 0.54), P(0.38, 0.54), P(0.43, 0.42), P(-0.43, 0.42)], cushion)
        stroke([P(-0.38, 0.54), P(0.38, 0.54)], width: max(1, 0.02 * s), cushionShade)
        fill([P(-0.43, 0.36), P(0.43, 0.36), P(0.43, 0.42), P(-0.43, 0.42)], woodShade)
        for dx in [-0.38, 0.38] { stroke([P(dx, 0), P(dx, 0.37)], width: leg, wood) }
        // Armrests.
        for sign in [-1.0, 1.0] {
            fill([P(sign * 0.40, 0.66), P(sign * 0.50, 0.66), P(sign * 0.50, 0.7), P(sign * 0.40, 0.7)], woodLight)
            stroke([P(sign * 0.45, 0.42), P(sign * 0.45, 0.66)], width: max(1.5, 0.045 * s), wood)
        }
        // A small open book on the seat says what the chair is for.
        let cover = Color(hex: 0xB5654E), page = Color(hex: 0xF4EBD3)
        fill([P(-0.2, 0.47), P(0.2, 0.47), P(0.22, 0.52), P(-0.22, 0.52)], cover)
        fill([P(-0.18, 0.485), P(-0.01, 0.485), P(-0.01, 0.525), P(-0.19, 0.525)], page)
        fill([P(0.01, 0.485), P(0.18, 0.485), P(0.19, 0.525), P(0.01, 0.525)], page)
    }
}

extension SceneContent {
    /// The chair's footprint on screen, for a press: the chair is one world unit wide and about one tall at its feet.
    static func chairRect(size: CGSize, camera cam: Camera) -> CGRect {
        let foot = cam.upright(x: SceneCanvas.chairX, z: SceneCanvas.chairZ)
        let side = cam.project(x: SceneCanvas.chairX + 1, z: SceneCanvas.chairZ)
        let s = abs(side.x - foot.x) * Double(size.width) * SceneCanvas.chairScale
        let fx = foot.x * Double(size.width), fy = foot.y * Double(size.height)
        return CGRect(x: fx - 0.55 * s, y: fy - 1.1 * s, width: 1.1 * s, height: 1.15 * s)
    }

    /// True when a press at `location` lands on the chair.
    static func chairHit(at location: CGPoint, size: CGSize, camera cam: Camera) -> Bool {
        chairRect(size: size, camera: cam).contains(location)
    }
}
