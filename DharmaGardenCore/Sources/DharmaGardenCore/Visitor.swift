import Foundation

/// How often a visitor species turns up. Drives the coin reward for spotting it.
public enum VisitorRarity: String, Codable, Sendable, CaseIterable { case common, uncommon, rare }

/// Creatures that drop in on the garden for a while. Visitors are live view state: they are not saved, only
/// the sightings they leave in the collection book are.
public enum VisitorSpecies: String, Codable, Sendable, CaseIterable {
    case bee, cabbageWhiteButterfly, orangeButterfly, ladybird, dragonfly, magpieLark, willieWagtail
    case blueTongueLizard, snail, frog, moth, cockatoo

    public var displayName: String {
        switch self {
        case .bee: "Bee"
        case .cabbageWhiteButterfly: "Cabbage white"
        case .orangeButterfly: "Orange butterfly"
        case .ladybird: "Ladybird"
        case .dragonfly: "Dragonfly"
        case .magpieLark: "Magpie-lark"
        case .willieWagtail: "Willie wagtail"
        case .blueTongueLizard: "Blue-tongue lizard"
        case .snail: "Snail"
        case .frog: "Frog"
        case .moth: "Moth"
        case .cockatoo: "Cockatoo"
        }
    }

    public var rarity: VisitorRarity {
        switch self {
        case .bee, .cabbageWhiteButterfly, .ladybird, .magpieLark, .snail: .common
        case .orangeButterfly, .dragonfly, .willieWagtail, .blueTongueLizard, .frog: .uncommon
        case .moth, .cockatoo: .rare
        }
    }

    /// Coins paid the first time (and every time) the visitor is spotted.
    public var coinReward: Int {
        switch rarity {
        case .common: Tuning.visitorCommonReward
        case .uncommon: Tuning.visitorUncommonReward
        case .rare: Tuning.visitorRareReward
        }
    }

    /// One line for the collection book.
    public var blurb: String {
        switch self {
        case .bee: "A busy little bee working the flowers."
        case .cabbageWhiteButterfly: "A white butterfly that lays its eggs on brassicas."
        case .orangeButterfly: "A bright orange butterfly, easy to spot in the sun."
        case .ladybird: "A red and black beetle that eats aphids and soft pests."
        case .dragonfly: "A darting hunter that likes warm, still afternoons."
        case .magpieLark: "A black and white songbird that walks the lawn in pairs."
        case .willieWagtail: "A fearless bird that flicks its tail and snaps up insects."
        case .blueTongueLizard: "A slow, sun-loving lizard that shows its blue tongue when threatened."
        case .snail: "A slow gardener that comes out after rain."
        case .frog: "A small frog that calls from damp soil after a night of rain."
        case .moth: "A night flyer that comes to the flowers after dark."
        case .cockatoo: "A loud visitor from the trees. Rarely seen in a small garden."
        }
    }

    /// Where and when to look, shown in the collection book until the species is spotted.
    public var hint: String {
        switch self {
        case .bee: "Warm sunny days with at least two flowers in bloom."
        case .cabbageWhiteButterfly: "Sunny, calm days with something in bloom."
        case .orangeButterfly: "Warm sunny days with several flowers in bloom."
        case .ladybird: "Mild, dry days in spring and summer."
        case .dragonfly: "Warm, calm, dry afternoons."
        case .magpieLark: "Dry days, any season."
        case .willieWagtail: "Dry days, any season."
        case .blueTongueLizard: "Hot, dry days outside winter."
        case .snail: "The day after it rains."
        case .frog: "A wet night after rain."
        case .moth: "Mild nights with flowers in bloom."
        case .cockatoo: "Dry days, very occasionally."
        }
    }

    /// Whether the visitor is drawn to flowers (and so lands near a bloom) rather than the open lawn.
    public var visitsFlowers: Bool {
        switch self {
        case .bee, .cabbageWhiteButterfly, .orangeButterfly, .ladybird, .moth: true
        case .dragonfly, .magpieLark, .willieWagtail, .blueTongueLizard, .snail, .frog, .cockatoo: false
        }
    }
}

