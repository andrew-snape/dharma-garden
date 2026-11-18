import SwiftUI
import DharmaGardenCore

/// Ground shadows for props and buildings, cast the way the plants' are: away from the sun (`SceneLighting`),
/// as long as the object's height times cot(elevation), up to the same cap. One place so no prop keeps its own
/// hard-coded offset.
extension SceneCanvas {
    /// A flat shadow for a free-standing prop. `foot` is the base centre, `height` its height in points, and
    /// `width` and `depth` the footprint ellipse's full size. A contact ellipse sits under it; the cast part is a
    /// tapering sweep of ellipses from the foot to the shadow of the top, filled as one shape so it does not stack.
    /// With no sun to go by, or at night, only the (faint) contact shadow is drawn.
    func propShadow(foot: CGPoint, height: CGFloat, width: CGFloat, depth: CGFloat, opacity: Double,
                    tint: Color = .black) {
        guard let sun = palette.sun, let d = SceneLighting.shadowDirection(for: sun) else {
            ellipse(foot, width, depth, tint.opacity(opacity * 0.6))
            return
        }
        let reach = height * CGFloat(SceneLighting.shadowLength(elevationDegrees: sun.elevationDegrees))
        let strength = opacity * (0.45 + 0.55 * SceneLighting.shadowOpacity(for: sun))
        ellipse(foot, width, depth, tint.opacity(strength * 0.7))
        var path = Path()
        // Enough ellipses that neighbours overlap, so the sweep reads as one smooth shape.
        let steps = min(80, max(8, Int(reach / max(1, depth * 0.25))))
        for k in 1...steps {
            let t = CGFloat(k) / CGFloat(steps)
            let c = CGPoint(x: foot.x + CGFloat(d.x) * reach * t, y: foot.y + CGFloat(d.y) * reach * t)
            let w = width * (1 - 0.6 * t), h = depth * (1 - 0.5 * t)
            path.addEllipse(in: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h))
        }
        ctx.fill(path, with: .color(tint.opacity(strength * 0.6)))
    }

    /// How far, in world units toward the viewer, the shadow of something `height` world units tall at the back of
    /// the yard reaches. The camera looks west, so only a sun with some west in it throws a wall's shadow forward;
    /// from the east the wall is lit and the answer is zero. Nil sun gives `fallback`.
    func wallShadowDepth(height: Double, fallback: Double) -> Double {
        guard let sun = palette.sun else { return fallback }
        guard sun.isUp, sun.intensity > 0 else { return 0 }
        let toward = SceneLighting.unitVector(bearing: sun.azimuthDegrees + 180)       // (east, north); east is toward the viewer
        return max(0, toward.x) * height * SceneLighting.shadowLength(elevationDegrees: sun.elevationDegrees)
    }

    /// 0...1 share of full strength for a wall-foot shadow: how much of the sun's light comes from behind the wall
    /// (the west), judged by how far toward the viewer its shadow falls. One when there is no sun to go by.
    func wallShadowShare() -> Double {
        guard let sun = palette.sun else { return 1 }
        guard sun.isUp, sun.intensity > 0 else { return 0 }
        return max(0, SceneLighting.unitVector(bearing: sun.azimuthDegrees + 180).x)
    }
}
