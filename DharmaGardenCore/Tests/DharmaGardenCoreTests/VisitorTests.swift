import XCTest
@testable import DharmaGardenCore

final class VisitorTests: XCTestCase {
    typealias F = GardenFixture

    /// A warm, dry, calm summer day with `blooms` flowers in bloom.
    func day(_ blooms: Int = 0, temp: Double = 22) -> VisitorContext {
        VisitorContext(season: .summer, isDay: true, temperatureC: temp, isRaining: false, recentlyRained: false,
                       windKmh: 5, bloomingPlants: Array(repeating: .daisy, count: blooms))
    }

    /// A mild, dry, calm summer night with `blooms` flowers in bloom.
    func night(_ blooms: Int = 0, temp: Double = 16) -> VisitorContext {
        var c = day(blooms, temp: temp)
        c.isDay = false
        return c
    }

    func weight(_ s: VisitorSpecies, _ c: VisitorContext) -> Double { VisitorRules.weight(of: s, in: c) }

    /// A garden with one blooming daisy at the centre and nothing else.
    func bloomingGarden() -> Garden {
        F.garden([F.plant(.daisy, id: 1, progress: 1)])
    }

    // MARK: Species data

    func testTwelveSpeciesWithFilledInText() {
        XCTAssertEqual(VisitorSpecies.allCases.count, 12)
        XCTAssertEqual(Set(VisitorSpecies.allCases.map(\.displayName)).count, 12)
        for s in VisitorSpecies.allCases {
            XCTAssertFalse(s.displayName.isEmpty, "\(s)")
            XCTAssertFalse(s.blurb.isEmpty, "\(s)")
            XCTAssertFalse(s.hint.isEmpty, "\(s)")
        }
    }

    func testRewardsFollowRarity() {
        XCTAssertEqual(VisitorSpecies.bee.rarity, .common)
        XCTAssertEqual(VisitorSpecies.bee.coinReward, 1)
        XCTAssertEqual(VisitorSpecies.frog.rarity, .uncommon)
        XCTAssertEqual(VisitorSpecies.frog.coinReward, 3)
        XCTAssertEqual(VisitorSpecies.cockatoo.rarity, .rare)
        XCTAssertEqual(VisitorSpecies.cockatoo.coinReward, 8)
        XCTAssertEqual(Tuning.visitorCommonReward, 1)
        XCTAssertEqual(Tuning.visitorUncommonReward, 3)
        XCTAssertEqual(Tuning.visitorRareReward, 8)
    }

