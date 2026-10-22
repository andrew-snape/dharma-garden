import Foundation
import Testing
@testable import DharmaGardenCore

struct GardenAdviceTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func garden(seeds: Bool = false) -> Garden {
        var g = Garden(now: now)
        g.seedStock = seeds ? [FlowerType.daisy.rawValue: 2] : [:]
        return g
    }

    @Test func emptyBedWithoutSeedsPointsToTheShop() {
        #expect(GardenAdvice.tips(for: garden()).map(\.action) == [.shop])
    }

    @Test func emptyBedWithSeedsSuggestsSowing() {
        #expect(GardenAdvice.tips(for: garden(seeds: true)).map(\.action) == [.sow])
    }

    @Test func readyThenThirstyThenDharmaGardenInOrder() {
        var g = garden()
        var ready = Plant(id: 1, flower: .daisy, position: GroundPoint(x: 0.4, y: 0.5))
        ready.progress = 1
        var thirsty = Plant(id: 2, flower: .lavender, position: GroundPoint(x: 0.6, y: 0.5))
        thirsty.moisture = 0
        g.plants = [ready, thirsty]
        g.weeds = [Weed(id: 3, position: GroundPoint(x: 0.5, y: 0.6))]
        #expect(GardenAdvice.tips(for: g).map(\.action) == [.pick, .water, .weed])
    }

    @Test func healthyGardenHasNoAdvice() {
        var g = garden()
        var plant = Plant(id: 1, flower: .daisy, position: GroundPoint(x: 0.5, y: 0.5))
        plant.moisture = 80
        g.plants = [plant]
        #expect(GardenAdvice.tips(for: g).isEmpty)
    }

    @Test func rainExpectedNeedsEnoughRainInTheNextDay() {
        let wet = WeatherSample(date: now.addingTimeInterval(3 * 3600), temperatureC: 12, precipitationMM: 3)
        let late = WeatherSample(date: now.addingTimeInterval(30 * 3600), temperatureC: 12, precipitationMM: 9)
        #expect(GardenAdvice.rainExpected(in: [wet], from: now))
        #expect(!GardenAdvice.rainExpected(in: [late], from: now))
        #expect(!GardenAdvice.rainExpected(in: [], from: now))
    }
}
