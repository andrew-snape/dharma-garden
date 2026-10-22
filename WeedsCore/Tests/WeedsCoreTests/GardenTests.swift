import XCTest
@testable import WeedsCore

/// Shared fixtures for the free-form garden tests.
enum GardenFixture {
    static let t0 = Date(timeIntervalSince1970: 1_699_999_200)   // on an hour boundary
    static let centre = GroundPoint(x: 0.5, y: 0.5)
    /// Seed that gives a speed factor of exactly 1 (unit value 0.5).
    static let neutralSeed: UInt64 = 1 << 63
    /// Far from the centre, so weeds parked here never slow the plants under test.
    static let farAway = GroundPoint(x: 0.02, y: 0.98)

    static func at(hours n: Int) -> Date { t0.addingTimeInterval(Double(n) * 3600) }

    static func weather(hours n: Int, temp: Double = 18, rain: Double = 0, wind: Double = 5,
                        isDay: Bool = true) -> [WeatherSample] {
        (1...max(1, n)).map {
            WeatherSample(date: at(hours: $0), temperatureC: temp, precipitationMM: rain, windKmh: wind, isDay: isDay)
        }
    }

    static func plant(_ f: FlowerType, id: Int, at p: GroundPoint = centre, progress: Double = 0,
                      moisture: Double = 100) -> Plant {
        var plant = Plant(id: id, flower: f, position: p, plantSeed: neutralSeed, moisture: moisture)
        plant.progress = progress
        return plant
    }

    /// A garden starting at `t0` with the given plants and soil. Fourteen weeds parked far away mean no
    /// new weeds spawn (the cap is reached) and none slow the plants.
    static func garden(_ plants: [Plant], soil moisture: Double = 100) -> Garden {
        var g = Garden(now: t0)
        g.soil = SoilField(fill: moisture)
        g.plants = plants
        g.weeds = (0..<Tuning.maxWeeds).map { Weed(id: 9000 + $0, position: farAway) }
        g.nextID = 9000 + Tuning.maxWeeds + 1
        return g
    }

    /// Advances a garden that starts at `t0` by `n` hours of constant weather.
    static func advance(_ g: Garden, hours n: Int, temp: Double = 18, rain: Double = 0,
                        wind: Double = 5, isDay: Bool = true) -> Garden {
        GardenEngine.advance(g, weather: weather(hours: n, temp: temp, rain: rain, wind: wind, isDay: isDay),
                                 to: at(hours: n))
    }
}

final class GardenModelTests: XCTestCase {

    // MARK: GroundPoint

    func testDistance() {
        XCTAssertEqual(GroundPoint(x: 0, y: 0).distance(to: GroundPoint(x: 0.3, y: 0.4)), 0.5, accuracy: 1e-12)
        XCTAssertEqual(GroundPoint(x: 0.2, y: 0.7).distance(to: GroundPoint(x: 0.2, y: 0.7)), 0)
    }

    // MARK: PlotShape

    func testPlotContainsCentreAndRejectsCorners() {
        let plot = PlotShape()
        XCTAssertTrue(plot.contains(GardenFixture.centre))
        XCTAssertFalse(plot.contains(GroundPoint(x: 0.02, y: 0.02)))
        XCTAssertFalse(plot.contains(GroundPoint(x: 0.99, y: 0.5)))
    }

    func testEdgeDistanceIsPositiveInsideAndNegativeOutside() {
        let plot = PlotShape()
        XCTAssertGreaterThan(plot.edgeDistance(GardenFixture.centre), 0.35)
        XCTAssertLessThan(plot.edgeDistance(GroundPoint(x: 0.99, y: 0.5)), 0)
        XCTAssertLessThan(abs(plot.edgeDistance(GroundPoint(x: 0.5 + 0.46, y: 0.5))), 0.03)
    }

    func testInsetShrinksThePlot() {
        let plot = PlotShape()
        // A point just inside the edge passes with no inset but fails with a larger one.
        let p = GroundPoint(x: 0.5 + 0.44, y: 0.5)
        XCTAssertTrue(plot.contains(p))
        XCTAssertFalse(plot.contains(p, inset: 0.05))
    }

