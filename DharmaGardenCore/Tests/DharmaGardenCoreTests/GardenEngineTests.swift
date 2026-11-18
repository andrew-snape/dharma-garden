import XCTest
@testable import DharmaGardenCore

final class GardenEngineTests: XCTestCase {
    typealias F = GardenFixture

    /// Plant with the given id from the garden, by id.
    func plant(_ g: Garden, _ id: Int) -> Plant? { g.plants.first { $0.id == id } }

    /// A varied week-by-week weather pattern: rain every seventh hour, day and night, warm and cool.
    func varied(hours n: Int) -> [WeatherSample] {
        (1...n).map { h in
            WeatherSample(date: F.at(hours: h), temperatureC: 6 + Double(h % 24) * 0.9,
                          precipitationMM: h % 7 == 0 ? 2 : 0, windKmh: Double(h % 50),
                          cloudCover: 0, isDay: (7..<19).contains(h % 24))
        }
    }

    // MARK: Determinism and time

    func testAdvanceIsDeterministic() {
        let start = F.garden([F.plant(.daisy, id: 1, at: GroundPoint(x: 0.3, y: 0.4))], soil: 30)
        let a = GardenEngine.advance(start, weather: varied(hours: 24 * 60), to: F.at(hours: 24 * 60))
        let b = GardenEngine.advance(start, weather: varied(hours: 24 * 60), to: F.at(hours: 24 * 60))
        XCTAssertEqual(a, b)
    }

    func testSplitAdvanceMatchesOneAdvance() {
        var base = Garden(now: F.t0)
        _ = GardenEngine.plant(.daisy, at: F.centre, in: &base)
        let weather = varied(hours: 24 * 40)
        let once = GardenEngine.advance(base, weather: weather, to: F.at(hours: 24 * 40))
        let first = GardenEngine.advance(base, weather: weather, to: F.at(hours: 24 * 17))
        let twice = GardenEngine.advance(first, weather: weather, to: F.at(hours: 24 * 40))
        XCTAssertEqual(once, twice)
    }

    func testTimeNeverRunsBackwards() {
        let g = F.garden([F.plant(.daisy, id: 1, progress: 0.5)])
        XCTAssertEqual(GardenEngine.advance(g, weather: [], to: F.at(hours: -10)), g)
    }

    func testAdvanceIsFastEnoughForSixtyPlants() {
        var g = Garden(now: F.t0)
        g.soil = SoilField(fill: 100)
        var placed = 0
        for row in 0..<20 where placed < Tuning.maxPlants {
            for col in 0..<20 where placed < Tuning.maxPlants {
                let p = GroundPoint(x: 0.1 + Double(col) * 0.045, y: 0.1 + Double(row) * 0.045)
                if GardenEngine.plant(FlowerType.allCases[placed % 11], at: p, in: &g) { placed += 1 }
            }
        }
        XCTAssertEqual(g.plants.count, Tuning.maxPlants)
        let weather = (1...(120 * 24)).map {
            WeatherSample(date: F.at(hours: $0), temperatureC: 18, precipitationMM: 1, isDay: true)
        }
        let started = Date()
        let after = GardenEngine.advance(g, weather: weather, to: F.at(hours: 120 * 24))
        let seconds = Date().timeIntervalSince(started)
        // Generous: a debug build on a busy machine takes about 1 s; this only has to catch a real regression.
        XCTAssertLessThan(seconds, 4, "120 days with 60 plants took \(seconds) s")
        XCTAssertEqual(after.lastSimulatedAt, F.at(hours: 120 * 24))
    }

    // MARK: Durations and life cycle

    func testWateredDaisyBloomsAfterAboutFortyNineDays() {
        let g = F.garden([F.plant(.daisy, id: 1)])
        let day48 = F.advance(g, hours: 48 * 24, rain: 1)
        XCTAssertLessThan(plant(day48, 1)!.progress, 1)
        XCTAssertEqual(plant(day48, 1)!.stage, .bud)
        let day50 = F.advance(g, hours: 50 * 24, rain: 1)
        XCTAssertEqual(plant(day50, 1)!.lifeStage, .blooming)
        XCTAssertEqual(plant(day50, 1)!.progress, 1)
    }

