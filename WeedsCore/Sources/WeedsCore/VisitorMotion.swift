import Foundation

/// Where a visitor is at one moment, and how it should look: the output of `VisitorMotion.pose`.
public struct VisitorPose: Equatable, Sendable {
    /// The ground point the visitor is over.
    public var position: GroundPoint
    /// Height above the lawn in world units (the same units as `Camera.groundPoint(height:)`). Zero on the ground.
    public var height: Double
    /// -1 faces left, 1 faces right.
    public var facing: Double
    /// Seconds, for the wing and leg animation. Each visitor has its own offset.
    public var phase: Double
    /// True while the visitor is travelling (arriving, leaving, hopping, crawling). False while it sits, hovers or pecks.
    public var isMoving: Bool
    /// 0...1. Fades in on arrival and out on leaving.
    public var opacity: Double

    public init(position: GroundPoint, height: Double = 0, facing: Double = 1, phase: Double = 0,
                isMoving: Bool = false, opacity: Double = 1) {
        self.position = position
        self.height = height
        self.facing = facing
        self.phase = phase
        self.isMoving = isMoving
        self.opacity = opacity
    }

    /// A visitor sitting in the middle of the patch, facing right and fully visible. Used by the collection book.
    public static let resting = VisitorPose(position: GroundPoint(x: 0.5, y: 0.5))
}

/// How a visitor moves over the patch: a path in from one lawn edge, a stay at its perch, and a path out to another
/// edge. Pure and deterministic from `Visitor.id` and the time, so any frame can be drawn or tested.
public enum VisitorMotion {
    /// Share of the lifetime spent arriving, and the same share spent leaving. The rest is the stay.
    public static let transitShare = 0.15

    /// Insects that hover over the patch at a steady height.
    public static func hovers(_ species: VisitorSpecies) -> Bool {
        switch species {
        case .bee, .cabbageWhiteButterfly, .orangeButterfly, .dragonfly, .moth: true
        default: false
        }
    }

    /// Birds that fly in and out, and lift off the lawn when they move.
    public static func isBird(_ species: VisitorSpecies) -> Bool {
        switch species {
        case .magpieLark, .willieWagtail, .cockatoo: true
        default: false
        }
    }

    public static func pose(of v: Visitor, at now: Date) -> VisitorPose {
        let key = UInt64(bitPattern: Int64(v.id))
        let t = now.timeIntervalSince(v.spawnedAt)
        let u = clamp01(t / max(v.lifetime, 1))
        let fade = transitShare

        let perch = clamped(v.position)
        let entrySide = Int(unit(key, 1) * 4)
        let exitSide = (entrySide + 1 + Int(unit(key, 3) * 3)) % 4
        let entry = edgePoint(side: entrySide, along: unit(key, 2))
        let exit = edgePoint(side: exitSide, along: unit(key, 4))

        let inProgress = clamp01(u / fade)
        let outProgress = clamp01((u - (1 - fade)) / fade)
        let opacity = smoothStep(inProgress) * smoothStep(1 - outProgress)

        let position: GroundPoint
        let height: Double
        let moving: Bool
        let heading: Double
        if u < fade {
            // Arriving: from the lawn edge onto the perch, quick at first and slowing down.
            let k = 1 - (1 - inProgress) * (1 - inProgress)
            position = lerp(entry, perch, k)
            height = transitHeight(v.species, progress: inProgress, key: key, t: t)
            moving = true
            heading = perch.x - entry.x
        } else if u > 1 - fade {
            // Leaving: from wherever the stay ended, out to the far edge, slowly at first.
            let stayEnd = stay(v.species, perch: perch, key: key, s: 1)
            position = lerp(stayEnd.position, exit, outProgress * outProgress)
            height = transitHeight(v.species, progress: outProgress, key: key, t: t)
            moving = true
            heading = exit.x - stayEnd.position.x
        } else {
            let s = clamp01((u - fade) / (1 - 2 * fade))
            let st = stay(v.species, perch: perch, key: key, s: s)
            position = st.position
            height = stayHeight(v.species, stay: st, key: key, t: t)
            moving = st.moving
            heading = st.dx ?? (perch.x - entry.x)
        }

        return VisitorPose(position: clamped(position), height: height, facing: heading < 0 ? -1 : 1,
                           phase: t + 10 * unit(key, 8), isMoving: moving, opacity: opacity)
    }

    // MARK: The stay

    /// What a visitor does while it sits at its perch.
    private struct Stay {
        var position: GroundPoint
        var moving = false
        /// Horizontal direction of the current movement, when there is one.
        var dx: Double?
        /// Progress through a hop between two spots (0...1), when a flyer is hopping.
        var hop: Double?
    }

