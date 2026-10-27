import SwiftUI
import DharmaGardenCore

/// The sundial: a stone plinth with a round bronze dial, hour ticks and a triangular gnomon, standing on the lawn on
/// the right of the bed (the chair is on the left). Its shadow falls the way the sun's does, so it points at the
/// solar time the scene's sun implies. Like the chair it is placed in world space and drawn with the drifted camera,
/// so plants and visitors in front of it cover it.
///
/// It is a horizontal dial. The gnomon is a right triangle whose sloping edge (the style) points at the celestial
/// pole, so it rises toward true south in the southern hemisphere (true north in the northern) at the latitude's
/// angle. Its shadow is the real shadow of the real sun (see `SceneLighting`), and the edge of it lies on the hour
/// line for the true local apparent solar time (from the sun's hour angle, not its bearing):
/// tan(angle from the noon line) = sin(latitude) * tan(hour angle). Hours run anticlockwise in the south.
extension SceneCanvas {
    /// Where the sundial stands: world x across the yard, world z toward the viewer. On open lawn, clear of the bed,
    /// the chair and every theme's side props.
    static let sundialX = 2.72
    static let sundialZ = 0.75

    /// Dial radius and plinth height, in world units.
    private static let dialRadius = 0.3
    private static let plinthHeight = 0.5

    /// Latitude the dial is cut for when the sun does not say (the garden's default, Geelong).
    static let sundialDefaultLatitude = -38.2

    /// Horizontal run of the style from the dial centre, in world units (it points to the pole's side).
    static let sundialStylePlan = 0.24