/// A visitor on the patch right now. Position is on the ground plane, like plants.
public struct Visitor: Equatable, Sendable, Identifiable {
    public var id: Int
    public var species: VisitorSpecies
    public var position: GroundPoint
    public var spawnedAt: Date
    /// Seconds from arrival until the visitor leaves.
    public var lifetime: TimeInterval

    public init(id: Int, species: VisitorSpecies, position: GroundPoint, spawnedAt: Date, lifetime: TimeInterval) {
        self.id = id
        self.species = species
        self.position = position
        self.spawnedAt = spawnedAt
        self.lifetime = lifetime
    }

    public var departsAt: Date { spawnedAt.addingTimeInterval(lifetime) }

    public func isGone(at now: Date) -> Bool { now >= departsAt }
}

/// The conditions that decide which visitors can turn up. Built from the garden and the weather.
public struct VisitorContext: Equatable, Sendable {
    public var season: Season
    public var isDay: Bool
    public var temperatureC: Double
    public var isRaining: Bool
    /// Rain in the last few hours, including now.
    public var recentlyRained: Bool
    public var windKmh: Double
    /// One entry per living plant that is in bloom right now.
    public var bloomingPlants: [FlowerType]

    public init(season: Season = .summer, isDay: Bool = true, temperatureC: Double = 22, isRaining: Bool = false,
                recentlyRained: Bool = false, windKmh: Double = 5, bloomingPlants: [FlowerType] = []) {
        self.season = season
        self.isDay = isDay
        self.temperatureC = temperatureC
        self.isRaining = isRaining
        self.recentlyRained = recentlyRained
        self.windKmh = windKmh
        self.bloomingPlants = bloomingPlants
    }

    /// Flowers in bloom in the garden (dead and not-yet-flowering plants are ignored).
    public static func blooming(in garden: Garden) -> [FlowerType] {
        garden.plants.filter { !$0.isDead && $0.lifeStage == .blooming }.map(\.flower)
    }

    /// Context from the current weather report and the garden at `now`.
    public static func make(report: WeatherReport, garden: Garden, now: Date) -> VisitorContext {
        let current = report.current
        let raining = current.precipitationMM > 0
            || [WeatherCondition.rain, .drizzle, .thunderstorm].contains(current.condition)
        let window = Tuning.visitorRecentRainHours * 3600
        let rainedLately = report.hourly.contains { sample in
            let age = now.timeIntervalSince(sample.date)
            return sample.precipitationMM > 0 && age >= 0 && age < window
        }
        return VisitorContext(
            season: SeasonProvider.season(on: now, latitude: report.latitude),
            isDay: current.isDay,
            temperatureC: current.temperatureC,
            isRaining: raining,
            recentlyRained: raining || rainedLately,
            windKmh: current.windKmh,
            bloomingPlants: blooming(in: garden))
    }
}