    func testWobbleMakesEdgeNotAPerfectEllipse() {
        let plot = PlotShape()
        var deviations: [Double] = []
        for step in 0..<360 {
            let a = Double(step) * Double.pi / 180
            let p = GroundPoint(x: 0.5 + cos(a) * 0.46, y: 0.5 + sin(a) * 0.42)
            deviations.append(abs(plot.edgeDistance(p)))
        }
        XCTAssertGreaterThan(deviations.max() ?? 0, 0.005, "the edge should wobble off the plain ellipse")
        XCTAssertLessThan(deviations.max() ?? 1, 0.06, "the wobble should stay small")
    }

    func testEdgeStaysNearTheEllipseEverywhere() {
        let plot = PlotShape()
        for step in 0..<360 {
            let a = Double(step) * Double.pi / 180
            let inside = GroundPoint(x: 0.5 + cos(a) * 0.46 * 0.9, y: 0.5 + sin(a) * 0.42 * 0.9)
            let outside = GroundPoint(x: 0.5 + cos(a) * 0.46 * 1.1, y: 0.5 + sin(a) * 0.42 * 1.1)
            XCTAssertTrue(plot.contains(inside), "angle \(step)")
            XCTAssertFalse(plot.contains(outside), "angle \(step)")
        }
    }

    func testWobbleIsDeterministic() {
        XCTAssertEqual(PlotShape(), PlotShape())
        let a = PlotShape(), b = PlotShape()
        for step in 0..<50 {
            let p = GroundPoint(x: Double(step) / 50, y: 0.37)
            XCTAssertEqual(a.edgeDistance(p), b.edgeDistance(p))
        }
    }

    func testPlotAreaIsAboutSixTenths() {
        XCTAssertEqual(PlotShape().area, Double.pi * 0.46 * 0.42, accuracy: 1e-12)
    }

    func testRandomPointsAreInsideWithInsetAndDeterministic() {
        let plot = PlotShape()
        for seed in 0..<200 {
            let p = plot.point(seed: UInt64(seed) &* 77 &+ 1, inset: 0.03)
            XCTAssertTrue(plot.contains(p, inset: 0.03), "seed \(seed)")
            XCTAssertEqual(p, plot.point(seed: UInt64(seed) &* 77 &+ 1, inset: 0.03))
        }
    }

    // MARK: SoilField

    func testSampleAtCellCentreReturnsThatCell() {
        var soil = SoilField(fill: 50)
        soil.values[7 * SoilField.columns + 5] = 80
        XCTAssertEqual(soil.moisture(at: SoilField.cellCentre(column: 5, row: 7)), 80, accuracy: 1e-9)
    }

    func testBilinearSamplingBetweenCells() {
        var soil = SoilField(fill: 0)
        soil.values[4 * SoilField.columns + 4] = 20
        soil.values[4 * SoilField.columns + 5] = 60
        let a = SoilField.cellCentre(column: 4, row: 4), b = SoilField.cellCentre(column: 5, row: 4)
        let mid = GroundPoint(x: (a.x + b.x) / 2, y: a.y)
        XCTAssertEqual(soil.moisture(at: mid), 40, accuracy: 1e-9)
    }

    func testSamplingClampsOutsideTheSquare() {
        let soil = SoilField(fill: 33)
        XCTAssertEqual(soil.moisture(at: GroundPoint(x: -1, y: 2)), 33, accuracy: 1e-9)
    }

    func testAddIsStrongestAtCentreAndFadesToNothing() {
        var soil = SoilField(fill: 50)
        soil.add(40, at: GardenFixture.centre, radius: 0.2)
        let near = soil.moisture(at: GardenFixture.centre)
        XCTAssertGreaterThan(near, 85)
        XCTAssertLessThanOrEqual(near, 90.0001)

        let mid = soil.moisture(at: GroundPoint(x: 0.5 + 0.1, y: 0.5))
        XCTAssertGreaterThan(mid, 50)
        XCTAssertLessThan(mid, near)

        // Far from the centre nothing changes.
        XCTAssertEqual(soil.moisture(at: GroundPoint(x: 0.9, y: 0.9)), 50, accuracy: 1e-9)
    }

