import Foundation

/// A point on the ground plane of the patch. Both axes run 0...1: x from left to right, y from back to front.
public struct GroundPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func distance(to other: GroundPoint) -> Double {
        let dx = x - other.x, dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// The look of the garden bed. The style decides where plants may stand; everything else about the garden is the same.
public enum BedStyle: String, CaseIterable, Codable, Sendable {
    case soilPatch, mounds, grid, plantersBoxes

    public var displayName: String {
        switch self {
        case .soilPatch: "Soil patch"
        case .mounds: "Soil mounds"
        case .grid: "Grid layout"
        case .plantersBoxes: "Raised wooden planter boxes"
        }
    }

    public var blurb: String {
        switch self {
        case .soilPatch: "One natural patch of tilled soil."
        case .mounds: "Soft mounds of earth with lawn between them."
        case .grid: "A tidy rectangular bed, planted freely."
        case .plantersBoxes: "Timber boxes raised above the lawn."
        }
    }
}

/// One piece of plantable ground, in ground units. `edgeDistance` is signed (positive inside), so the same
/// inset rules work for every shape.
public struct BedRegion: Equatable, Sendable {
    public enum Shape: Equatable, Sendable {
        /// The soft-edged oval of the soil patch (the edge wobbles slightly, see `edgeRadius`).
        case wobblyOval
        case ellipse
        /// A rectangle whose corners are rounded by `cornerRadius` (0 for a sharp rectangle).
        case roundedRect
        /// An irregular soil heap: an ellipse whose edge is bent by harmonics chosen from `wobbleSeed`.
        case mound
    }

    public var shape: Shape
    public var centre: GroundPoint
    /// Half the width and half the height of the region's bounding box.
    public var halfWidth: Double
    public var halfHeight: Double
    /// Corner radius for `.roundedRect`. Ignored by the other shapes.
    public var cornerRadius: Double
    /// Seed for the edge bend of a `.mound`, so each heap has its own outline. Ignored by the other shapes.
    public var wobbleSeed: UInt64

    public init(shape: Shape, centre: GroundPoint, halfWidth: Double, halfHeight: Double, cornerRadius: Double = 0,
                wobbleSeed: UInt64 = 0) {
        self.shape = shape
        self.centre = centre
        self.halfWidth = halfWidth
        self.halfHeight = halfHeight
        self.cornerRadius = cornerRadius
        self.wobbleSeed = wobbleSeed
    }

    /// Area in ground units. The wobbly shapes use their average area, since the wobble averages out.
    public var area: Double {
        switch shape {
        case .wobblyOval, .ellipse, .mound: Double.pi * halfWidth * halfHeight
        case .roundedRect: 4 * halfWidth * halfHeight - (4 - Double.pi) * cornerRadius * cornerRadius
        }
    }

    /// Signed distance from the edge in ground units: positive inside, negative outside.
    public func edgeDistance(_ p: GroundPoint) -> Double {
        switch shape {
        case .wobblyOval:
            let u = (p.x - centre.x) / halfWidth, v = (p.y - centre.y) / halfHeight
            let q = (u * u + v * v).squareRoot()
            return (BedRegion.edgeRadius(atan2(v, u)) - q) * min(halfWidth, halfHeight)
        case .mound:
            let u = (p.x - centre.x) / halfWidth, v = (p.y - centre.y) / halfHeight
            let q = (u * u + v * v).squareRoot()
            return (BedRegion.moundRadius(atan2(v, u), seed: wobbleSeed) - q) * min(halfWidth, halfHeight)
        case .ellipse:
            let u = (p.x - centre.x) / halfWidth, v = (p.y - centre.y) / halfHeight
            let q = (u * u + v * v).squareRoot()
            return (1 - q) * min(halfWidth, halfHeight)
        case .roundedRect:
            let qx = abs(p.x - centre.x) - (halfWidth - cornerRadius)
            let qy = abs(p.y - centre.y) - (halfHeight - cornerRadius)
            let outside = (max(qx, 0) * max(qx, 0) + max(qy, 0) * max(qy, 0)).squareRoot()
            return cornerRadius - outside - min(max(qx, qy), 0)
        }
    }

    /// Edge radius, in normalised units (1 for a plain ellipse), in direction `theta`.
    private static func edgeRadius(_ theta: Double) -> Double {
        1 + 0.025 * cos(2 * theta + 0.7) + 0.018 * cos(3 * theta + 2.1) + 0.01 * cos(5 * theta + 4.0)
    }

