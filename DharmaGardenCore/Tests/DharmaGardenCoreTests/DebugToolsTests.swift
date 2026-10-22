import XCTest
@testable import DharmaGardenCore

final class DebugToolsTests: XCTestCase {
    typealias F = GardenFixture

    func testAdvanceByDaysMovesTheClockAndBloomsADaisy() {
        var g = Garden(now: F.t0)
        _ = GardenEngine.plant(.daisy, at: F.centre, in: &g)
        // DharmaGarden can slow it a little, so allow a few days over the 49-day base.
        let out = DebugTools.advance(garden: g, days: 52, autoWater: true,
                                         weather: F.weather(hours: 52 * 24, rain: 1))
        XCTAssertEqual(out.lastSimulatedAt, F.at(hours: 52 * 24))
        XCTAssertEqual(out.plants.first?.lifeStage, .blooming)
    }

    func testAdvanceWithoutAutoWaterLetsTheSoilDry() {
        var g = Garden(now: F.t0)
        _ = GardenEngine.plant(.daisy, at: F.centre, in: &g)
        g.soil = SoilField(fill: 0)
        let dry = DebugTools.advance(garden: g, days: 5, weather: F.weather(hours: 120))
        XCTAssertTrue(dry.plants.first?.isDead ?? false)
    }

    func testAutoWaterKeepsPlantsAliveThroughDryWeather() {
        var g = Garden(now: F.t0)
        _ = GardenEngine.plant(.daisy, at: F.centre, in: &g)
        g.soil = SoilField(fill: 0)
        let watered = DebugTools.advance(garden: g, days: 20, autoWater: true, weather: F.weather(hours: 20 * 24))
        XCTAssertFalse(watered.plants.first?.isDead ?? true)
        XCTAssertGreaterThan(watered.plants.first?.progress ?? 0, 0)
    }

    func testAutoWaterClearsTheDharmaGardenAtTheStartOfEachDay() {
        var g = Garden(now: F.t0)
        g.weeds = [Weed(id: 9001, position: F.centre)]
        let out = DebugTools.advance(garden: g, days: 1, autoWater: true, weather: F.weather(hours: 24))
        XCTAssertFalse(out.weeds.contains { $0.id == 9001 })
    }

    func testFillWithPlantsRotatesThroughEveryType() {
        let g = DebugTools.fillWithPlants(garden: Garden(now: F.t0), count: FlowerType.allCases.count)
        XCTAssertEqual(g.plants.count, FlowerType.allCases.count)
        XCTAssertEqual(Set(g.plants.map(\.flower)), Set(FlowerType.allCases))
        XCTAssertTrue(g.plants.allSatisfy { g.plot.contains($0.position, inset: Tuning.sowInset) })
    }

    func testFillWithPlantsIsDeterministicAndSpendsNothing() {
        let a = DebugTools.fillWithPlants(garden: Garden(now: F.t0), count: 30)
        let b = DebugTools.fillWithPlants(garden: Garden(now: F.t0), count: 30)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.coins, Tuning.startingCoins)
        XCTAssertEqual(a.seeds, [.daisy: Tuning.startingDaisySeeds])
    }

    func testFillWithPlantsStopsAtTheCap() {
        let g = DebugTools.fillWithPlants(garden: Garden(now: F.t0), count: 70)
        XCTAssertEqual(g.plants.count, Tuning.maxPlants)
    }

    func testSummaryCountsLivingPlantsByLifeStage() {
        var g = Garden(now: F.t0)
        g.plants = [
            F.plant(.daisy, id: 1, at: GroundPoint(x: 0.3, y: 0.3), progress: 1),
            F.plant(.lettuce, id: 2, at: GroundPoint(x: 0.6, y: 0.6), progress: 1),
            F.plant(.poppy, id: 3, at: GroundPoint(x: 0.7, y: 0.3), progress: 0.5),
        ]
        g.plants[1].bloomHoursElapsed = 10 * 24
        g.plants[2].isDead = true
        g.weeds = [Weed(id: 9, position: F.centre)]
        let s = DebugTools.summary(of: g)
        XCTAssertEqual(s, DebugTools.Summary(planted: 2, blooming: 1, fading: 1, weeds: 1))
    }

    func testResetGivesAFreshGarden() {
        XCTAssertEqual(DebugTools.reset(now: F.t0), Garden(now: F.t0))
    }
}