    func testAddClampsToZeroAndHundred() {
        var soil = SoilField(fill: 50)
        soil.add(500, at: GardenFixture.centre, radius: 0.3)
        XCTAssertTrue(soil.values.allSatisfy { $0 >= 0 && $0 <= 100 })
        XCTAssertEqual(soil.moisture(at: GardenFixture.centre), 100, accuracy: 1e-9)
        soil.add(-500, at: GardenFixture.centre, radius: 0.3)
        XCTAssertTrue(soil.values.allSatisfy { $0 >= 0 && $0 <= 100 })
        XCTAssertEqual(soil.moisture(at: GardenFixture.centre), 0, accuracy: 1e-9)
    }

    func testAddWithZeroRadiusOrAmountDoesNothing() {
        var soil = SoilField(fill: 50)
        soil.add(30, at: GardenFixture.centre, radius: 0)
        soil.add(0, at: GardenFixture.centre, radius: 0.2)
        XCTAssertEqual(soil, SoilField(fill: 50))
    }

    func testForEachCellVisitsEveryCellOnce() {
        let soil = SoilField(fill: 12)
        var count = 0
        soil.forEachCell { _, _, _, m in
            count += 1
            XCTAssertEqual(m, 12)
        }
        XCTAssertEqual(count, SoilField.columns * SoilField.rows)
        XCTAssertEqual(SoilField.columns * SoilField.rows, 504)
    }

    func testCellIndexMatchesCellCentre() {
        let p = SoilField.cellCentre(column: 13, row: 4)
        XCTAssertEqual(SoilField.cellIndex(of: p), 4 * SoilField.columns + 13)
    }

    func testWrongSizedSoilSaveResetsToStartingMoisture() throws {
        let json = #"{"values":[1,2,3]}"#.data(using: .utf8)!
        let soil = try JSONDecoder().decode(SoilField.self, from: json)
        XCTAssertEqual(soil.values.count, SoilField.columns * SoilField.rows)
        XCTAssertTrue(soil.values.allSatisfy { $0 == SoilField.startingMoisture })
    }

    // MARK: Plant

    func testLifeStageThresholds() {
        var p = GardenFixture.plant(.daisy, id: 1, progress: 1)
        XCTAssertEqual(p.lifeStage, .blooming)
        p.bloomHoursElapsed = 10 * 24 - 1
        XCTAssertEqual(p.lifeStage, .blooming)
        p.bloomHoursElapsed = 10 * 24
        XCTAssertEqual(p.lifeStage, .fading)
        p.bloomHoursElapsed = 17 * 24
        XCTAssertEqual(p.lifeStage, .seedHead)
        p.progress = 0.99
        XCTAssertEqual(p.lifeStage, .growing)
    }

    func testFadeRampsAcrossTheFadingDays() {
        var p = GardenFixture.plant(.daisy, id: 1, progress: 1)
        p.bloomHoursElapsed = 10 * 24
        XCTAssertEqual(p.fade, 0, accuracy: 1e-9)
        p.bloomHoursElapsed = 10 * 24 + 84
        XCTAssertEqual(p.fade, 0.5, accuracy: 1e-9)
        p.bloomHoursElapsed = 17 * 24 + 50
        XCTAssertEqual(p.fade, 1, accuracy: 1e-9)
        let growing = GardenFixture.plant(.daisy, id: 2)
        XCTAssertEqual(growing.fade, 0)
    }

    func testStageLabelsFollowProgress() {
        XCTAssertEqual(GardenFixture.plant(.daisy, id: 1, progress: 0.1).stage, .seed)
        XCTAssertEqual(GardenFixture.plant(.daisy, id: 1, progress: 0.3).stage, .sprout)
        XCTAssertEqual(GardenFixture.plant(.daisy, id: 1, progress: 0.8).stage, .bud)
        XCTAssertEqual(GardenFixture.plant(.daisy, id: 1, progress: 1).stage, .bloom)
    }