    /// Edge radius of a mound in direction `theta`, in normalised units. Three harmonics with amplitudes and phases
    /// drawn from `seed`: a broad lean (2nd), a lumpy shoulder (3rd) and a fine bump (5th). Stays within about 0.9...1.1.
    static func moundRadius(_ theta: Double, seed: UInt64) -> Double {
        func unit(_ k: Int) -> Double { DeterministicHash.unitFromBits(DeterministicHash.seed(Int(seed), k)) }
        let a2 = 0.03 + 0.03 * unit(1), p2 = 2 * Double.pi * unit(2)
        let a3 = 0.015 + 0.02 * unit(3), p3 = 2 * Double.pi * unit(4)
        let a5 = 0.006 + 0.01 * unit(5), p5 = 2 * Double.pi * unit(6)
        return 1 + a2 * cos(2 * theta + p2) + a3 * cos(3 * theta + p3) + a5 * cos(5 * theta + p5)
    }
}

/// The garden bed. Its `style` decides the plantable regions (see `regions`). `centre`, `rx` and `ry` shape the
/// soil patch only; the other styles have fixed regions in the unit square. Everything here is deterministic.
public struct PlotShape: Codable, Equatable, Sendable {
    /// Thickness of a planter box's timber, in ground units. A box's plantable ground is its outer frame inset by this.
    public static let plankThickness = 0.025

    /// Corner radius of a planter box's plantable ground, in ground units. It keeps seeds and plants out of the
    /// corners, where the posts stand (the drawn soil keeps square corners).
    public static let planterCornerRadius = 0.09

    public var centre: GroundPoint
    public var rx: Double
    public var ry: Double
    public var style: BedStyle

    public init(centre: GroundPoint = GroundPoint(x: 0.5, y: 0.5), rx: Double = 0.46, ry: Double = 0.42,
                style: BedStyle = .soilPatch) {
        self.centre = centre
        self.rx = rx
        self.ry = ry
        self.style = style
    }

    private enum CodingKeys: String, CodingKey { case centre, rx, ry, style }

    /// Saves from before bed styles have no `style` key, so they load as the soil patch (no save version bump).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        centre = try c.decode(GroundPoint.self, forKey: .centre)
        rx = try c.decode(Double.self, forKey: .rx)
        ry = try c.decode(Double.self, forKey: .ry)
        style = try c.decodeIfPresent(BedStyle.self, forKey: .style) ?? .soilPatch
    }

    /// The plantable regions for the current style. Plants and weeds stand inside one of them.
    public var regions: [BedRegion] {
        switch style {
        case .soilPatch:
            [BedRegion(shape: .wobblyOval, centre: centre, halfWidth: rx, halfHeight: ry)]
        case .mounds:
            // Four heaps of different sizes and shapes, placed off-centre with lawn between (every gap is at least
            // 0.08). Two sit at the back, two in the middle, and the front stays clear for the watering can.
            [PlotShape.mound(0.20, 0.20, 0.28, 0.22, seed: 11), PlotShape.mound(0.84, 0.13, 0.24, 0.20, seed: 23),
             PlotShape.mound(0.33, 0.64, 0.16, 0.14, seed: 37), PlotShape.mound(0.73, 0.57, 0.16, 0.14, seed: 53)]
        case .grid:
            [BedRegion(shape: .roundedRect, centre: GroundPoint(x: 0.5, y: 0.5),
                       halfWidth: 0.42, halfHeight: 0.31, cornerRadius: 0.07)]
        case .plantersBoxes:
            // Three boxes, outer frames (x0, y0, x1, y1): two at the back, one in front and to the left, so the front
            // right of the lawn stays clear for the watering can. Every gap between frames is at least 0.08 both ways.
            // Each frame, walls included, stays inside the view with a margin of 0.05 (checked in BedStyleTests).
            [PlotShape.planterInside(-0.04, -0.06, 0.44, 0.38), PlotShape.planterInside(0.52, -0.06, 1.0, 0.38),
             PlotShape.planterInside(0.21, 0.52, 0.70, 0.90)]
        }
    }

    /// A soil mound centred at (x, y), with half-extents `hw` and `hh`, and an edge shaped from `seed`.
    private static func mound(_ x: Double, _ y: Double, _ hw: Double, _ hh: Double, seed: UInt64) -> BedRegion {
        BedRegion(shape: .mound, centre: GroundPoint(x: x, y: y), halfWidth: hw, halfHeight: hh, wobbleSeed: seed)
    }