    // MARK: Garden speed

    /// The first hour (counting from the start) at which the lone daisy is in bloom at the given speed.
    func bloomHour(speed: Double) -> Int {
        let g = F.garden([F.plant(.daisy, id: 1)])
        let weather = F.weather(hours: 50 * 24, rain: 1)
        var lo = 1, hi = 50 * 24
        while lo < hi {
            let mid = (lo + hi) / 2
            let out = GardenEngine.advance(g, weather: weather, to: F.at(hours: mid), speed: speed)
            // A plant that has bloomed and gone to seed is no longer there, which also counts as past bloom.
            if (plant(out, 1)?.progress ?? 1) >= 1 { hi = mid } else { lo = mid + 1 }
        }
        return lo
    }

    func testSpeedMultipliesGrowth() {
        let one = Double(bloomHour(speed: 1))
        XCTAssertEqual(one, 49 * 24, accuracy: 2)
        XCTAssertEqual(Double(bloomHour(speed: 2)), one / 2, accuracy: 2)
        XCTAssertEqual(Double(bloomHour(speed: 4)), one / 4, accuracy: 2)
    }

    func testSpeedOneMatchesDefaultAdvance() {
        let start = F.garden([F.plant(.daisy, id: 1), F.plant(.lavender, id: 2, at: GroundPoint(x: 0.7, y: 0.6))])
        let weather = varied(hours: 24 * 30)
        XCTAssertEqual(GardenEngine.advance(start, weather: weather, to: F.at(hours: 24 * 30), speed: 1),
                       GardenEngine.advance(start, weather: weather, to: F.at(hours: 24 * 30)))
    }

    func testSpeedAgesWeedsAndDriesSoilFaster() {
        var start = F.garden([], soil: 100)
        start.weeds = []
        let weather = F.weather(hours: 24 * 3)
        let slow = GardenEngine.advance(start, weather: weather, to: F.at(hours: 24 * 3))
        let fast = GardenEngine.advance(start, weather: weather, to: F.at(hours: 24 * 3), speed: 4)
        XCTAssertGreaterThan(fast.weeds.count, slow.weeds.count)
        XCTAssertGreaterThan(fast.weeds.map(\.ageHours).max() ?? 0, slow.weeds.map(\.ageHours).max() ?? 0)
        XCTAssertLessThan(fast.soil.values.reduce(0, +), slow.soil.values.reduce(0, +))
        XCTAssertEqual(fast.lastSimulatedAt, slow.lastSimulatedAt, "the clock stays real")
    }

    func testLifeCycleBloomFadeSeedHeadThenGone() {
        let bloomed = F.garden([F.plant(.daisy, id: 1, progress: 1)])
        XCTAssertEqual(plant(F.advance(bloomed, hours: 9 * 24, rain: 1), 1)?.lifeStage, .blooming)
        XCTAssertEqual(plant(F.advance(bloomed, hours: 10 * 24, rain: 1), 1)?.lifeStage, .fading)
        XCTAssertEqual(plant(F.advance(bloomed, hours: 17 * 24, rain: 1), 1)?.lifeStage, .seedHead)
        XCTAssertNotNil(plant(F.advance(bloomed, hours: 20 * 24 - 1, rain: 1), 1))
        XCTAssertNil(plant(F.advance(bloomed, hours: 20 * 24, rain: 1), 1), "the seed head drops after 20 days")
    }

    func testBloomingFlowerAgesWithoutWater() {
        // Once in bloom the clock runs even when the soil is dry.
        let bloomed = F.garden([F.plant(.lavender, id: 1, progress: 1)], soil: 0)
        let g = F.advance(bloomed, hours: 24)
        XCTAssertEqual(plant(g, 1)?.bloomHoursElapsed, 24)
    }