    func testSpeciesEncodeAsTheirRawName() throws {
        let data = try JSONEncoder().encode(VisitorSpecies.cabbageWhiteButterfly)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"cabbageWhiteButterfly\"")
    }

    // MARK: Weights per condition

    func testBeesNeedWarmDayAndTwoBlooms() {
        XCTAssertEqual(weight(.bee, day(0)), 0)
        XCTAssertEqual(weight(.bee, day(1)), 0, "one bloom is not enough")
        XCTAssertGreaterThan(weight(.bee, day(2)), 0)
        XCTAssertEqual(weight(.bee, night(2)), 0, "no bees at night")
        XCTAssertEqual(weight(.bee, day(2, temp: 10)), 0, "too cold")
        var rainy = day(2)
        rainy.isRaining = true
        XCTAssertEqual(weight(.bee, rainy), 0, "no bees in the rain")
    }

    func testMoreBloomsMeansMoreBees() {
        XCTAssertGreaterThan(weight(.bee, day(6)), weight(.bee, day(2)))
    }

    func testWinterKeepsInsectsAndReptilesAway() {
        var winter = day(3, temp: 20)
        winter.season = .winter
        XCTAssertEqual(weight(.bee, winter), 0)
        XCTAssertEqual(weight(.cabbageWhiteButterfly, winter), 0)
        XCTAssertEqual(weight(.dragonfly, winter), 0)
        XCTAssertEqual(weight(.blueTongueLizard, winter), 0)
        XCTAssertGreaterThan(weight(.magpieLark, winter), 0, "birds stay all year")
    }

    func testRainKeepsFliersAndBirdsIndoorsButBringsSnails() {
        var rainy = day(3)
        rainy.isRaining = true
        rainy.recentlyRained = true
        XCTAssertEqual(weight(.bee, rainy), 0)
        XCTAssertEqual(weight(.magpieLark, rainy), 0)
        XCTAssertGreaterThan(weight(.snail, rainy), 0)
    }

    func testSnailsOnlyAppearAfterRain() {
        XCTAssertEqual(weight(.snail, day()), 0)
        var wet = day()
        wet.recentlyRained = true
        XCTAssertGreaterThan(weight(.snail, wet), 0)
    }

    func testFrogsNeedAWetNight() {
        var wetNight = night()
        wetNight.recentlyRained = true
        XCTAssertGreaterThan(weight(.frog, wetNight), 0)

        var wetDay = day()
        wetDay.recentlyRained = true
        XCTAssertEqual(weight(.frog, wetDay), 0, "frogs wait for night")
        XCTAssertEqual(weight(.frog, night()), 0, "no frogs without rain")
    }

    func testMothsOnlyComeOutAtNightToFlowers() {
        XCTAssertGreaterThan(weight(.moth, night(1)), 0)
        XCTAssertEqual(weight(.moth, night(0)), 0)
        XCTAssertEqual(weight(.moth, day(3)), 0)
    }

    func testLizardNeedsHeat() {
        XCTAssertEqual(weight(.blueTongueLizard, day(0, temp: 18)), 0)
        XCTAssertGreaterThan(weight(.blueTongueLizard, day(0, temp: 25)), 0)
    }

    func testWindKeepsFliersAway() {
        var windy = day(3)
        windy.windKmh = 30
        XCTAssertEqual(weight(.bee, windy), 0)
        XCTAssertEqual(weight(.dragonfly, windy), 0)
        XCTAssertGreaterThan(weight(.magpieLark, windy), 0, "birds ignore the wind here")
    }

    func testWeightsListEverySpeciesInOrder() {
        let list = VisitorRules.weights(in: day(2))
        XCTAssertEqual(list.map(\.species), VisitorSpecies.allCases)
    }

    // MARK: Context from the garden and weather

    func testBloomingCountsOnlyLivingBloomingPlants() {
        let g = F.garden([
            F.plant(.daisy, id: 1, progress: 1),
            F.plant(.lettuce, id: 2, at: GroundPoint(x: 0.3, y: 0.3), progress: 0.5),
            { var dead = F.plant(.poppy, id: 3, at: GroundPoint(x: 0.7, y: 0.3), progress: 1); dead.isDead = true; return dead }(),
        ])
        XCTAssertEqual(VisitorContext.blooming(in: g), [.daisy])
    }

    func testContextReadsCurrentRainAndRecentRainFromTheReport() {
        let now = F.t0
        let current = CurrentConditions(temperatureC: 15, apparentTemperatureC: 14, precipitationMM: 0, windKmh: 8,
                                        cloudCover: 40, isDay: false, condition: .clear)
        let hourly = [
            WeatherSample(date: now.addingTimeInterval(-2 * 3600), temperatureC: 15, precipitationMM: 1),
            WeatherSample(date: now.addingTimeInterval(-5 * 3600), temperatureC: 15, precipitationMM: 4),
        ]
        let report = WeatherReport(current: current, hourly: hourly, sunrise: now, sunset: now, fetchedAt: now,
                                   latitude: -33.8, longitude: 151.2)
        let c = VisitorContext.make(report: report, garden: bloomingGarden(), now: now)
        XCTAssertFalse(c.isRaining)
        XCTAssertTrue(c.recentlyRained, "rain two hours ago counts")
        XCTAssertFalse(c.isDay)
        XCTAssertEqual(c.temperatureC, 15)
        XCTAssertEqual(c.windKmh, 8)
        XCTAssertEqual(c.season, SeasonProvider.season(on: now, latitude: -33.8))
        XCTAssertEqual(c.bloomingPlants, [.daisy])
    }

    func testOldRainIsNotRecent() {
        let now = F.t0
        let current = CurrentConditions(temperatureC: 15, apparentTemperatureC: 14, precipitationMM: 0, windKmh: 8,
                                        cloudCover: 40, isDay: true, condition: .clear)
        let hourly = [WeatherSample(date: now.addingTimeInterval(-5 * 3600), temperatureC: 15, precipitationMM: 4)]
        let report = WeatherReport(current: current, hourly: hourly, sunrise: now, sunset: now, fetchedAt: now,
                                   latitude: 51, longitude: 0)
        XCTAssertFalse(VisitorContext.make(report: report, garden: Garden(now: now), now: now).recentlyRained)
    }

    // MARK: Spawner

    func testNothingSpawnsWhenTheGardenIsFull() {
        let g = bloomingGarden()
        for i in 0..<300 {
            let seed = DeterministicHash.mix(UInt64(i))
            XCTAssertNil(VisitorSpawner.roll(garden: g, context: day(3), now: F.t0, liveCount: Tuning.maxVisitors, seed: seed))
            XCTAssertNil(VisitorSpawner.roll(garden: g, context: day(3), now: F.t0, liveCount: Tuning.maxVisitors + 1, seed: seed))
        }
    }

    func testOneFreeSlotStillLetsVisitorsIn() {
        XCTAssertEqual(Tuning.maxVisitors, 3)
        let g = bloomingGarden()
        var spawned = 0
        for i in 0..<300 {
            let seed = DeterministicHash.mix(UInt64(i))
            if VisitorSpawner.roll(garden: g, context: day(3), now: F.t0, liveCount: 2, seed: seed) != nil { spawned += 1 }
        }
        XCTAssertGreaterThan(spawned, 0, "one slot free still lets visitors in")
    }

    func testNoVisitorWhenNothingCanComeOut() {
        var deadOfWinter = night(0)
        deadOfWinter.season = .winter
        let g = Garden(now: F.t0)
        for i in 0..<300 {
            let seed = DeterministicHash.mix(UInt64(i))
            XCTAssertNil(VisitorSpawner.roll(garden: g, context: deadOfWinter, now: F.t0, liveCount: 0, seed: seed))
        }
    }

    func testRollIsDeterministic() {
        let g = bloomingGarden()
        for i in 0..<100 {
            let seed = DeterministicHash.mix(UInt64(i))
            let a = VisitorSpawner.roll(garden: g, context: day(2), now: F.t0, liveCount: 0, seed: seed)
            let b = VisitorSpawner.roll(garden: g, context: day(2), now: F.t0, liveCount: 0, seed: seed)
            XCTAssertEqual(a, b, "seed \(i)")
        }
    }

    func testArrivalRateMatchesTheChance() {
        let g = bloomingGarden()
        let trials = 4000
        var arrived = 0
        for i in 0..<trials {
            if VisitorSpawner.roll(garden: g, context: day(2), now: F.t0, liveCount: 0,
                                   seed: DeterministicHash.mix(UInt64(i))) != nil { arrived += 1 }
        }
        let rate = Double(arrived) / Double(trials)
        XCTAssertEqual(rate, Tuning.visitorArrivalChance, accuracy: 0.04)
    }

    func testVariedDayBringsVariedSpecies() {
        let g = bloomingGarden()
        var seen = Set<VisitorSpecies>()
        for i in 0..<2000 {
            if let v = VisitorSpawner.roll(garden: g, context: day(2), now: F.t0, liveCount: 0,
                                           seed: DeterministicHash.mix(UInt64(i))) {
                seen.insert(v.species)
            }
        }
        XCTAssertGreaterThanOrEqual(seen.count, 5)
        XCTAssertFalse(seen.contains(.moth), "no moths by day")
    }

    func testVisitorsHaveSensibleTimingAndPlace() {
        let g = bloomingGarden()
        var count = 0
        for i in 0..<500 {
            guard let v = VisitorSpawner.roll(garden: g, context: day(2), now: F.t0, liveCount: 0,
                                              seed: DeterministicHash.mix(UInt64(i))) else { continue }
            count += 1
            XCTAssertEqual(v.spawnedAt, F.t0)
            XCTAssertGreaterThanOrEqual(v.lifetime, Tuning.visitorMinLifetimeSeconds)
            XCTAssertLessThanOrEqual(v.lifetime, Tuning.visitorMaxLifetimeSeconds)
            XCTAssertEqual(v.departsAt, F.t0.addingTimeInterval(v.lifetime))
            XCTAssertFalse(v.isGone(at: F.t0))
            XCTAssertTrue(v.isGone(at: v.departsAt))
            XCTAssertTrue(g.plot.contains(v.position), "seed \(i)")
        }
        XCTAssertGreaterThan(count, 0)
    }

    func testFlowerVisitorsLandNearABloom() {
        let bloom = GroundPoint(x: 0.3, y: 0.6)
        let g = F.garden([F.plant(.daisy, id: 1, at: bloom, progress: 1)])
        var flowerVisitors = 0
        for i in 0..<800 {
            guard let v = VisitorSpawner.roll(garden: g, context: day(1), now: F.t0, liveCount: 0,
                                              seed: DeterministicHash.mix(UInt64(i))),
                  v.species.visitsFlowers else { continue }
            flowerVisitors += 1
            XCTAssertLessThanOrEqual(v.position.distance(to: bloom), Tuning.visitorPerchRadius + 1e-9)
        }
        XCTAssertGreaterThan(flowerVisitors, 0)
    }

    // MARK: Spotting

    func testSpotPaysCoinsAndCountsSightings() {
        var g = F.garden([])
        g.coins = 10
        let cockatoo = Visitor(id: 1, species: .cockatoo, position: F.centre, spawnedAt: F.t0, lifetime: 30)

        let first = GardenEngine.spot(cockatoo, in: &g)
        XCTAssertEqual(first.coins, 8)
        XCTAssertTrue(first.isNewEntry)
        XCTAssertEqual(g.coins, 18)
        XCTAssertEqual(g.sightingCount(.cockatoo), 1)

        let second = GardenEngine.spot(cockatoo, in: &g)
        XCTAssertEqual(second.coins, 8)
        XCTAssertFalse(second.isNewEntry, "only the first spot is a new entry")
        XCTAssertEqual(g.coins, 26)
        XCTAssertEqual(g.sightingCount(.cockatoo), 2)

        let bee = Visitor(id: 2, species: .bee, position: F.centre, spawnedAt: F.t0, lifetime: 30)
        XCTAssertEqual(GardenEngine.spot(bee, in: &g).coins, 1)
        XCTAssertEqual(g.sightingCount(.bee), 1)
        XCTAssertEqual(g.sightingCount(.cockatoo), 2, "other species are unchanged")
    }

    // MARK: Save format

    func testSightingsRoundTrip() throws {
        var g = F.garden([])
        g.sightings = [VisitorSpecies.frog.rawValue: 4]
        let back = try JSONDecoder().decode(Garden.self, from: JSONEncoder().encode(g))
        XCTAssertEqual(back, g)
        XCTAssertEqual(back.sightingCount(.frog), 4)
        XCTAssertEqual(back.sightingCount(.bee), 0)
    }

    func testVersionFourSaveLoadsWithEmptySightings() throws {
        var g = F.garden([F.plant(.lavender, id: 3, at: GroundPoint(x: 0.3, y: 0.6), progress: 0.4)], soil: 42)
        g.coins = 77
        g.weeds = [Weed(id: 77, position: GroundPoint(x: 0.7, y: 0.4), ageHours: 12)]
        let data = try JSONEncoder().encode(g)
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        obj["version"] = 4
        obj.removeValue(forKey: "sightings")
        let v4 = try JSONSerialization.data(withJSONObject: obj)

        let loaded = try XCTUnwrap(Garden.decodeSave(v4))
        XCTAssertEqual(loaded.version, Garden.currentVersion)
        XCTAssertEqual(loaded.plants, g.plants)
        XCTAssertEqual(loaded.weeds, g.weeds)
        XCTAssertEqual(loaded.soil, g.soil)
        XCTAssertEqual(loaded.coins, 77)
        XCTAssertEqual(loaded.sightings, [:])
        XCTAssertEqual(loaded.sightingCount(.bee), 0)
    }

    func testCurrentSaveKeepsSightings() throws {
        var g = F.garden([])
        g.sightings = [VisitorSpecies.bee.rawValue: 5]
        let loaded = try XCTUnwrap(Garden.decodeSave(try JSONEncoder().encode(g)))
        XCTAssertEqual(loaded.sightingCount(.bee), 5)
    }

    func testOtherVersionsAreDiscarded() throws {
        let data = try JSONEncoder().encode(F.garden([]))
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for version in [1, 3, 6] {
            obj["version"] = version
            let bytes = try JSONSerialization.data(withJSONObject: obj)
            XCTAssertNil(Garden.decodeSave(bytes), "version \(version) should start fresh")
        }
    }
}