    /// The plantable inside of a planter box whose outer frame runs from (x0, y0) to (x1, y1).
    private static func planterInside(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> BedRegion {
        BedRegion(shape: .roundedRect,
                  centre: GroundPoint(x: (x0 + x1) / 2, y: (y0 + y1) / 2),
                  halfWidth: (x1 - x0) / 2 - plankThickness,
                  halfHeight: (y1 - y0) / 2 - plankThickness,
                  cornerRadius: planterCornerRadius)
    }

    /// Plantable area in ground units: the sum of the regions. For the soil patch this is the old oval's area.
    public var area: Double { regions.reduce(0) { $0 + $1.area } }

    /// Signed distance from the nearest plantable edge in ground units: positive inside, negative outside.
    public func edgeDistance(_ p: GroundPoint) -> Double {
        regions.reduce(-Double.infinity) { max($0, $1.edgeDistance(p)) }
    }

    /// True when the point is inside the plot and at least `inset` ground units from its edge.
    public func contains(_ p: GroundPoint, inset: Double = 0) -> Bool {
        edgeDistance(p) >= inset
    }

    /// A deterministic point inside the plot, from `seed`. Samples the bounding box of the regions. If no sample
    /// lands inside, falls back to the middle of the region with the most room (the centre, for the soil patch).
    public func point(seed: UInt64, inset: Double = 0) -> GroundPoint {
        let box = samplingBox
        var rng = DeterministicRNG(seed: seed)
        for _ in 0..<16 {
            let p = GroundPoint(x: box.centre.x + (2 * rng.unit() - 1) * box.halfWidth,
                                y: box.centre.y + (2 * rng.unit() - 1) * box.halfHeight)
            if contains(p, inset: inset) { return p }
        }
        return regions.map(\.centre).max { edgeDistance($0) < edgeDistance($1) } ?? centre
    }

    /// Centre and half-extents of the box `point(seed:)` samples from: the regions' combined bounding box.
    private var samplingBox: (centre: GroundPoint, halfWidth: Double, halfHeight: Double) {
        let r = regions
        if r.count == 1 { return (r[0].centre, r[0].halfWidth, r[0].halfHeight) }
        let xs = r.flatMap { [$0.centre.x - $0.halfWidth, $0.centre.x + $0.halfWidth] }
        let ys = r.flatMap { [$0.centre.y - $0.halfHeight, $0.centre.y + $0.halfHeight] }
        let minX = xs.min() ?? centre.x, maxX = xs.max() ?? centre.x
        let minY = ys.min() ?? centre.y, maxY = ys.max() ?? centre.y
        return (GroundPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2), (maxX - minX) / 2, (maxY - minY) / 2)
    }
}

/// Soil moisture on a coarse grid covering the unit square. Only cells whose centre is inside the plot matter.
public struct SoilField: Codable, Equatable, Sendable {
    public static let columns = 28
    public static let rows = 18
    public static let startingMoisture = 50.0

    /// Row-major moisture, 0...100. Index = row * columns + column.
    public var values: [Double]
    /// Hours left of each soil treatment, per cell (same layout as `values`). Zero means the cell is untreated.
    public var aeratedHours: [Int]
    public var seasolHours: [Int]
    public var fertiliserHours: [Int]

    public init(fill: Double = SoilField.startingMoisture) {
        values = Array(repeating: fill, count: Self.columns * Self.rows)
        aeratedHours = Array(repeating: 0, count: Self.columns * Self.rows)
        seasolHours = aeratedHours
        fertiliserHours = aeratedHours
    }

    private enum CodingKeys: String, CodingKey { case values, aeratedHours, seasolHours, fertiliserHours }