    // MARK: Moisture, wilting and death

    func testSoilDrainsAndRainRefills() {
        let dry = F.garden([], soil: 0)
        let rained = GardenEngine.advance(dry, weather: [WeatherSample(date: F.at(hours: 1), temperatureC: 18, precipitationMM: 5)], to: F.at(hours: 1))
        XCTAssertEqual(rained.soil.values.first ?? -1, 49, accuracy: 1e-9)

        let wet = F.garden([], soil: 100)
        let hot = F.advance(wet, hours: 10, temp: 31)
        XCTAssertEqual(hot.soil.values[SoilField.rows * SoilField.columns / 2], 80, accuracy: 1e-9, "heat doubles drain")
        let windy = F.advance(wet, hours: 10, wind: 40)
        XCTAssertEqual(windy.soil.values[0], 87, accuracy: 1e-9, "wind multiplies drain by 1.3")
    }

    func testDryTolerantAndThirstyPlantsChangeDrainInTheirCell() {
        let cell = SoilField.cellCentre(column: 14, row: 9)
        func moisture(_ f: FlowerType) -> Double {
            let g = F.advance(F.garden([F.plant(f, id: 1, at: cell)]), hours: 10)
            return plant(g, 1)!.moisture
        }
        XCTAssertEqual(moisture(.daisy), 90, accuracy: 1e-6)
        XCTAssertEqual(moisture(.zucchini), 88, accuracy: 1e-6, "zucchini is thirsty")
        XCTAssertEqual(moisture(.lavender), 93, accuracy: 1e-6, "lavender is dry-tolerant")
    }

    func testWiltAndDeathAfterDryHours() {
        let dry = F.garden([F.plant(.daisy, id: 1)], soil: 0)
        let before = plant(F.advance(dry, hours: 47), 1)!
        XCTAssertEqual(before.dryHours, 47)
        XCTAssertFalse(before.isWilted)
        let wilted = plant(F.advance(dry, hours: 48), 1)!
        XCTAssertTrue(wilted.isWilted)
        XCTAssertFalse(wilted.isDead)
        XCTAssertEqual(wilted.droop(moisture: wilted.moisture), 1)
        XCTAssertTrue(plant(F.advance(dry, hours: 96), 1)!.isDead)
    }

    func testPlantRecoversWhenRainArrivesBeforeDeath() {
        var weather = F.weather(hours: 60)
        weather.append(WeatherSample(date: F.at(hours: 61), temperatureC: 18, precipitationMM: 1))
        let g = GardenEngine.advance(F.garden([F.plant(.daisy, id: 1)], soil: 0), weather: weather, to: F.at(hours: 61))
        let p = plant(g, 1)!
        XCTAssertFalse(p.isWilted)
        XCTAssertFalse(p.isDead)
        XCTAssertEqual(p.dryHours, 0)
    }

    func testGrowthPausesBelowTwentyMoisture() {
        let thirsty = F.advance(F.garden([F.plant(.daisy, id: 1)], soil: 15), hours: 10)
        XCTAssertEqual(plant(thirsty, 1)!.progress, 0)
        let watered = F.advance(F.garden([F.plant(.daisy, id: 1)], soil: 100), hours: 10)
        XCTAssertGreaterThan(plant(watered, 1)!.progress, 0)
    }

    // MARK: Temperature rules

