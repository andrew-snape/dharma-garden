import Foundation

/// Rules and player actions for the free-form garden. Pure and deterministic: catch-up runs hour by hour,
/// with randomness keyed by hour index and ids, so the same inputs always give the same garden.
public enum GardenEngine {

    // MARK: Daily visits

    /// Counts today as a day the app was opened. Opening again on the same day changes nothing, opening on the
    /// next day extends the streak, and opening after a missed day restarts it at 1. Returns true when the
    /// garden changed.
    @discardableResult
    public static func recordOpen(in g: inout Garden, now: Date, calendar: Calendar = .current) -> Bool {
        if let last = g.lastOpenedAt {
            if calendar.isDate(last, inSameDayAs: now) { return false }
            // A clock set back must not extend the streak.
            guard now > last else { return false }
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now)
            g.openStreak = yesterday.map { calendar.isDate(last, inSameDayAs: $0) } == true ? g.openStreak + 1 : 1
        } else {
            g.openStreak = 1
        }
        g.lastOpenedAt = now
        return true
    }

    // MARK: Simulation

    /// Advance the garden hour by hour using the supplied weather. Hours with no sample use mild neutral
    /// weather (18 C) so the game never blocks on a failed fetch.
    ///
    /// `speed` runs that many simulation steps per real hour on the same weather sample (rounded, at least 1),
    /// so plants grow, weeds spawn and age and the soil dries or soaks that many times faster. The clock,
    /// weather and seasons stay real. At 1 the result is identical to the plain hourly run.
    public static func advance(_ garden: Garden, weather: [WeatherSample], to now: Date, speed: Double = 1) -> Garden {
        // Time never runs backwards: a garden already simulated past `now` is returned unchanged.
        guard now > garden.lastSimulatedAt else { return garden }
        var g = garden
        let byHour = Dictionary(weather.map { (hourStart($0.date), $0) }, uniquingKeysWith: { $1 })
        var hour = hourStart(g.lastSimulatedAt)
        let end = hourStart(now)
        let steps = speed.isFinite ? max(1, Int(speed.rounded())) : 1
        while hour < end {
            hour = hour.addingTimeInterval(3600)
            let w = byHour[hour] ?? WeatherSample(date: hour, temperatureC: 18)
            for sub in 0..<steps {
                // Each sub-step has its own tick number so weed spawns stay spread out and never repeat a spot.
                step(&g, w, hour, tick: hourIndex(hour) * steps + sub)
            }
        }
        g.lastSimulatedAt = now
        return g
    }

    static func hourStart(_ d: Date) -> Date {
        Date(timeIntervalSince1970: (d.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
    }

    static func hourIndex(_ hour: Date) -> Int { Int((hour.timeIntervalSince1970 / 3600).rounded(.down)) }

    /// One simulated hour, in order: weeds appear, the soil drains and rains, plants grow, then finished
    /// seed heads drop volunteers for the next hour, and weeds age.
    /// `tick` numbers the step for weed spawning; it equals the hour index at normal speed.
    static func step(_ g: inout Garden, _ w: WeatherSample, _ hour: Date, tick: Int? = nil) {
        let h = tick ?? hourIndex(hour)
        if h % Tuning.weedCheckEveryHours == 0 { spawnDharmaGarden(&g, hourIndex: h) }

        drainSoil(&g, w)

        let slow = slowdowns(g)
        let soil = g.soil
        var finished: [(id: Int, flower: FlowerType, position: GroundPoint)] = []
        for i in g.plants.indices {
            let p = g.plants[i]
            var updated = p
            let seedHeadEnded = stepPlant(&updated, soil: soil, w, hour,
                                          crowding: slow.crowding[i], weeds: slow.weeds[i])
            g.plants[i] = updated
            if seedHeadEnded { finished.append((p.id, p.flower, p.position)) }
        }

        g.soil.tickTreatments()

        if !finished.isEmpty {
            let gone = Set(finished.map(\.id))
            g.plants.removeAll { gone.contains($0.id) }
            for parent in finished { sowVolunteers(from: parent, hour: hour, in: &g) }
        }

        for i in g.weeds.indices { g.weeds[i].ageHours += 1 }

        let excess = g.plants.count - Tuning.maxEntriesKeptWithDead
        if excess > 0 {
            var removed = 0
            g.plants.removeAll { p in
                guard removed < excess, p.isDead else { return false }
                removed += 1
                return true
            }
        }
    }

    /// Soil drains by the same rules as before (heat, wind), and dry-tolerant or thirsty plants
    /// change the drain in their own cell. Rain refills everywhere.
    static func drainSoil(_ g: inout Garden, _ w: WeatherSample) {
        var drain = Tuning.baseDrainPerHour
        if w.temperatureC > Tuning.heatThresholdC { drain *= Tuning.heatDrainMultiplier }
        if w.windKmh > Tuning.windThresholdKmh { drain *= Tuning.windDrainMultiplier }

        var modifiers = [Double](repeating: 1, count: g.soil.values.count)
        for p in g.plants where !p.isDead {
            var m = 1.0
            if p.flower.dryTolerant { m *= Tuning.dryTolerantDrainMultiplier }
            if p.flower.thirsty { m *= Tuning.thirstyDrainMultiplier }
            if m != 1 { modifiers[SoilField.cellIndex(of: p.position)] *= m }
        }

        let rain = w.precipitationMM * Tuning.moisturePerRainMM
        for i in g.soil.values.indices {
            let aerated = g.soil.aeratedHours[i] > 0 ? Tuning.aerateDrainMultiplier : 1
            g.soil.values[i] = min(100, max(0, g.soil.values[i] - drain * modifiers[i] * aerated + rain))
        }
    }

    /// Growth slowdowns per plant index: crowding (fraction lost to close neighbours, capped) and weeds
    /// (fraction lost to nearby weeds, capped). Both are computed from positions at the start of the hour.
    static func slowdowns(_ g: Garden) -> (crowding: [Double], weeds: [Double]) {
        let n = g.plants.count
        let alive = g.plants.map { !$0.isDead }
        var neighbours = [Int](repeating: 0, count: n)
        for i in 0..<n where alive[i] {
            for j in (i + 1)..<max(i + 1, n) where alive[j] {
                if g.plants[i].position.distance(to: g.plants[j].position) < Tuning.crowdingRadius {
                    neighbours[i] += 1
                    neighbours[j] += 1
                }
            }
        }
        let crowding = neighbours.map { min(Tuning.crowdingCap, Double($0) * Tuning.crowdingPerNeighbour) }

        let weedSlow: [Double] = g.plants.map { p in
            var total = 0.0
            for weed in g.weeds where weed.position.distance(to: p.position) < Tuning.weedSlowdownRadius {
                let strength = 0.5 + 0.5 * min(1, Double(weed.ageHours) / Double(Tuning.weedFullStrengthHours))
                total += Tuning.weedSlowdownPerWeed * strength
            }
            return min(Tuning.weedSlowdownCap, total)
        }
        return (crowding, weedSlow)
    }

    /// Advances one plant by one hour. Returns true when its seed head period ended this hour.
    static func stepPlant(_ p: inout Plant, soil: SoilField, _ w: WeatherSample, _ hour: Date,
                          crowding: Double, weeds: Double) -> Bool {
        guard !p.isDead else { return false }
        p.moisture = soil.moisture(at: p.position)

        if p.moisture <= 0 { p.dryHours += 1 } else { p.dryHours = 0 }
        if p.dryHours >= Tuning.deathAfterDryHours { p.isDead = true; return false }

        if p.flower.frostTender, !w.isDay, w.temperatureC < Tuning.frostThresholdC {
            p.frostUntil = hour.addingTimeInterval(Double(Tuning.frostDurationHours) * 3600)
        }

        // Once in bloom the flower ages on its own clock, watered or not.
        if p.progress >= 1 {
            p.bloomHoursElapsed += 1
            return p.bloomHoursElapsed >= Tuning.lifeCycleHours
        }

        guard p.moisture >= Tuning.growthPauseBelowMoisture, !p.isWilted else { return false }

        var rate = p.speedFactor / (p.flower.daysToBloom * 24)
        rate *= (1 - crowding) * (1 - weeds)
        rate *= 1 + treatmentGrowthBonus(soil: soil, at: p.position)
        // Only frost-tender plants are ever given a frost clock, so frost-tolerant plants are never slowed.
        if p.flower.frostTender, let until = p.frostUntil, until > hour { rate *= Tuning.frostGrowthMultiplier }
        if p.flower.lovesHeat {
            if w.temperatureC < Tuning.coldGrowthBelowC { rate *= Tuning.coldGrowthMultiplier }
            else if w.temperatureC > Tuning.heatGrowthAboveC { rate *= Tuning.heatGrowthMultiplier }
        }
        if p.flower.coolSeason {
            if w.temperatureC > Tuning.lettuceBoltAboveC { rate *= Tuning.lettuceBoltGrowthMultiplier }
            else if w.temperatureC < Tuning.lettuceCoolBelowC { rate *= Tuning.lettuceCoolGrowthMultiplier }
        }
        p.progress = min(1, p.progress + rate)
        return false
    }

    /// The growth bonus from the soil treatments active under a plant (they add up).
    static func treatmentGrowthBonus(soil: SoilField, at p: GroundPoint) -> Double {
        var bonus = 0.0
        if soil.isTreated(\.aeratedHours, at: p) { bonus += Tuning.aerateGrowthBonus }
        if soil.isTreated(\.seasolHours, at: p) { bonus += Tuning.seasolGrowthBonus }
        if soil.isTreated(\.fertiliserHours, at: p) { bonus += Tuning.fertiliserGrowthBonus }
        return bonus
    }

    /// DharmaGarden appear at deterministic random points on the soil. The expected count scales with plot area.
    static func spawnDharmaGarden(_ g: inout Garden, hourIndex h: Int) {
        let expected = Tuning.weedSpawnsPerCheckAtDefaultPlot * g.plot.area / PlotShape().area
        let whole = Int(expected.rounded(.down))
        var roll = DeterministicRNG(seed: DeterministicHash.seed(h, -1))
        let count = whole + (roll.unit() < expected - Double(whole) ? 1 : 0)
        for k in 0..<count where g.weeds.count < Tuning.maxDharmaGarden {
            let p = g.plot.point(seed: DeterministicHash.seed(h, 1000 + k), inset: Tuning.weedSpawnInset)
            g.weeds.append(Weed(id: takeID(&g), position: p))
        }
    }

    /// A finished seed head scatters 0 to 3 volunteers around where it stood, inside the plot and clear of
    /// other plants. They start growing the next hour.
    static func sowVolunteers(from parent: (id: Int, flower: FlowerType, position: GroundPoint),
                              hour: Date, in g: inout Garden) {
        let h = hourIndex(hour)
        var rng = DeterministicRNG(seed: DeterministicHash.seed(h, parent.id))
        let count = min(Tuning.maxVolunteers, Int(rng.unit() * 4))
        for _ in 0..<count {
            for _ in 0..<8 {
                let angle = rng.unit() * 2 * Double.pi
                let dist = Tuning.volunteerRadius * rng.unit()
                let p = GroundPoint(x: parent.position.x + cos(angle) * dist,
                                    y: parent.position.y + sin(angle) * dist)
                if place(parent.flower, at: p, in: &g, spacing: Tuning.volunteerSpacing, time: hour) { break }
            }
        }
    }

    /// Puts a new plant in the garden with no carrot or seed cost. Fails when the point is outside the plot,
    /// too close to a living plant, or the garden already holds `maxPlants` living plants. Dead plants in
    /// the way are replaced.
    static func place(_ flower: FlowerType, at p: GroundPoint, in g: inout Garden,
                      spacing: Double, time: Date) -> Bool {
        guard g.plot.contains(p, inset: Tuning.sowInset) else { return false }
        guard g.plants.filter({ !$0.isDead }).count < Tuning.maxPlants else { return false }
        guard !g.plants.contains(where: { !$0.isDead && $0.position.distance(to: p) < spacing }) else { return false }
        g.plants.removeAll { $0.isDead && $0.position.distance(to: p) < spacing }
        let id = takeID(&g)
        let seed = DeterministicHash.seed(Int(time.timeIntervalSince1970), id)
        g.plants.append(Plant(id: id, flower: flower, position: p, plantSeed: seed,
                              moisture: g.soil.moisture(at: p)))
        return true
    }

    static func takeID(_ g: inout Garden) -> Int {
        let id = g.nextID
        g.nextID += 1
        return id
    }

    /// Index of the point closest to `p` within `reach` (the first one wins ties), or nil.
    static func nearestIndex(in points: [GroundPoint], to p: GroundPoint, reach: Double) -> Int? {
        var best: Int?
        var bestDistance = Double.infinity
        for (i, q) in points.enumerated() {
            let d = q.distance(to: p)
            if d <= reach && d < bestDistance {
                best = i
                bestDistance = d
            }
        }
        return best
    }

    /// Refreshes every plant's moisture snapshot from the soil (after watering).
    static func refreshMoisture(_ g: inout Garden) {
        let soil = g.soil
        for i in g.plants.indices { g.plants[i].moisture = soil.moisture(at: g.plants[i].position) }
    }

    // MARK: Player actions

    /// Whether a seed could land at `point` right now: on the patch, at least `Tuning.sowSpacing` from every living
    /// plant, and the garden not full. Withered plants do not block: planting replaces them. The seed ghost uses
    /// this same rule.
    public static func canPlant(at point: GroundPoint, in g: Garden) -> Bool {
        g.plot.contains(point, inset: Tuning.sowInset)
            && g.plants.filter({ !$0.isDead }).count < Tuning.maxPlants
            && !g.plants.contains { !$0.isDead && $0.position.distance(to: point) < Tuning.sowSpacing }
    }

    /// Plants a seed from the packet inventory at `point`. Fails (and changes nothing) when `canPlant` is false or
    /// the player has no seeds of that type. Consumes one packet on success. A withered plant in the way is cleared.
    public static func sow(_ flower: FlowerType, at point: GroundPoint, in g: inout Garden, now: Date? = nil) -> Bool {
        guard g.seedCount(flower) > 0, canPlant(at: point, in: g) else { return false }
        guard place(flower, at: point, in: &g, spacing: Tuning.sowSpacing, time: now ?? g.lastSimulatedAt) else {
            return false
        }
        g.seedStock[flower.rawValue] = g.seedCount(flower) - 1
        return true
    }

    /// Free planting, for volunteers and debug tools. Same placement rules as `sow` but no seed is used.
    public static func plant(_ flower: FlowerType, at point: GroundPoint, in g: inout Garden, now: Date? = nil) -> Bool {
        place(flower, at: point, in: &g, spacing: Tuning.volunteerSpacing, time: now ?? g.lastSimulatedAt)
    }

    /// What `setBedStyle` did to the garden.
    public struct BedStyleChange: Equatable, Sendable {
        public var plantsMoved = 0
        /// Living plants with no room in the new bed. Each one's seed packet went back to the stock.
        public var seedsReturned = 0
        public var weedsRemoved = 0
    }

    /// Switches the bed's style, which changes where plants may stand. Living plants outside the new bed move to
    /// the nearest spot that fits (respecting `Tuning.sowSpacing`). A living plant with no room goes back to the seed
    /// stock. Withered plants outside are cleared and weeds outside vanish. Deterministic.
    @discardableResult
    public static func setBedStyle(_ style: BedStyle, in g: inout Garden) -> BedStyleChange {
        g.plot.style = style
        var change = BedStyleChange()

        let weedCount = g.weeds.count
        g.weeds.removeAll { !g.plot.contains($0.position) }
        change.weedsRemoved = weedCount - g.weeds.count

        var gone = Set<Int>()
        for i in g.plants.indices where !g.plot.contains(g.plants[i].position, inset: Tuning.sowInset) {
            let plant = g.plants[i]
            if plant.isDead {
                gone.insert(plant.id)
                continue
            }
            // Only plants already inside the bed block a spot. Outside plants are placed one at a time, in id order.
            let taken = g.plants.indices.compactMap { j -> GroundPoint? in
                let other = g.plants[j]
                guard j != i, !other.isDead, !gone.contains(other.id), g.plot.contains(other.position) else { return nil }
                return other.position
            }
            if let spot = nearestFreeSpot(to: plant.position, taken: taken, in: g.plot) {
                g.plants[i].position = spot
                change.plantsMoved += 1
            } else {
                gone.insert(plant.id)
                g.seedStock[plant.flower.rawValue] = g.seedCount(plant.flower) + 1
                change.seedsReturned += 1
            }
        }
        g.plants.removeAll { gone.contains($0.id) }
        refreshMoisture(&g)
        return change
    }

    /// The spot nearest to `p` inside `plot` that is `Tuning.sowInset` from the edge and `Tuning.sowSpacing` from
    /// every point in `taken`. Searches outward in rings with fixed angles, so the answer is deterministic. Nil when
    /// the bed has no room.
    static func nearestFreeSpot(to p: GroundPoint, taken: [GroundPoint], in plot: PlotShape) -> GroundPoint? {
        let step = Tuning.sowSpacing / 2
        let rings = Int((1.5 / step).rounded(.up))
        for ring in 1...rings {
            let radius = Double(ring) * step
            let count = 8 * ring
            for k in 0..<count {
                let angle = 2 * Double.pi * Double(k) / Double(count)
                let q = GroundPoint(x: p.x + cos(angle) * radius, y: p.y + sin(angle) * radius)
                if plot.contains(q, inset: Tuning.sowInset),
                   !taken.contains(where: { $0.distance(to: q) < Tuning.sowSpacing }) {
                    return q
                }
            }
        }
        return nil
    }

    /// Buys `count` seed packets of one type for `seedPrice` carrots each. Changes nothing when the count is
    /// not positive or the carrots are short.
    public static func buySeeds(_ flower: FlowerType, count: Int, in g: inout Garden) -> Bool {
        guard count > 0 else { return false }
        let cost = flower.seedPrice * count
        guard g.coins >= cost else { return false }
        g.coins -= cost
        g.seedStock[flower.rawValue] = g.seedCount(flower) + count
        return true
    }

    /// Soft watering: moisture rises most at `point` and fades to nothing at `radius`.
    public static func water(at point: GroundPoint, in g: inout Garden,
                             radius: Double = Tuning.waterRadius, amount: Double = Tuning.waterAmount) {
        g.soil.add(amount, at: point, radius: radius)
        refreshMoisture(&g)
    }

    /// The garden fork: loosens the soil around `point`. Free. Returns false when the point is off the bed or the
    /// soil there is already aerated.
    @discardableResult
    public static func aerate(at point: GroundPoint, in g: inout Garden) -> Bool {
        guard g.plot.contains(point) else { return false }
        return g.soil.treat(\.aeratedHours, hours: Tuning.aerateHours, at: point, radius: Tuning.treatRadius)
    }

    /// Seasol: costs `Tuning.seasolCost` carrots. Returns false (and charges nothing) when the point is off the bed,
    /// the soil there is already treated or the carrots are short.
    @discardableResult
    public static func applySeasol(at point: GroundPoint, in g: inout Garden) -> Bool {
        applyFeed(\.seasolHours, hours: Tuning.seasolHours, cost: Tuning.seasolCost, at: point, in: &g)
    }

    /// Fertiliser: costs `Tuning.fertiliserCost` carrots. Same rules as Seasol.
    @discardableResult
    public static func applyFertiliser(at point: GroundPoint, in g: inout Garden) -> Bool {
        applyFeed(\.fertiliserHours, hours: Tuning.fertiliserHours, cost: Tuning.fertiliserCost, at: point, in: &g)
    }

    private static func applyFeed(_ treatment: WritableKeyPath<SoilField, [Int]>, hours: Int, cost: Int,
                                  at point: GroundPoint, in g: inout Garden) -> Bool {
        guard g.plot.contains(point), g.coins >= cost else { return false }
        guard g.soil.treat(treatment, hours: hours, at: point, radius: Tuning.treatRadius) else { return false }
        g.coins -= cost
        return true
    }

    /// The weed tool: pulls the weed nearest to `point` if one is within `reach`. When no weed is in reach, a
    /// withered (dead) plant there is cleared instead. Returns false when neither is in reach.
    @discardableResult
    public static func pullWeed(at point: GroundPoint, in g: inout Garden,
                                reach: Double = Tuning.pullReach) -> Bool {
        if let i = nearestIndex(in: g.weeds.map(\.position), to: point, reach: reach) {
            g.weeds.remove(at: i)
            return true
        }
        let withered = g.plants.indices.filter { g.plants[$0].isDead }
        if let k = nearestIndex(in: withered.map { g.plants[$0].position }, to: point, reach: reach) {
            g.plants.remove(at: withered[k])
            return true
        }
        return false
    }

    /// Picks the blooming plant nearest to `point` if one is within `reach`. Carrots go to the player and the
    /// plant is removed, so it never self-sows. Only blooming plants can be picked.
    public static func harvest(at point: GroundPoint, in g: inout Garden,
                               reach: Double = Tuning.harvestReach) -> FlowerType? {
        let eligible = g.plants.indices.filter { !g.plants[$0].isDead && g.plants[$0].lifeStage == .blooming }
        guard let k = nearestIndex(in: eligible.map { g.plants[$0].position }, to: point, reach: reach) else { return nil }
        let i = eligible[k]
        let flower = g.plants[i].flower
        g.coins += flower.sellValue
        g.plants.remove(at: i)
        return flower
    }

    /// Spotting a visitor pays its carrot reward and counts as a sighting. `isNewEntry` is true the first time
    /// that species is ever spotted (the collection book's "New entry" moment).
    public static func spot(_ visitor: Visitor, in g: inout Garden) -> (coins: Int, isNewEntry: Bool) {
        let before = g.sightingCount(visitor.species)
        g.sightings[visitor.species.rawValue] = before + 1
        let coins = visitor.species.coinReward
        g.coins += coins
        return (coins, before == 0)
    }

    /// How many different visitor species have been spotted at least once.
    public static func spottedSpeciesCount(in g: Garden) -> Int {
        VisitorSpecies.allCases.filter { g.sightingCount($0) > 0 }.count
    }

    /// Milestones that are reached and not yet claimed, in book order.
    public static func claimableMilestones(in g: Garden) -> [VisitorMilestone] {
        let spotted = spottedSpeciesCount(in: g)
        return VisitorMilestone.all.filter { spotted >= $0.species && !g.claimedMilestones.contains($0.species) }
    }

    /// Pays a milestone's coins and seeds and records it as claimed. Returns false and changes nothing when the
    /// milestone is not reached or was already claimed.
    public static func claimMilestone(_ milestone: VisitorMilestone, in g: inout Garden) -> Bool {
        guard claimableMilestones(in: g).contains(milestone) else { return false }
        g.coins += milestone.coins
        for (flower, count) in milestone.seeds {
            g.seedStock[flower.rawValue] = g.seedCount(flower) + count
        }
        g.claimedMilestones.append(milestone.species)
        return true
    }

    /// The living plant nearest to `point` within `reach`, if any.
    public static func nearestPlant(to point: GroundPoint, in g: Garden, reach: Double) -> Plant? {
        let living = g.plants.filter { !$0.isDead }
        guard let i = nearestIndex(in: living.map(\.position), to: point, reach: reach) else { return nil }
        return living[i]
    }
}