    /// Saves from before soil treatments have no treatment keys, so they load untreated (no save version bump).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let count = Self.columns * Self.rows
        let decoded = try c.decodeIfPresent([Double].self, forKey: .values) ?? []
        values = decoded.count == count ? decoded : Array(repeating: Self.startingMoisture, count: count)
        func hours(_ key: CodingKeys) throws -> [Int] {
            let saved = try c.decodeIfPresent([Int].self, forKey: key) ?? []
            return saved.count == count ? saved : Array(repeating: 0, count: count)
        }
        aeratedHours = try hours(.aeratedHours)
        seasolHours = try hours(.seasolHours)
        fertiliserHours = try hours(.fertiliserHours)
    }

    /// Sets `hours` on every untreated cell within `radius` of `p` in the chosen treatment. Returns false (and
    /// changes nothing) when every cell in reach is already treated.
    public mutating func treat(_ treatment: WritableKeyPath<SoilField, [Int]>, hours: Int,
                               at p: GroundPoint, radius: Double) -> Bool {
        var changed = false
        for r in 0..<Self.rows {
            for c in 0..<Self.columns where Self.cellCentre(column: c, row: r).distance(to: p) < radius {
                let i = r * Self.columns + c
                if self[keyPath: treatment][i] == 0 {
                    self[keyPath: treatment][i] = hours
                    changed = true
                }
            }
        }
        return changed
    }

    /// Whether the treatment is active in the cell under `p`.
    public func isTreated(_ treatment: KeyPath<SoilField, [Int]>, at p: GroundPoint) -> Bool {
        self[keyPath: treatment][Self.cellIndex(of: p)] > 0
    }

    /// One simulated hour passes: every active treatment has an hour less left.
    mutating func tickTreatments() {
        for i in values.indices {
            if aeratedHours[i] > 0 { aeratedHours[i] -= 1 }
            if seasolHours[i] > 0 { seasolHours[i] -= 1 }
            if fertiliserHours[i] > 0 { fertiliserHours[i] -= 1 }
        }
    }

    public static func cellCentre(column: Int, row: Int) -> GroundPoint {
        GroundPoint(x: (Double(column) + 0.5) / Double(columns), y: (Double(row) + 0.5) / Double(rows))
    }

    /// Index of the cell containing `p` (points outside the unit square are clamped to the nearest cell).
    public static func cellIndex(of p: GroundPoint) -> Int {
        let c = min(columns - 1, max(0, Int((p.x * Double(columns)).rounded(.down))))
        let r = min(rows - 1, max(0, Int((p.y * Double(rows)).rounded(.down))))
        return r * columns + c
    }

    /// Bilinear moisture at a ground point.
    public func moisture(at p: GroundPoint) -> Double {
        let fx = min(Double(Self.columns - 1), max(0, p.x * Double(Self.columns) - 0.5))
        let fy = min(Double(Self.rows - 1), max(0, p.y * Double(Self.rows) - 0.5))
        let c0 = Int(fx), r0 = Int(fy)
        let c1 = min(Self.columns - 1, c0 + 1), r1 = min(Self.rows - 1, r0 + 1)
        let tx = fx - Double(c0), ty = fy - Double(r0)
        let a = values[r0 * Self.columns + c0], b = values[r0 * Self.columns + c1]
        let c = values[r1 * Self.columns + c0], d = values[r1 * Self.columns + c1]
        let top = a + (b - a) * tx, bottom = c + (d - c) * tx
        return top + (bottom - top) * ty
    }

    /// Adds `amount` at `p`, falling off smoothly to nothing at `radius`. Results stay within 0...100.
    public mutating func add(_ amount: Double, at p: GroundPoint, radius: Double) {
        guard radius > 0, amount != 0 else { return }
        for r in 0..<Self.rows {
            for c in 0..<Self.columns {
                let d = Self.cellCentre(column: c, row: r).distance(to: p)
                guard d < radius else { continue }
                let w = 1 - d / radius
                let i = r * Self.columns + c
                values[i] = min(100, max(0, values[i] + amount * w * w * (3 - 2 * w)))
            }
        }
    }

    public func forEachCell(_ body: (_ column: Int, _ row: Int, _ centre: GroundPoint, _ moisture: Double) -> Void) {
        for r in 0..<Self.rows {
            for c in 0..<Self.columns {
                body(c, r, Self.cellCentre(column: c, row: r), values[r * Self.columns + c])
            }
        }
    }
}

/// Where a planted flower is in its life after progress reaches 1.
public enum LifeStage: String, Codable, Sendable { case growing, blooming, fading, seedHead }