    func testFrostSlowsFrostTenderPlantsHalfButNotTolerantOnes() {
        let mild = F.advance(F.garden([F.plant(.poppy, id: 1)]), hours: 24, temp: 10, rain: 1, isDay: false)
        let frost = F.advance(F.garden([F.plant(.poppy, id: 1)]), hours: 24, temp: -3, rain: 1, isDay: false)
        XCTAssertNotNil(plant(frost, 1)!.frostUntil)
        XCTAssertEqual(plant(frost, 1)!.progress / plant(mild, 1)!.progress, 0.5, accuracy: 1e-9)

        let hardyMild = F.advance(F.garden([F.plant(.calendula, id: 1)]), hours: 24, temp: 10, rain: 1, isDay: false)
        let hardyFrost = F.advance(F.garden([F.plant(.calendula, id: 1)]), hours: 24, temp: -3, rain: 1, isDay: false)
        XCTAssertEqual(plant(hardyFrost, 1)!.progress, plant(hardyMild, 1)!.progress, accuracy: 1e-12)
        XCTAssertNil(plant(hardyFrost, 1)!.frostUntil)
    }

    func testFrostNeedsNightAndCold() {
        let day = F.advance(F.garden([F.plant(.poppy, id: 1)]), hours: 24, temp: -3, rain: 1, isDay: true)
        XCTAssertNil(plant(day, 1)!.frostUntil)
    }

    func testSunflowerLovesHeatAndDislikesCold() {
        let base = plant(F.advance(F.garden([F.plant(.sunflower, id: 1)]), hours: 240, temp: 18, rain: 1), 1)!.progress
        let hot = plant(F.advance(F.garden([F.plant(.sunflower, id: 1)]), hours: 240, temp: 28, rain: 1), 1)!.progress
        let cold = plant(F.advance(F.garden([F.plant(.sunflower, id: 1)]), hours: 240, temp: 5, rain: 1), 1)!.progress
        XCTAssertEqual(hot / base, 1.15, accuracy: 1e-9)
        XCTAssertEqual(cold / base, 0.6, accuracy: 1e-9)
    }

    func testLettuceBoltsInHeatAndLikesCool() {
        let base = plant(F.advance(F.garden([F.plant(.lettuce, id: 1)]), hours: 240, temp: 18, rain: 1), 1)!.progress
        let bolting = plant(F.advance(F.garden([F.plant(.lettuce, id: 1)]), hours: 240, temp: 30, rain: 1), 1)!.progress
        let cool = plant(F.advance(F.garden([F.plant(.lettuce, id: 1)]), hours: 240, temp: 10, rain: 1), 1)!.progress
        XCTAssertEqual(bolting / base, 0.4, accuracy: 1e-9)
        XCTAssertEqual(cool / base, 1.1, accuracy: 1e-9)
    }

    // MARK: Crowding and weeds

    func testCrowdingSlowsGrowthCappedAtAQuarter() {
        let target = F.plant(.daisy, id: 1)
        let ring: [Plant] = (0..<8).map { k in
            let a = Double(k) * Double.pi / 4
            return F.plant(.daisy, id: 2 + k, at: GroundPoint(x: 0.5 + cos(a) * 0.05, y: 0.5 + sin(a) * 0.05))
        }
        let alone = plant(F.advance(F.garden([target]), hours: 240, rain: 1), 1)!.progress
        let one = plant(F.advance(F.garden([target, ring[0]]), hours: 240, rain: 1), 1)!.progress
        let crowded = plant(F.advance(F.garden([target] + ring), hours: 240, rain: 1), 1)!.progress
        XCTAssertEqual(one / alone, 0.94, accuracy: 1e-9)
        XCTAssertEqual(crowded / alone, 0.75, accuracy: 1e-9, "crowding never takes more than 25 percent")
    }

    func testFarNeighboursDoNotCrowd() {
        let near = F.plant(.daisy, id: 1)
        let far = F.plant(.daisy, id: 2, at: GroundPoint(x: 0.1, y: 0.1))
        let alone = plant(F.advance(F.garden([near]), hours: 240, rain: 1), 1)!.progress
        let together = plant(F.advance(F.garden([near, far]), hours: 240, rain: 1), 1)!.progress
        XCTAssertEqual(together, alone, accuracy: 1e-12)
    }