    /// True when the sun sweeps through the south (northern hemisphere), judged from its bearing: used only for a
    /// hand-made sun that carries no latitude.
    static func sunCrossesSouth(azimuth a: Double) -> Bool {
        let b = (a.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return b >= 90 && b <= 270
    }

    /// Compass bearing of the hour line for an hour angle (degrees, 0 at noon, negative in the morning) on a dial cut
    /// for `latitude`: the direction, from the dial centre, the style's shadow points at that hour.
    static func sundialHourBearing(hourAngle: Double, latitude: Double) -> Double {
        let h = hourAngle * .pi / 180
        let beta = atan2(sin(abs(latitude) * .pi / 180) * sin(-h), cos(h)) * 180 / .pi
        return latitude < 0 ? 180 + beta : 360 - beta
    }

    /// The shadow of the gnomon's apex on the dial plane, as (north, east) ground offsets from the dial centre in
    /// world units, for this sun. The shadow of the style runs from the centre to this point.
    static func sundialShadowTip(for sun: SunLight) -> (north: Double, east: Double) {
        let lat = sun.latitudeDegrees ?? sundialDefaultLatitude
        let a = sundialStylePlan, h = a * tan(abs(lat) * .pi / 180)
        let styleBearing = lat < 0 ? 180.0 : 0.0
        let s = SceneLighting.unitVector(bearing: styleBearing)                  // (east, north)
        let reach = h / max(0.02, tan(sun.elevationDegrees * .pi / 180))        // cot(elevation) times the height
        let v = SceneLighting.unitVector(bearing: sun.azimuthDegrees + 180)
        return (a * s.y + reach * v.y, a * s.x + reach * v.x)
    }

    /// Local apparent solar time in hours (0..<24) the sun implies, or nil when the sun is not up (no shadow, no
    /// reading). Uses the sun's hour angle; a hand-made sun without one is read from its bearing, 15 degrees an hour.
    public static func sundialSolarHour(for sun: SunLight?) -> Double? {
        guard let sun, sun.isUp else { return nil }
        if let hour = sun.solarHour { return hour }
        let b = (sun.azimuthDegrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let swept = sunCrossesSouth(azimuth: b) ? b - 90 : (b > 270 ? 90 - (b - 360) : 90 - b)
        return min(18, max(6, 6 + swept / 15))
    }

    /// The reading as text for a tooltip, such as "Sundial: 10:42 am (solar time)", or a line saying it is idle.
    public static func sundialReading(for sun: SunLight?) -> String {
        guard let hour = sundialSolarHour(for: sun) else { return "Sundial: no shadow without the sun" }
        let minutes = Int((hour * 60).rounded())
        let h24 = (minutes / 60) % 24, m = minutes % 60
        let h12 = h24 % 12 == 0 ? 12 : h24 % 12
        return "Sundial: \(h12):\(String(format: "%02d", m)) \(h24 < 12 ? "am" : "pm") (solar time)"
    }

    func drawSundial() {
        let x = Self.sundialX, z = Self.sundialZ
        let R = Self.dialRadius, plinth = Self.plinthHeight
        let s = screenPerUnit(x: x, y: 0, z: z)
        let ry = abs(at3(x, 0, z + 1).y - at3(x, 0, z - 1).y) / 2     // screen depth of one world unit on the ground
        func U(_ dx: Double, _ h: Double) -> CGPoint { upright(x + dx, h, z, scale: s) }
        let stone = Color(hex: 0xB9B3A6), stoneLight = Color(hex: 0xD2CDC0), stoneShade = Color(hex: 0x8F897C)
        let bronze = Color(hex: 0xB8914E), bronzeShade = Color(hex: 0x8A6A33), bronzeLight = Color(hex: 0xD6B672)
        let ink = Color(hex: 0x4A3818)

        // Shadow on the grass, then a stepped footing and the column.
        let base = at3(x, 0, z)
        propShadow(foot: base, height: CGFloat(plinth + 0.2) * s, width: 0.55 * s, depth: ry * 0.4, opacity: 0.2)
        fill([U(-0.24, 0), U(0.24, 0), U(0.24, 0.07), U(-0.24, 0.07)], stoneShade)
        ellipse(CGPoint(x: base.x, y: base.y - 0.07 * s), 0.48 * s, ry * 0.24, stoneLight)
        fill([U(-0.15, 0.07), U(0.15, 0.07), U(0.12, plinth - 0.06), U(-0.12, plinth - 0.06)], stone)
        fill([U(0.04, 0.07), U(0.15, 0.07), U(0.12, plinth - 0.06), U(0.04, plinth - 0.06)], stoneShade.opacity(0.55))
        stroke([U(-0.17, plinth - 0.05), U(0.17, plinth - 0.05)], width: max(1, 0.05 * s), stoneLight)

        // The dial plate: an ellipse on top of the column with a bronze rim, thickness and an inner ring.
        let top = U(0, plinth)
        let rx = CGFloat(R) * s, rim = CGFloat(R) * ry
        let thick = 0.05 * s
        ellipse(CGPoint(x: top.x, y: top.y + thick), rx * 2, rim * 2, bronzeShade)
        ellipse(top, rx * 2, rim * 2, bronzeLight)
        ellipse(top, rx * 1.9, rim * 1.9, bronze)
        let ring = Path(ellipseIn: CGRect(x: top.x - rx * 0.72, y: top.y - rim * 0.72, width: rx * 1.44, height: rim * 1.44))
        ctx.stroke(ring, with: .color(ink.opacity(0.45)), lineWidth: max(0.8, 0.012 * s))

        // A dial point: ground offset (world x, world z) in units of the radius, on the plate.
        func D(_ wx: Double, _ wz: Double, _ k: Double = 1) -> CGPoint {
            CGPoint(x: top.x + CGFloat(wx * k) * rx, y: top.y + CGFloat(wz * k) * rim)
        }
        let sun = palette.sun
        let lat = sun?.latitudeDegrees ?? Self.sundialDefaultLatitude
        // Hour ticks from 6 to 18, laid along the style's shadow at that solar hour (hour angle 15 per hour).
        for hour in 6...18 {
            let bearing = Self.sundialHourBearing(hourAngle: 15 * Double(hour - 12), latitude: lat)
            let v = SceneLighting.unitVector(bearing: bearing)       // (east, north); world x is north, world z is east
            let long = hour % 3 == 0
            stroke([D(v.y, v.x, long ? 0.74 : 0.8), D(v.y, v.x, 0.93)], width: max(1, (long ? 0.03 : 0.018) * s), ink.opacity(0.85))
        }
        ellipse(top, 0.06 * s, 0.06 * ry, ink.opacity(0.7))

        // The gnomon is a vertical triangle: its foot at the centre, its upright edge a style-length toward the pole.
        let plan = Self.sundialStylePlan, rise = plan * tan(abs(lat) * .pi / 180)
        let toPole = lat < 0 ? -1.0 : 1.0                            // world x is north
        // Its shadow: the triangle from the centre, along the ground to the foot of the upright edge, to the shadow of
        // its apex, clipped to the plate. Zero at night and faint under cloud, because it follows direct intensity.
        if let sun, sun.isUp, sun.intensity > 0 {
            var tip = Self.sundialShadowTip(for: sun)
            let reach = hypot(tip.north, tip.east)
            if reach > 3 * R { tip = (tip.north * 3 * R / reach, tip.east * 3 * R / reach) }
            let saved = ctx
            ctx.clip(to: Path(ellipseIn: CGRect(x: top.x - rx, y: top.y - rim, width: rx * 2, height: rim * 2)))
            fill([D(0, 0), D(toPole * plan / R, 0), D(tip.north / R, tip.east / R)],
                 Color.black.opacity(0.5 * SceneLighting.shadowOpacity(for: sun)))
            ctx = saved
        }
        let foot = U(0, plinth + 0.012)
        let uprightFoot = U(toPole * plan, plinth + 0.012)
        let apex = U(toPole * plan, plinth + 0.012 + rise)
        fill([foot, uprightFoot, apex], bronzeShade)
        stroke([foot, apex], width: max(1, 0.025 * s), bronzeLight)
    }
}

extension SceneContent {
    /// The sundial's footprint on screen (scene points) for a camera, for a hover or press, like `chairRect`.
    static func sundialRect(size: CGSize, camera cam: Camera) -> CGRect {
        let foot = cam.upright(x: SceneCanvas.sundialX, z: SceneCanvas.sundialZ)
        let side = cam.project(x: SceneCanvas.sundialX + 1, z: SceneCanvas.sundialZ)
        let s = abs(side.x - foot.x) * Double(size.width)
        let fx = foot.x * Double(size.width), fy = foot.y * Double(size.height)
        return CGRect(x: fx - 0.42 * s, y: fy - 0.98 * s, width: 0.84 * s, height: 1.03 * s)
    }

    /// True when a point lands on the sundial.
    static func sundialHit(at location: CGPoint, size: CGSize, camera cam: Camera) -> Bool {
        sundialRect(size: size, camera: cam).contains(location)
    }
}