/// A planted flower (or herb or vegetable) at a free position on the plot.
public struct Plant: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var flower: FlowerType
    public var position: GroundPoint
    public var progress: Double = 0          // 0...1
    /// Snapshot of the soil moisture under the plant, refreshed every simulated hour and on watering.
    public var moisture: Double = SoilField.startingMoisture
    public var dryHours: Int = 0
    public var frostUntil: Date?
    public var isDead: Bool = false
    /// Seed for this plant's variation (growth speed), set when it is planted or sown.
    public var plantSeed: UInt64 = 0
    /// Simulated hours since progress reached 1. Drives the bloom, fade and seed head clock.
    public var bloomHoursElapsed: Int = 0

    public init(id: Int, flower: FlowerType, position: GroundPoint, plantSeed: UInt64 = 0,
                moisture: Double = SoilField.startingMoisture) {
        self.id = id
        self.flower = flower
        self.position = position
        self.plantSeed = plantSeed
        self.moisture = moisture
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        flower = try c.decode(FlowerType.self, forKey: .flower)
        position = try c.decode(GroundPoint.self, forKey: .position)
        progress = try c.decodeIfPresent(Double.self, forKey: .progress) ?? 0
        moisture = try c.decodeIfPresent(Double.self, forKey: .moisture) ?? SoilField.startingMoisture
        dryHours = try c.decodeIfPresent(Int.self, forKey: .dryHours) ?? 0
        frostUntil = try c.decodeIfPresent(Date.self, forKey: .frostUntil)
        isDead = try c.decodeIfPresent(Bool.self, forKey: .isDead) ?? false
        plantSeed = try c.decodeIfPresent(UInt64.self, forKey: .plantSeed) ?? 0
        bloomHoursElapsed = try c.decodeIfPresent(Int.self, forKey: .bloomHoursElapsed) ?? 0
    }

    public var isWilted: Bool { !isDead && dryHours >= Tuning.wiltAfterDryHours }

    /// Growth stage label from progress (thresholds unchanged from the grid version).
    public var stage: GrowthStage {
        switch progress {
        case ..<0.25: .seed
        case ..<0.55: .sprout
        case ..<1.0: .bud
        default: .bloom
        }
    }

    /// Life cycle: growing until progress is 1, then blooming, fading and seedHead.
    public var lifeStage: LifeStage {
        guard progress >= 1 else { return .growing }
        if bloomHoursElapsed < Tuning.bloomDays * 24 { return .blooming }
        if bloomHoursElapsed < (Tuning.bloomDays + Tuning.fadeDays) * 24 { return .fading }
        return .seedHead
    }

    /// Petal fade: 0 before the fading period, rising linearly to 1 across it.
    public var fade: Double {
        guard progress >= 1 else { return 0 }
        let start = Tuning.bloomDays * 24, length = Tuning.fadeDays * 24
        return min(1, max(0, Double(bloomHoursElapsed - start) / Double(length)))
    }

    /// Leaf droop for a given soil moisture: 0 at or above `Tuning.droopFullMoisture`, smoothly rising to 1
    /// at moisture 0, and 1 once the plant is wilted or dead. Pass `moisture` (the stored snapshot) when rendering.
    public func droop(moisture: Double) -> Double {
        if isWilted || isDead { return 1 }
        let t = min(1, max(0, (Tuning.droopFullMoisture - moisture) / Tuning.droopFullMoisture))
        return t * t * (3 - 2 * t)
    }

    /// Per-plant growth speed multiplier, within 1 +/- `Tuning.speedVariation`.
    public var speedFactor: Double {
        1 + (DeterministicHash.unitFromBits(plantSeed) * 2 - 1) * Tuning.speedVariation
    }
}

/// A weed on the soil. It slows plants near it, more as it ages, up to a cap.
public struct Weed: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var position: GroundPoint
    public var ageHours: Int = 0

    public init(id: Int, position: GroundPoint, ageHours: Int = 0) {
        self.id = id
        self.position = position
        self.ageHours = ageHours
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        position = try c.decode(GroundPoint.self, forKey: .position)
        ageHours = try c.decodeIfPresent(Int.self, forKey: .ageHours) ?? 0
    }
}

/// Hashing helpers so catch-up and random placement are deterministic.
enum DeterministicHash {
    static func mix(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Seed for a pair of integers (hour index, ids, and so on).
    static func seed(_ a: Int, _ b: Int) -> UInt64 {
        mix(mix(UInt64(bitPattern: Int64(a))) &+ UInt64(bitPattern: Int64(b)) &* 0xD6E8_FEB8_6659_FD93)
    }

    static func unitFromBits(_ x: UInt64) -> Double { Double(x >> 11) / Double(1 << 53) }
}

/// A small deterministic stream of values in 0..<1.
struct DeterministicRNG {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func unit() -> Double {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        return DeterministicHash.unitFromBits(DeterministicHash.mix(state))
    }
}

/// The free-form garden: plants and weeds at any point on a soft-edged patch, with a moisture field under it.
public struct Garden: Codable, Equatable, Sendable {
    /// Save format version. Saves with any other version than this (or the one before, see `decodeSave`) are discarded.
    public static let currentVersion = 5
    /// The oldest version whose save can still be loaded. Version 4 saves get an empty collection book.
    public static let oldestSupportedVersion = 4