    func testDharmaGardenSlowNearbyPlantsAndTheSlowdownIsCapped() {
        let base = plant(F.advance(F.garden([F.plant(.daisy, id: 1)]), hours: 240, rain: 1), 1)!.progress

        var young = F.garden([F.plant(.daisy, id: 1)])
        young.weeds += [Weed(id: 50, position: GroundPoint(x: 0.52, y: 0.5))]
        let youngProgress = plant(F.advance(young, hours: 240, rain: 1), 1)!.progress
        XCTAssertLessThan(youngProgress, base)
        XCTAssertGreaterThan(youngProgress / base, 0.9)

        var old = F.garden([F.plant(.daisy, id: 1)])
        old.weeds += [Weed(id: 50, position: GroundPoint(x: 0.52, y: 0.5), ageHours: 1000)]
        let oldProgress = plant(F.advance(old, hours: 240, rain: 1), 1)!.progress
        XCTAssertLessThan(oldProgress, youngProgress, "older weeds slow more")

        var crowdedDharmaGarden = F.garden([F.plant(.daisy, id: 1)])
        crowdedDharmaGarden.weeds += (0..<5).map { k in
            Weed(id: 60 + k, position: GroundPoint(x: 0.5 + Double(k - 2) * 0.01, y: 0.5 + Double(k % 2) * 0.01),
                 ageHours: 1000)
        }
        let capped = plant(F.advance(crowdedDharmaGarden, hours: 240, rain: 1), 1)!.progress
        XCTAssertEqual(capped / base, 0.7, accuracy: 1e-9, "weed slowdown is capped at 30 percent")
    }

    func testDharmaGardenSpawnInsidePlotAndStopAtTheCap() {
        let g = F.advance(Garden(now: F.t0), hours: 30 * 24)
        XCTAssertFalse(g.weeds.isEmpty)
        XCTAssertLessThanOrEqual(g.weeds.count, Tuning.maxDharmaGarden)
        XCTAssertTrue(g.weeds.allSatisfy { g.plot.contains($0.position, inset: Tuning.weedSpawnInset) })
        XCTAssertTrue(g.weeds.allSatisfy { $0.ageHours > 0 })
        XCTAssertEqual(Set(g.weeds.map(\.id)).count, g.weeds.count, "weed ids are unique")
    }

    // MARK: Self-sowing

    func testSeedHeadScattersUpToThreeVolunteersNearTheParent() {
        let spots = [GroundPoint(x: 0.3, y: 0.3), GroundPoint(x: 0.7, y: 0.3),
                     GroundPoint(x: 0.3, y: 0.7), GroundPoint(x: 0.7, y: 0.7)]
        let parents = spots.enumerated().map { F.plant(.daisy, id: $0.offset + 1, at: $0.element, progress: 1) }
        let g = F.garden(parents)
        let done = F.advance(g, hours: Tuning.lifeCycleHours, rain: 1)
        XCTAssertEqual(done.plants.filter { $0.id <= 4 }.count, 0, "parents are gone after their seed heads")

        let volunteers = done.plants.filter { $0.id > 4 }
        XCTAssertGreaterThan(volunteers.count, 0)
        XCTAssertLessThanOrEqual(volunteers.count, 4 * Tuning.maxVolunteers)
        for v in volunteers {
            XCTAssertEqual(v.progress, 0, "volunteers start growing from the next hour")
            XCTAssertTrue(done.plot.contains(v.position, inset: Tuning.sowInset))
            XCTAssertTrue(spots.contains { $0.distance(to: v.position) <= Tuning.volunteerRadius + 1e-9 })
        }
        for (i, a) in volunteers.enumerated() {
            for b in volunteers[(i + 1)...] {
                XCTAssertGreaterThanOrEqual(a.position.distance(to: b.position), Tuning.volunteerSpacing - 1e-12)
            }
        }
    }

    func testSelfSowingIsDeterministic() {
        let g = F.garden([F.plant(.zucchini, id: 1, progress: 1)])
        let a = F.advance(g, hours: Tuning.lifeCycleHours + 24, rain: 1)
        let b = F.advance(g, hours: Tuning.lifeCycleHours + 24, rain: 1)
        XCTAssertEqual(a, b)
    }

