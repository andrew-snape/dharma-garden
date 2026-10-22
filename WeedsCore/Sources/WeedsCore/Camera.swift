import Foundation

/// The one place the garden camera lives. Pure maths, no UI types.
///
/// World space: x runs across the garden, z runs toward the viewer, y is height above the lawn. The planting
/// patch is centred on the origin and `patchSide` world units wide. Screen space is normalised to 0...1 with y
/// pointing down.
///
/// `Camera()` is the first-person view (the default). `Camera.backyard` is the wider 3/4 view of the yard.
public struct Camera: Sendable {
    /// Downward tilt of the view in degrees. 45 is the first-person view.
    public var pitchDegrees: Double
    /// Eye height above the lawn, in world units.
    public var eyeHeight: Double
    /// Horizontal distance from the eye to the garden centre, in world units.
    public var distance: Double
    /// Vertical field of view in degrees.
    public var fieldOfViewDegrees: Double
    /// Scene width over height.
    public var aspect: Double
    /// Normalised screen position where the garden centre lands with no offsets.
    public var focus: (x: Double, y: Double)
    /// Drift: sideways (x) and vertical (y) displacement of the eye, in world units.
    public var offset: (x: Double, y: Double)
    /// Drift: extra pitch in degrees added to `pitchDegrees`. Zero for now.
    public var pitchOffsetDegrees: Double

    /// Defaults: eyeHeight + distance = 5.17 gives a back/front scale ratio of about 0.55 at 45 degrees.
    public init(pitchDegrees: Double = 45, eyeHeight: Double = 2.2, distance: Double = 2.97,
                fieldOfViewDegrees: Double = 76, aspect: Double = 4.0 / 3.0,
                focus: (x: Double, y: Double) = (0.5, 0.5),
                offset: (x: Double, y: Double) = (0, 0), pitchOffsetDegrees: Double = 0) {
        self.pitchDegrees = pitchDegrees
        self.eyeHeight = eyeHeight
        self.distance = distance
        self.fieldOfViewDegrees = fieldOfViewDegrees
        self.aspect = aspect
        self.focus = focus
        self.offset = offset
        self.pitchOffsetDegrees = pitchOffsetDegrees
    }

    /// The wider backyard view: pulled back and higher, about a third of the way down, so the whole yard
    /// (fence, back of the house, the patch and lawn in front) shows at once.
    public static let backyard = Camera(pitchDegrees: 34, eyeHeight: 3.0, distance: 4.0,
                                        fieldOfViewDegrees: 60, aspect: 4.0 / 3.0)

    /// Projects a world point (x across, z toward the viewer, height above the lawn) to normalised screen space.
    /// `scale` is 1 at the garden centre, larger near the viewer and smaller far away.
    public func project(x: Double, z: Double, height: Double = 0) -> (x: Double, y: Double, scale: Double) {
        screen(x: x, y: height, z: z)
    }

    /// Projects a world point the way upright things are drawn: screen x and the ground-level screen y come from
    /// the point's footprint (x, z), and `height` then rises straight up the screen at the scale of that depth
    /// (the same scale plants use), by the screen height of one world unit at the garden centre. Verticals stay
    /// vertical on screen, and every line parallel to z, at any height, runs to the lawn's vanishing point,
    /// because x, y and scale are all linear in each other along such a line. At height 0 it is `project`.
    public func upright(x: Double, z: Double, height: Double = 0) -> (x: Double, y: Double, scale: Double) {
        let g = screen(x: x, y: 0, z: z)
        return (g.x, g.y - height * risePerUnit * g.scale, g.scale)
    }

    /// The same for a point on the ground plane of the patch (`groundPoint`'s coordinates), lifted by `height`.
    public func uprightGroundPoint(x: Double, y: Double, height: Double = 0) -> (x: Double, y: Double, scale: Double) {
        let w = Camera.groundWorld(x: x, y: y)
        return upright(x: w.x, z: w.z, height: height)
    }

    /// The ground point under a normalised screen point on the plane `height` above the lawn, for things drawn with
    /// `upright`: the exact inverse of `uprightGroundPoint(x:y:height:)`. Nil when no depth in view matches.
    public func groundPoint(atScreen point: (x: Double, y: Double), uprightHeight height: Double) -> GroundPoint? {
        // Screen y at a depth is monotone in z (it is linear in the scale), so bisect z for the screen y.
        let t = radians(pitchDegrees + pitchOffsetDegrees)
        let zNear = distance + (eyeHeight + offset.y) * tan(t) - 1e-6   // depth reaches zero here
        func y(_ z: Double) -> Double { upright(x: 0, z: z, height: height).y }
        var lo = -200.0, hi = zNear
        guard y(lo) <= point.y, point.y <= y(hi) else { return nil }
        for _ in 0..<100 {
            let mid = (lo + hi) / 2
            if y(mid) < point.y { lo = mid } else { hi = mid }
        }
        let z = (lo + hi) / 2
        // Ground screen x is focus + k * (x - eyeX) / depth / aspect; solve it for x.
        let r = cameraSpace(x: 0, y: 0, z: z, pitch: pitchDegrees + pitchOffsetDegrees,
                            eyeX: offset.x, eyeY: eyeHeight + offset.y)
        let wx = offset.x + (point.x - focus.x) * aspect * r.depth / focal
        return GroundPoint(x: wx / Camera.patchSide + 0.5, y: z / Camera.patchSide + 0.5)
    }

    /// Normalised screen y of the horizon for the current pitch (for lining up backdrops).
    /// With the default pitch this is above the top of the frame.
    public var horizonY: Double {
        let k = focal
        let refUp = reference.up
        return focus.y - k * (tan(radians(pitchDegrees + pitchOffsetDegrees)) - refUp)
    }