    public var version: Int = Garden.currentVersion
    /// Kept in id order: ids only ever grow, and new plants are appended.
    public var plants: [Plant]
    public var weeds: [Weed]
    public var soil: SoilField
    public var plot: PlotShape
    public var lastSimulatedAt: Date
    public var coins: Int = Tuning.startingCoins
    /// Seed packets owned, keyed by `FlowerType.rawValue` so the dictionary encodes as a JSON object.
    /// Use `seeds` for typed access.
    public var seedStock: [String: Int]
    /// Times each visitor species has been spotted, keyed by `VisitorSpecies.rawValue`. Use `sightingCount` to read it.
    public var sightings: [String: Int] = [:]
    /// Milestone thresholds (`VisitorMilestone.species`) already claimed. A claimed milestone is never paid again.
    public var claimedMilestones: [Int] = []
    /// When the app was last opened on a new day (see `GardenEngine.recordOpen`). nil before the first open.
    public var lastOpenedAt: Date?
    /// Consecutive days the app has been opened, counting `lastOpenedAt`'s day. Restarts at 1 after a missed day.
    public var openStreak: Int = 0
    /// Next id for plants and weeds (one counter, so ids are unique across both).
    public var nextID: Int = 1

    public init(now: Date) {
        plants = []
        weeds = []
        soil = SoilField()
        plot = PlotShape()
        lastSimulatedAt = now
        seedStock = [FlowerType.daisy.rawValue: Tuning.startingDaisySeeds]
    }

    /// Seed packets owned by flower type. Types with no seeds are absent.
    public var seeds: [FlowerType: Int] {
        get {
            var out: [FlowerType: Int] = [:]
            for (key, count) in seedStock where count > 0 {
                if let f = FlowerType(rawValue: key) { out[f] = count }
            }
            return out
        }
        set {
            seedStock = Dictionary(uniqueKeysWithValues: newValue.filter { $0.value > 0 }.map { ($0.key.rawValue, $0.value) })
        }
    }

    public func seedCount(_ flower: FlowerType) -> Int { seedStock[flower.rawValue] ?? 0 }

    /// Times this visitor species has been spotted.
    public func sightingCount(_ species: VisitorSpecies) -> Int { sightings[species.rawValue] ?? 0 }

    /// Decodes a saved garden. Accepts the current version and `oldestSupportedVersion`, which is upgraded in
    /// place (the garden is kept, sightings start empty). Anything else returns nil, so the app starts fresh.
    public static func decodeSave(_ data: Data) -> Garden? {
        guard let saved = try? JSONDecoder().decode(Garden.self, from: data),
              (oldestSupportedVersion...currentVersion).contains(saved.version) else { return nil }
        var garden = saved
        garden.version = currentVersion
        return garden
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        plants = try c.decodeIfPresent([Plant].self, forKey: .plants) ?? []
        weeds = try c.decodeIfPresent([Weed].self, forKey: .weeds) ?? []
        soil = try c.decodeIfPresent(SoilField.self, forKey: .soil) ?? SoilField()
        plot = try c.decodeIfPresent(PlotShape.self, forKey: .plot) ?? PlotShape()
        lastSimulatedAt = try c.decode(Date.self, forKey: .lastSimulatedAt)
        coins = try c.decodeIfPresent(Int.self, forKey: .coins) ?? Tuning.startingCoins
        seedStock = try c.decodeIfPresent([String: Int].self, forKey: .seedStock) ?? [:]
        sightings = try c.decodeIfPresent([String: Int].self, forKey: .sightings) ?? [:]
        claimedMilestones = try c.decodeIfPresent([Int].self, forKey: .claimedMilestones) ?? []
        lastOpenedAt = try c.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
        openStreak = try c.decodeIfPresent(Int.self, forKey: .openStreak) ?? 0
        nextID = try c.decodeIfPresent(Int.self, forKey: .nextID)
            ?? ((plants.map(\.id) + weeds.map(\.id)).max() ?? 0) + 1
    }
}