    func testHarvestedPlantNeverSelfSows() {
        var g = F.garden([F.plant(.daisy, id: 1, progress: 1)])
        XCTAssertEqual(GardenEngine.harvest(at: F.centre, in: &g), .daisy)
        let later = F.advance(g, hours: 40 * 24)
        XCTAssertTrue(later.plants.isEmpty)
    }

    // MARK: Sowing, planting and the cap

    func testSowNeedsSeedInsidePlotAndSpacing() {
        var g = Garden(now: F.t0)
        XCTAssertFalse(GardenEngine.sow(.poppy, at: F.centre, in: &g), "no poppy seeds")
        XCTAssertFalse(GardenEngine.sow(.daisy, at: GroundPoint(x: 0.02, y: 0.02), in: &g), "outside the plot")
        XCTAssertEqual(g.seedCount(.daisy), 3)
        XCTAssertTrue(GardenEngine.sow(.daisy, at: F.centre, in: &g))
        XCTAssertEqual(g.seedCount(.daisy), 2)
        XCTAssertEqual(g.plants.count, 1)
        XCTAssertEqual(g.plants[0].position, F.centre)
        XCTAssertEqual(g.plants[0].progress, 0)
        XCTAssertFalse(GardenEngine.sow(.daisy, at: GroundPoint(x: 0.52, y: 0.5), in: &g), "on top of a plant")
        XCTAssertEqual(g.seedCount(.daisy), 2, "a refused sow keeps the seed")
        XCTAssertTrue(GardenEngine.sow(.daisy, at: GroundPoint(x: 0.55, y: 0.5), in: &g))
        XCTAssertEqual(g.seedCount(.daisy), 1)
        XCTAssertEqual(g.plants.count, 2)
    }

    func testPlantPrimitiveIsFreeAndFollowsPlacementRules() {
        var g = Garden(now: F.t0)
        XCTAssertTrue(GardenEngine.plant(.lettuce, at: F.centre, in: &g))
        XCTAssertEqual(g.seedStock, [FlowerType.daisy.rawValue: Tuning.startingDaisySeeds])
        XCTAssertFalse(GardenEngine.plant(.lettuce, at: GroundPoint(x: 0.52, y: 0.5), in: &g))
        XCTAssertFalse(GardenEngine.plant(.lettuce, at: GroundPoint(x: 0.01, y: 0.5), in: &g))
    }

    func testDeadPlantInTheWayIsReplaced() {
        var g = Garden(now: F.t0)
        g.nextID = 5
        var dead = Plant(id: 1, flower: .daisy, position: F.centre)
        dead.isDead = true
        g.plants = [dead]
        XCTAssertTrue(GardenEngine.plant(.lettuce, at: GroundPoint(x: 0.51, y: 0.5), in: &g))
        XCTAssertEqual(g.plants.map(\.flower), [.lettuce])
    }

    func testGardenHoldsAtMostSixtyLivingPlants() {
        var g = Garden(now: F.t0)
        var placed = 0
        for row in 0..<20 {
            for col in 0..<20 {
                let p = GroundPoint(x: 0.1 + Double(col) * 0.04, y: 0.1 + Double(row) * 0.04)
                if GardenEngine.plant(.daisy, at: p, in: &g) { placed += 1 }
            }
        }
        XCTAssertEqual(placed, Tuning.maxPlants)
        XCTAssertEqual(g.plants.filter { !$0.isDead }.count, Tuning.maxPlants)
    }