    /// The visitor's place during its stay, at stay progress `s` (0...1).
    private static func stay(_ species: VisitorSpecies, perch: GroundPoint, key: UInt64, s: Double) -> Stay {
        let angle = 2 * Double.pi * unit(key, 6)
        switch species {
        case .bee, .cabbageWhiteButterfly, .orangeButterfly:
            // Sit on the perch, then hop to a second spot close by in the middle of the stay.
            let r = 0.025 + 0.015 * unit(key, 7)
            let spot = clamped(GroundPoint(x: perch.x + cos(angle) * r, y: perch.y + sin(angle) * r))
            let h = clamp01((s - 0.35) / 0.1)
            let moving = h > 0 && h < 1
            return Stay(position: lerp(perch, spot, smoothStep(h)), moving: moving,
                        dx: h > 0 ? spot.x - perch.x : nil, hop: moving ? h : nil)
        case .dragonfly:
            // Darts back and forth over the same spot.
            let theta = 2 * Double.pi * 1.2 * s
            let offset = GroundPoint(x: perch.x + 0.02 * sin(theta), y: perch.y)
            return Stay(position: clamped(offset), moving: true, dx: cos(theta))
        case .snail:
            // A very slow crawl in one direction for the whole stay.
            let dir = (x: cos(angle), y: sin(angle))
            let p = GroundPoint(x: perch.x + dir.x * 0.03 * s, y: perch.y + dir.y * 0.03 * s)
            return Stay(position: clamped(p), moving: true, dx: dir.x)
        case .ladybird:
            // Walks a short way forward and back.
            let dir = (x: cos(angle), y: sin(angle))
            let along = sin(2 * Double.pi * s)
            let p = GroundPoint(x: perch.x + dir.x * 0.025 * along, y: perch.y + dir.y * 0.025 * along)
            return Stay(position: clamped(p), moving: true, dx: dir.x * cos(2 * Double.pi * s))
        case .moth, .magpieLark, .willieWagtail, .cockatoo, .blueTongueLizard, .frog:
            // Hovering over a bloom, pecking on the lawn, or sitting still in the sun.
            return Stay(position: perch)
        }
    }

    // MARK: Height

    /// Height of a flyer's hover: a steady height with a slow bob. Always above zero.
    private static func hoverHeight(_ species: VisitorSpecies, key: UInt64, t: Double) -> Double {
        let base: Double
        switch species {
        case .bee: base = 0.13
        case .cabbageWhiteButterfly: base = 0.11
        case .orangeButterfly: base = 0.12
        case .dragonfly: base = 0.16
        default: base = 0.10
        }
        let period = 0.9 + 0.4 * unit(key, 5)
        return base + 0.012 * sin(2 * Double.pi * t / period + 2 * Double.pi * unit(key, 9))
    }

    /// Height while arriving or leaving. Flyers keep their hover height; birds lift off and come down in an arc.
    private static func transitHeight(_ species: VisitorSpecies, progress p: Double, key: UInt64, t: Double) -> Double {
        if hovers(species) { return hoverHeight(species, key: key, t: t) }
        if isBird(species) {
            let lift = species == .cockatoo ? 0.07 : 0.04
            let arc = species == .cockatoo ? 0.1 : 0.07
            return lift + arc * sin(Double.pi * p)
        }
        return 0
    }

    /// Height during the stay. Hovering insects rise a little when they hop; everything else stays on the ground.
    private static func stayHeight(_ species: VisitorSpecies, stay: Stay, key: UInt64, t: Double) -> Double {
        guard hovers(species) else { return 0 }
        let arc = stay.hop.map { 0.05 * sin(Double.pi * $0) } ?? 0
        return hoverHeight(species, key: key, t: t) + arc
    }

    // MARK: Helpers

    /// A point on one edge of the unit square (the lawn around the patch), `along` 0...1 from its start.
    static func edgePoint(side: Int, along: Double) -> GroundPoint {
        let t = 0.03 + 0.94 * along
        switch side {
        case 0: return GroundPoint(x: t, y: 0)
        case 1: return GroundPoint(x: 1, y: t)
        case 2: return GroundPoint(x: t, y: 1)
        default: return GroundPoint(x: 0, y: t)
        }
    }

    private static func lerp(_ a: GroundPoint, _ b: GroundPoint, _ k: Double) -> GroundPoint {
        GroundPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
    }

    /// Keeps a point on the patch's square, 0...1 on both axes.
    private static func clamped(_ p: GroundPoint) -> GroundPoint {
        GroundPoint(x: clamp01(p.x), y: clamp01(p.y))
    }

    private static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }

    private static func smoothStep(_ x: Double) -> Double {
        let k = clamp01(x)
        return k * k * (3 - 2 * k)
    }

    /// A deterministic value in 0..<1 from a visitor's key and a salt.
    private static func unit(_ key: UInt64, _ salt: UInt64) -> Double {
        DeterministicHash.unitFromBits(DeterministicHash.mix(key &+ salt &* 0x9E37_79B9_7F4A_7C15))
    }
}