    // MARK: Ground plane of the planting patch

    /// Side of the planting patch in world units. The unit ground square is this wide. Larger than the old 4-unit grid
    /// (4.0) so the soil patch shows about 35 percent bigger on screen.
    public static let patchSide = 5.4

    /// World (x, z) of a ground point. The patch is centred on the garden centre.
    public static func groundWorld(x: Double, y: Double) -> (x: Double, z: Double) {
        ((x - 0.5) * patchSide, (y - 0.5) * patchSide)
    }

    /// Projects a point on the ground plane of the patch to normalised screen space. `x` runs 0...1 across and
    /// `y` runs 0...1 back to front (see `GroundPoint`). Values outside 0...1 land on the lawn beyond the patch.
    /// `height` lifts the point above the ground, in world units. Returns the same scale as `project`.
    public func groundPoint(x: Double, y: Double, height: Double = 0) -> (x: Double, y: Double, scale: Double) {
        let w = Camera.groundWorld(x: x, y: y)
        return screen(x: w.x, y: height, z: w.z)
    }

    /// Plant scale (1 at the garden centre, larger toward the viewer) at ground depth `y`. Uses this camera,
    /// so drift and pitch are included.
    public func scale(atGroundY y: Double) -> Double {
        screen(x: 0, y: 0, z: Camera.groundWorld(x: 0.5, y: y).z).scale
    }

    /// The ground point under a normalised screen point, or nil when the view ray misses the ground (it points
    /// at or above the horizon). This is the exact inverse of `groundPoint(x:y:height:)` for the same camera, so taps
    /// land where the drawing is. `height` picks the plane the ground point lies on (the soil of a raised bed, say).
    /// The result may fall outside 0...1 (the lawn); the caller checks the plot.
    public func groundPoint(atScreen point: (x: Double, y: Double), height: Double = 0) -> GroundPoint? {
        let k = focal
        let ref = reference
        // Camera-space ratios that `screen` maps from: r.x / r.depth and r.up / r.depth.
        let a = (point.x - focus.x) * aspect / k
        let b = ref.up + (focus.y - point.y) / k
        // Invert the view rotation for a direction with depth 1, so (a, b, 1) is the ray in camera space.
        let t = radians(pitchDegrees + pitchOffsetDegrees)
        let s = sin(t), c = cos(t)
        let dx = a, dy = c * b - s, dz = -s * b - c
        guard dy < -1e-12 else { return nil }
        let eyeY = eyeHeight + offset.y - height
        let lambda = -eyeY / dy
        guard lambda > 0 else { return nil }
        let wx = offset.x + lambda * dx
        let wz = distance + lambda * dz
        return GroundPoint(x: wx / Camera.patchSide + 0.5, y: wz / Camera.patchSide + 0.5)
    }

    // MARK: Internals

    /// Screen units per tan of half the field of view. Vertical half-extent maps to 0.5.
    private var focal: Double { 0.5 / tan(radians(fieldOfViewDegrees) / 2) }

    /// Screen y rise of one world unit of height at the garden centre (scale 1), measured from the camera.
    private var risePerUnit: Double {
        let e = 0.01
        return (screen(x: 0, y: 0, z: 0).y - screen(x: 0, y: e, z: 0).y) / e
    }

    private func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

    /// Camera-space coordinates of the reference point (garden centre with no offsets).
    private var reference: (x: Double, up: Double, depth: Double) {
        let r = cameraSpace(x: 0, y: 0, z: 0, pitch: pitchDegrees, eyeX: 0, eyeY: eyeHeight)
        return (r.x, r.up / r.depth, r.depth)
    }

    private func screen(x: Double, y: Double, z: Double) -> (x: Double, y: Double, scale: Double) {
        let r = cameraSpace(x: x, y: y, z: z, pitch: pitchDegrees + pitchOffsetDegrees,
                            eyeX: offset.x, eyeY: eyeHeight + offset.y)
        let ref = reference
        let k = focal
        let sx = focus.x + k * (r.x / r.depth) / aspect
        let sy = focus.y - k * (r.up / r.depth - ref.up)
        return (sx, sy, ref.depth / r.depth)
    }

    /// Camera-space coordinates: x across, `up` the vertical axis tilted by the pitch, and `depth` along the view.
    /// The eye sits at (eyeX, eyeY, distance) and looks along (0, -sin, -cos).
    private func cameraSpace(x: Double, y: Double, z: Double, pitch: Double,
                             eyeX: Double, eyeY: Double) -> (x: Double, up: Double, depth: Double) {
        let t = radians(pitch)
        let s = sin(t), c = cos(t)
        let vx = x - eyeX, vy = y - eyeY, vz = z - distance
        let depth = -vy * s - vz * c
        let up = vy * c - vz * s
        return (vx, up, depth)
    }

    private static func contains(_ p: (x: Double, y: Double), in quad: [(x: Double, y: Double)]) -> Bool {
        var positive = false, negative = false
        for i in quad.indices {
            let a = quad[i], b = quad[(i + 1) % quad.count]
            let cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
            if cross > 0 { positive = true } else if cross < 0 { negative = true }
            if positive && negative { return false }
        }
        return true
    }

    private static func centroid(_ quad: [(x: Double, y: Double)]) -> (x: Double, y: Double) {
        let n = Double(quad.count)
        return (quad.reduce(0) { $0 + $1.x } / n, quad.reduce(0) { $0 + $1.y } / n)
    }

    private static func scaled(_ quad: [(x: Double, y: Double)], by f: Double) -> [(x: Double, y: Double)] {
        let c = centroid(quad)
        return quad.map { (x: c.x + ($0.x - c.x) * f, y: c.y + ($0.y - c.y) * f) }
    }
}
