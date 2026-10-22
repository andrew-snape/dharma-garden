import Foundation
import WeedsCore

/// Turns the sun into flat, screen-space shadow values for the scene. Pure maths, no drawing.
public enum SceneLighting {
    /// Compass bearing the camera looks toward (270 = looking west). The view is the same camera as
    /// `Camera`, so the screen's right-hand side is bearing + 90 and nearer ground is bearing + 180.
    public static let cameraFacingAzimuth: Double = 270
    /// Longest shadow, in plant heights.
    public static let maxShadowLength: Double = 1.3
    /// Downward tilt of the camera in degrees, used to foreshorten depth on the ground.
    public static let cameraPitchDegrees: Double = 45
    /// Plant size relative to scene width at scale 1. Same value as `GardenSceneView.plantSize`.
    public static let plantSizeFraction: Double = 0.112

    /// Unit vector on screen (x right, y down) that shadows fall toward, for the 45-degree view.
    /// Shadows point away from the sun. Returns nil when the sun gives no direct light (night, or zero intensity).
    public static func shadowDirection(for sun: SunLight,
                                       cameraFacingAzimuth facing: Double = cameraFacingAzimuth,
                                       pitchDegrees: Double = cameraPitchDegrees) -> (x: Double, y: Double)? {
        guard sun.isUp, sun.intensity > 0 else { return nil }
        // Ground vector of the shadow as (east, north), from the opposite bearing.
        let ground = unitVector(bearing: sun.azimuthDegrees + 180)
        // Screen right and toward-the-viewer directions as ground vectors.
        let right = unitVector(bearing: facing + 90)
        let towardViewer = unitVector(bearing: facing + 180)
        let sx = dot(ground, right)
        let depth = dot(ground, towardViewer) * sin(pitchDegrees * .pi / 180)
        let length = hypot(sx, depth)
        guard length > 1e-9 else { return nil }
        return (x: sx / length, y: depth / length)
    }

    /// Shadow length in plant heights: cotangent of elevation (long when low), capped at `maxShadowLength`.
    /// Zero when the sun is at or below the horizon.
    public static func shadowLength(elevationDegrees elevation: Double) -> Double {
        guard elevation > 0 else { return 0 }
        return min(maxShadowLength, 1 / tan(elevation * .pi / 180))
    }

    /// Opacity of the soft shadow shapes, 0...1. Follows direct sun intensity, so it is faint under cloud and zero at night.
    public static func shadowOpacity(for sun: SunLight) -> Double {
        guard sun.isUp else { return 0 }
        return min(1, max(0, sun.intensity))
    }

    /// Share of full height a plant has reached, 0...1. Matches FlowerArt's growth curve (seed heads are full height).
    public static func plantGrowth(progress: Double, isSeedHead: Bool = false) -> Double {
        if isSeedHead { return 1 }
        let p = min(1, max(0, progress))
        return 1 - (1 - p) * (1 - p)
    }

    // MARK: Helpers

    /// Ground vector (east, north) for a compass bearing in degrees.
    static func unitVector(bearing: Double) -> (x: Double, y: Double) {
        let r = bearing * .pi / 180
        return (sin(r), cos(r))
    }

    static func dot(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> Double {
        a.x * b.x + a.y * b.y
    }
}