    func testBuySeedsRules() {
        var g = Garden(now: F.t0)
        XCTAssertFalse(GardenEngine.buySeeds(.daisy, count: 0, in: &g))
        XCTAssertEqual(g.coins, Tuning.startingCoins)
        XCTAssertFalse(GardenEngine.buySeeds(.sunflower, count: 100, in: &g), "not enough coins")
        XCTAssertEqual(g.coins, Tuning.startingCoins)
        let price = FlowerType.daisy.seedPrice
        XCTAssertTrue(GardenEngine.buySeeds(.daisy, count: 2, in: &g))
        XCTAssertEqual(g.coins, Tuning.startingCoins - 2 * price)
        XCTAssertEqual(g.seedCount(.daisy), Tuning.startingDaisySeeds + 2)
    }

    // MARK: Watering, weeds, harvest, nearest

    func testWaterIsSoftAndLocal() {
        var g = Garden(now: F.t0)
        GardenEngine.water(at: F.centre, in: &g)
        XCTAssertGreaterThan(g.soil.moisture(at: F.centre), 90)
        XCTAssertGreaterThan(g.soil.moisture(at: GroundPoint(x: 0.6, y: 0.5)), 50)
        XCTAssertLessThan(g.soil.moisture(at: GroundPoint(x: 0.6, y: 0.5)), g.soil.moisture(at: F.centre))
        XCTAssertEqual(g.soil.moisture(at: GroundPoint(x: 0.9, y: 0.6)), 50, accuracy: 1e-9)
    }

    func testWaterAddsTheFullAmountAtACellCentre() {
        var g = Garden(now: F.t0)
        g.soil = SoilField(fill: 0)
        let cell = SoilField.cellCentre(column: 14, row: 9)
        GardenEngine.water(at: cell, in: &g)
        XCTAssertEqual(g.soil.moisture(at: cell), Tuning.waterAmount, accuracy: 1e-6)
    }

    func testWaterRefreshesPlantSnapshots() {
        var g = Garden(now: F.t0)
        g.soil = SoilField(fill: 10)
        _ = GardenEngine.plant(.daisy, at: F.centre, in: &g)
        XCTAssertEqual(g.plants[0].moisture, 10, accuracy: 1e-9)
        GardenEngine.water(at: F.centre, in: &g, radius: 0.14, amount: 60)
        XCTAssertEqual(g.plants[0].moisture, g.soil.moisture(at: F.centre), accuracy: 1e-12)
        XCTAssertGreaterThan(g.plants[0].moisture, 50)
    }

    func testPullWeedRemovesTheNearestWithinReach() {
        var g = Garden(now: F.t0)
        g.weeds = [Weed(id: 1, position: F.centre), Weed(id: 2, position: GroundPoint(x: 0.6, y: 0.5))]
        XCTAssertFalse(GardenEngine.pullWeed(at: GroundPoint(x: 0.9, y: 0.9), in: &g))
        XCTAssertTrue(GardenEngine.pullWeed(at: GroundPoint(x: 0.52, y: 0.5), in: &g))
        XCTAssertEqual(g.weeds.map(\.id), [2])
        XCTAssertFalse(GardenEngine.pullWeed(at: GroundPoint(x: 0.52, y: 0.5), in: &g), "the other weed is out of reach")
    }

    func testHarvestOnlyTakesBloomingPlantsAndPaysCoins() {
        var g = F.garden([F.plant(.daisy, id: 1, progress: 0.5)])
        XCTAssertNil(GardenEngine.harvest(at: F.centre, in: &g), "still growing")
        g.plants = [F.plant(.daisy, id: 1, progress: 1)]
        XCTAssertNil(GardenEngine.harvest(at: GroundPoint(x: 0.8, y: 0.5), in: &g), "out of reach")
        XCTAssertEqual(GardenEngine.harvest(at: GroundPoint(x: 0.53, y: 0.5), in: &g), .daisy)
        XCTAssertEqual(g.coins, Tuning.startingCoins + FlowerType.daisy.sellValue)
        XCTAssertTrue(g.plants.isEmpty)
    }