/// Relative weights for each species under a context. A weight of 0 means the species cannot turn up.
public enum VisitorRules {
    public static func weight(of species: VisitorSpecies, in c: VisitorContext) -> Double {
        // Insects and reptiles need some warmth and are not out in winter.
        let active = c.season != .winter
        let dry = !c.isRaining
        let calm = c.windKmh < Tuning.visitorCalmWindKmh
        let blooms = c.bloomingPlants.count

        switch species {
        case .bee:
            guard c.isDay, dry, active, calm, c.temperatureC >= Tuning.visitorWarmC,
                  blooms >= Tuning.visitorBeeMinBlooms else { return 0 }
            return 4 + Double(min(blooms, 8))
        case .cabbageWhiteButterfly:
            guard c.isDay, dry, active, calm, c.temperatureC >= Tuning.visitorButterflyMinC, blooms >= 1 else { return 0 }
            return 4 + Double(min(blooms, 6))
        case .orangeButterfly:
            guard c.isDay, dry, active, calm, c.temperatureC >= Tuning.visitorOrangeMinC, blooms >= 1 else { return 0 }
            return 2 + Double(min(blooms, 6))
        case .ladybird:
            guard c.isDay, dry, active, c.temperatureC >= Tuning.visitorButterflyMinC else { return 0 }
            return 3
        case .dragonfly:
            guard c.isDay, dry, active, calm, c.temperatureC >= Tuning.visitorDragonflyMinC else { return 0 }
            return 2
        case .magpieLark:
            return c.isDay && dry ? 4 : 0
        case .willieWagtail:
            return c.isDay && dry ? 3 : 0
        case .blueTongueLizard:
            guard c.isDay, dry, active, c.temperatureC >= Tuning.visitorLizardMinC else { return 0 }
            return 3
        case .snail:
            return c.recentlyRained ? 6 : 0
        case .frog:
            guard c.recentlyRained, !c.isDay, active, c.temperatureC >= Tuning.visitorFrogMinC else { return 0 }
            return 4
        case .moth:
            guard !c.isDay, active, c.temperatureC >= Tuning.visitorMothMinC, blooms >= 1 else { return 0 }
            return 2
        case .cockatoo:
            return c.isDay && dry ? 1 : 0
        }
    }

    /// Every species with its weight, in `VisitorSpecies.allCases` order (zero weights included).
    public static func weights(in c: VisitorContext) -> [(species: VisitorSpecies, weight: Double)] {
        VisitorSpecies.allCases.map { (species: $0, weight: weight(of: $0, in: c)) }
    }
}

/// Decides whether a visitor arrives at a check, and which one. Pure: the same inputs always give the same visitor.
public enum VisitorSpawner {
    /// Rolls one check. Returns nil when the garden is already at `Tuning.maxVisitors`, when no visitor arrives
    /// this time, or when no species can turn up under the context. `seed` should differ for each check.
    public static func roll(garden: Garden, context: VisitorContext, now: Date, liveCount: Int,
                            seed: UInt64) -> Visitor? {
        guard liveCount < Tuning.maxVisitors else { return nil }
        var rng = DeterministicRNG(seed: seed)
        guard rng.unit() < Tuning.visitorArrivalChance else { return nil }

        let options = VisitorRules.weights(in: context).filter { $0.weight > 0 }
        let total = options.reduce(0) { $0 + $1.weight }
        guard total > 0, let last = options.last else { return nil }
        var pick = rng.unit() * total
        var species = last.species
        for option in options {
            if pick < option.weight {
                species = option.species
                break
            }
            pick -= option.weight
        }

        let position = arrivalPoint(for: species, garden: garden, rng: &rng, seed: seed)
        let lifetime = Tuning.visitorMinLifetimeSeconds
            + rng.unit() * (Tuning.visitorMaxLifetimeSeconds - Tuning.visitorMinLifetimeSeconds)
        return Visitor(id: Int(truncatingIfNeeded: DeterministicHash.mix(seed)), species: species,
                       position: position, spawnedAt: now, lifetime: lifetime)
    }

    /// Flower visitors land near a living bloom; everything else lands at a random point on the lawn.
    static func arrivalPoint(for species: VisitorSpecies, garden: Garden, rng: inout DeterministicRNG,
                             seed: UInt64) -> GroundPoint {
        let blooms = garden.plants.filter { !$0.isDead && $0.lifeStage == .blooming }
        if species.visitsFlowers, !blooms.isEmpty {
            let target = blooms[min(blooms.count - 1, Int(rng.unit() * Double(blooms.count)))].position
            let angle = rng.unit() * 2 * Double.pi
            let distance = Tuning.visitorPerchRadius * rng.unit()
            let p = GroundPoint(x: target.x + cos(angle) * distance, y: target.y + sin(angle) * distance)
            return garden.plot.contains(p, inset: Tuning.sowInset) ? p : target
        }
        return garden.plot.point(seed: DeterministicHash.seed(Int(truncatingIfNeeded: seed), 7), inset: Tuning.sowInset)
    }
}