    func testDroopFollowsMoistureAndWilting() {
        let p = GardenFixture.plant(.daisy, id: 1)
        XCTAssertEqual(p.droop(moisture: 60), 0)
        XCTAssertEqual(p.droop(moisture: 40), 0)
        XCTAssertEqual(p.droop(moisture: 0), 1)
        XCTAssertEqual(p.droop(moisture: 20), 0.5, accuracy: 1e-9)
        var wilted = p
        wilted.dryHours = Tuning.wiltAfterDryHours
        XCTAssertTrue(wilted.isWilted)
        XCTAssertEqual(wilted.droop(moisture: 90), 1)
    }

    func testSpeedFactorStaysWithinVariation() {
        XCTAssertEqual(GardenFixture.plant(.daisy, id: 1).speedFactor, 1, accuracy: 1e-12)
        for seed in 0..<500 {
            var p = GardenFixture.plant(.daisy, id: 1)
            p.plantSeed = DeterministicHash.mix(UInt64(seed))
            XCTAssertLessThanOrEqual(abs(p.speedFactor - 1), Tuning.speedVariation + 1e-12)
        }
    }

    // MARK: Garden

    func testNewGardenStartsWithDaisySeedsAndCoins() {
        let g = Garden(now: GardenFixture.t0)
        XCTAssertEqual(g.version, 5)
        XCTAssertEqual(Garden.currentVersion, 5)
        XCTAssertTrue(g.plants.isEmpty)
        XCTAssertTrue(g.weeds.isEmpty)
        XCTAssertEqual(g.seeds, [.daisy: Tuning.startingDaisySeeds])
        XCTAssertEqual(g.coins, Tuning.startingCoins)
        XCTAssertEqual(g.lastSimulatedAt, GardenFixture.t0)
        XCTAssertTrue(g.soil.values.allSatisfy { $0 == 50 })
        XCTAssertEqual(g.nextID, 1)
    }

    func testSeedsAccessorDropsZeroCounts() {
        var g = Garden(now: GardenFixture.t0)
        g.seeds = [.lettuce: 2, .poppy: 0]
        XCTAssertEqual(g.seeds, [.lettuce: 2])
        XCTAssertEqual(g.seedStock, ["lettuce": 2])
        XCTAssertEqual(g.seedCount(.daisy), 0)
    }

    func testCodableRoundTripKeepsEverything() throws {
        var g = GardenFixture.garden([GardenFixture.plant(.lavender, id: 3, at: GroundPoint(x: 0.3, y: 0.6), progress: 0.4)],
                                   soil: 42)
        g.coins = 99
        g.weeds.append(Weed(id: 77, position: GroundPoint(x: 0.7, y: 0.4), ageHours: 12))
        g.nextID = 80
        let data = try JSONEncoder().encode(g)
        let back = try JSONDecoder().decode(Garden.self, from: data)
        XCTAssertEqual(back, g)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"version\":5"))
    }

    func testOldSaveWithoutVersionDecodesWithDefaults() throws {
        let json = #"{"lastSimulatedAt":1699999200}"#.data(using: .utf8)!
        let g = try JSONDecoder().decode(Garden.self, from: json)
        XCTAssertEqual(g.version, 1)
        XCTAssertTrue(g.plants.isEmpty)
        XCTAssertEqual(g.coins, Tuning.startingCoins)
        XCTAssertEqual(g.soil.values.count, SoilField.columns * SoilField.rows)
        XCTAssertEqual(g.nextID, 1)
    }

    func testNextIDIsDerivedWhenMissing() throws {
        let json = #"{"lastSimulatedAt":1699999200,"plants":[{"id":5,"flower":"daisy","position":{"x":0.5,"y":0.5}}],"weeds":[{"id":9,"position":{"x":0.4,"y":0.4}}]}"#
        let g = try JSONDecoder().decode(Garden.self, from: Data(json.utf8))
        XCTAssertEqual(g.nextID, 10)
        XCTAssertEqual(g.plants.first?.moisture, SoilField.startingMoisture)
    }
}