    func testHarvestPicksTheNearestBloomingPlant() {
        var g = F.garden([F.plant(.daisy, id: 1, at: F.centre, progress: 1),
                          F.plant(.lettuce, id: 2, at: GroundPoint(x: 0.6, y: 0.5), progress: 1)])
        XCTAssertEqual(GardenEngine.harvest(at: GroundPoint(x: 0.58, y: 0.5), in: &g), .lettuce)
        XCTAssertEqual(g.plants.map(\.id), [1])
        XCTAssertEqual(g.coins, Tuning.startingCoins + FlowerType.lettuce.sellValue)
    }

    func testNearestPlantWithinReach() {
        let g = F.garden([F.plant(.daisy, id: 1)])
        XCTAssertEqual(GardenEngine.nearestPlant(to: GroundPoint(x: 0.52, y: 0.5), in: g, reach: 0.05)?.id, 1)
        XCTAssertNil(GardenEngine.nearestPlant(to: GroundPoint(x: 0.52, y: 0.5), in: g, reach: 0.01))
    }

    // MARK: DharmaGarden, withered plants and the planting rule

    func testWeedRateIsHalfTheOldAndTheCapIsTwelve() {
        XCTAssertEqual(Tuning.maxDharmaGarden, 12)
        XCTAssertEqual(Tuning.weedSpawnsPerCheckAtDefaultPlot, 0.64, accuracy: 1e-12, "half of 16 cells at 8 percent")
        // Average spawns per check over 1,000 checks on a fresh plot (the cap never bites on one check).
        var total = 0
        for k in 0..<1000 {
            var g = Garden(now: F.t0)
            GardenEngine.spawnDharmaGarden(&g, hourIndex: k * Tuning.weedCheckEveryHours)
            total += g.weeds.count
        }
        XCTAssertEqual(Double(total) / 1000, 0.64, accuracy: 0.05)
        // Left alone for two months the patch fills to the cap and stops there.
        let filled = F.advance(Garden(now: F.t0), hours: 60 * 24)
        XCTAssertEqual(filled.weeds.count, Tuning.maxDharmaGarden)
    }

    func testWeedToolClearsAWitheredPlantWhenNoWeedIsInReach() {
        var g = Garden(now: F.t0)
        _ = GardenEngine.plant(.daisy, at: F.centre, in: &g)
        g.plants[0].isDead = true
        XCTAssertFalse(GardenEngine.pullWeed(at: GroundPoint(x: 0.9, y: 0.9), in: &g), "nothing in reach")
        XCTAssertTrue(GardenEngine.pullWeed(at: F.centre, in: &g))
        XCTAssertTrue(g.plants.isEmpty, "the withered plant is cleared")
    }

    func testWeedToolPullsAWeedBeforeAWitheredPlant() {
        var g = Garden(now: F.t0)
        _ = GardenEngine.plant(.daisy, at: F.centre, in: &g)
        g.plants[0].isDead = true
        g.weeds = [Weed(id: 77, position: F.centre)]
        XCTAssertTrue(GardenEngine.pullWeed(at: F.centre, in: &g))
        XCTAssertTrue(g.weeds.isEmpty)
        XCTAssertEqual(g.plants.count, 1, "the withered plant stays until the next tap")
    }

    func testCanPlantFollowsTheSowRules() {
        var g = Garden(now: F.t0)
        XCTAssertTrue(GardenEngine.canPlant(at: F.centre, in: g))
        XCTAssertFalse(GardenEngine.canPlant(at: GroundPoint(x: 0.02, y: 0.02), in: g), "off the patch")
        _ = GardenEngine.plant(.daisy, at: F.centre, in: &g)
        XCTAssertFalse(GardenEngine.canPlant(at: GroundPoint(x: 0.5, y: 0.52), in: g), "too close to a living plant")
        XCTAssertTrue(GardenEngine.canPlant(at: GroundPoint(x: 0.5, y: 0.6), in: g))
        g.plants[0].isDead = true
        XCTAssertTrue(GardenEngine.canPlant(at: GroundPoint(x: 0.5, y: 0.52), in: g), "a withered plant does not block")
    }
}
