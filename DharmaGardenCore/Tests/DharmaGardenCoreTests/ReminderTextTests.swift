import XCTest
@testable import DharmaGardenCore

/// The daily reminder: priorities, the words for ready and thirsty plants, and the projection to notification time.
final class ReminderTextTests: XCTestCase {
    typealias F = GardenFixture

    /// A second spot on the patch, away from the centre so two plants do not crowd each other.
    let p2 = GroundPoint(x: 0.25, y: 0.3)

    /// A garden on the fixture's soil with the given plants (weeds parked far away, so none are near).
    private func garden(_ plants: [Plant], soil: Double = 100) -> Garden {
        F.garden(plants, soil: soil)
    }

    private func plant(_ f: FlowerType, _ id: Int, at p: GroundPoint = F.centre, moisture: Double = 60,
                       progress: Double = 0.3) -> Plant {
        F.plant(f, id: id, at: p, progress: progress, moisture: moisture)
    }

    /// A fully grown flower at the start of its bloom: ready to pick.
    private func bloom(_ f: FlowerType, _ id: Int, at p: GroundPoint = F.centre, moisture: Double = 60) -> Plant {
        F.plant(f, id: id, at: p, progress: 1, moisture: moisture)
    }

    // MARK: Priorities

    func testEmptyGardenIsFine() {
        XCTAssertEqual(ReminderText.message(for: Garden(now: F.t0)), "Your garden is doing fine")
    }

    func testHealthyPlantsGiveTheFallback() {
        let g = garden([plant(.daisy, 1, moisture: 60), plant(.poppy, 2, at: p2, moisture: 80)])
        XCTAssertEqual(ReminderText.message(for: g), ReminderText.fallback)
    }

    func testSingleReadyFlower() {
        XCTAssertEqual(ReminderText.message(for: garden([bloom(.daisy, 1)])), "Your daisy is ready to pick")
    }

    func testSeveralReadyFlowersOfMixedKinds() {
        let g = garden([bloom(.daisy, 1), bloom(.poppy, 2, at: p2), bloom(.sunflower, 3, at: GroundPoint(x: 0.7, y: 0.6))])
        XCTAssertEqual(ReminderText.message(for: g), "3 flowers are ready to pick")
    }

    func testSeveralReadyOfTheSameKind() {
        let g = garden([bloom(.lavender, 1), bloom(.lavender, 2, at: p2)])
        XCTAssertEqual(ReminderText.message(for: g), "2 lavenders are ready to pick")
    }

    func testReadyBeatsThirst() {
        let g = garden([bloom(.daisy, 1, moisture: 5), plant(.poppy, 2, at: p2, moisture: 3)])
        XCTAssertEqual(ReminderText.message(for: g), "Your daisy is ready to pick")
    }

    func testThirstyBeatsDharmaGarden() {
        var g = garden([plant(.daisy, 1, moisture: 10), plant(.poppy, 2, at: p2, moisture: 60)])
        g.weeds = [Weed(id: 50, position: GroundPoint(x: 0.27, y: 0.3)), Weed(id: 51, position: GroundPoint(x: 0.25, y: 0.33))]
        XCTAssertEqual(ReminderText.message(for: g), "Your daisy is thirsty")
    }

    func testOneThirstyDaisy() {
        XCTAssertEqual(ReminderText.message(for: garden([plant(.daisy, 1, moisture: 19.9)])), "Your daisy is thirsty")
    }

    func testTwentyMoistureIsNotThirsty() {
        XCTAssertEqual(ReminderText.message(for: garden([plant(.daisy, 1, moisture: 20)])), ReminderText.fallback)
    }

    func testTwoThirstyDaisiesArePlural() {
        let g = garden([plant(.daisy, 1, moisture: 5), plant(.daisy, 2, at: p2, moisture: 12)])
        XCTAssertEqual(ReminderText.message(for: g), "Your daisies are thirsty")
    }

    func testThirstyMixedKinds() {
        let g = garden([plant(.daisy, 1, moisture: 5), plant(.poppy, 2, at: p2, moisture: 12)])
        XCTAssertEqual(ReminderText.message(for: g), "Some of your flowers are thirsty")
    }

    func testTwoDharmaGardenNearAPlantNeedAttention() {
        var g = garden([plant(.daisy, 1, moisture: 60)])
        g.weeds = [Weed(id: 50, position: GroundPoint(x: 0.52, y: 0.5)), Weed(id: 51, position: GroundPoint(x: 0.5, y: 0.53))]
        XCTAssertEqual(ReminderText.message(for: g), "DharmaGarden are creeping in")
    }

    func testOneWeedIsNotEnough() {
        var g = garden([plant(.daisy, 1, moisture: 60)])
        g.weeds = [Weed(id: 50, position: GroundPoint(x: 0.52, y: 0.5))]
        XCTAssertEqual(ReminderText.message(for: g), ReminderText.fallback)
    }

    func testDharmaGardenFarFromEveryPlantDoNotCount() {
        var g = garden([plant(.daisy, 1, moisture: 60)])
        g.weeds = [Weed(id: 50, position: GroundPoint(x: 0.1, y: 0.1)), Weed(id: 51, position: GroundPoint(x: 0.12, y: 0.1))]
        XCTAssertEqual(ReminderText.message(for: g), ReminderText.fallback)
    }

    func testDeadPlantsAreIgnored() {
        var dead = plant(.daisy, 1, moisture: 0)
        dead.isDead = true
        XCTAssertEqual(ReminderText.message(for: garden([dead])), ReminderText.fallback)
    }

    // MARK: Pick or harvest

    func testFlowersArePickedAndHerbsAndVegetablesHarvested() {
        XCTAssertEqual(ReminderText.message(for: garden([bloom(.daisy, 1)])), "Your daisy is ready to pick")
        XCTAssertEqual(ReminderText.message(for: garden([bloom(.basil, 1)])), "Your basil is ready to harvest")
        XCTAssertEqual(ReminderText.message(for: garden([bloom(.zucchini, 1)])), "Your zucchini is ready to harvest")
        XCTAssertEqual(ReminderText.message(for: garden([bloom(.lettuce, 1)])), "Your lettuce is ready to harvest")
    }

    func testSeveralVegetablesOfTheSameKindHarvest() {
        XCTAssertEqual(ReminderText.message(for: garden([bloom(.zucchini, 1), bloom(.zucchini, 2, at: p2)])),
                       "2 zucchinis are ready to harvest")
    }

    func testSeveralFlowersAndHerbsCountAsPlants() {
        XCTAssertEqual(ReminderText.message(for: garden([bloom(.daisy, 1), bloom(.basil, 2, at: p2)])), "2 plants are ready")
    }

    func testSeveralHarvestablesOfMixedKindsAreHarvested() {
        XCTAssertEqual(ReminderText.message(for: garden([bloom(.basil, 1), bloom(.lettuce, 2, at: p2)])),
                       "2 plants are ready to harvest")
    }

    // MARK: Names

    func testNamesAreLowerCaseDisplayNames() {
        XCTAssertEqual(ReminderText.name(for: .daisy), "daisy")
        XCTAssertEqual(ReminderText.name(for: .sunflower), "sunflower")
        XCTAssertEqual(ReminderText.name(for: .commonEverlasting), "common everlasting")
        XCTAssertEqual(ReminderText.name(for: .chocolateLily), "chocolate lily")
        for f in FlowerType.allCases {
            XCTAssertEqual(ReminderText.name(for: f), f.displayName.lowercased())
        }
    }

    func testPluralsForTheNewNames() {
        XCTAssertEqual(ReminderText.plural("common everlasting"), "common everlastings")
        XCTAssertEqual(ReminderText.plural("chocolate lily"), "chocolate lilies")
        XCTAssertEqual(ReminderText.plural("calendula"), "calendulas")
        XCTAssertEqual(ReminderText.plural("cosmos"), "cosmos")
        XCTAssertEqual(ReminderText.plural("basil"), "basil")
        XCTAssertEqual(ReminderText.plural("zucchini"), "zucchinis")
        XCTAssertEqual(ReminderText.plural("lettuce"), "lettuces")
    }

    func testPlurals() {
        XCTAssertEqual(ReminderText.plural("daisy"), "daisies")
        XCTAssertEqual(ReminderText.plural("poppy"), "poppies")
        XCTAssertEqual(ReminderText.plural("sunflower"), "sunflowers")
        XCTAssertEqual(ReminderText.plural("lavender"), "lavenders")
        XCTAssertEqual(ReminderText.plural("bus"), "buses")
        XCTAssertEqual(ReminderText.plural("bench"), "benches")
        XCTAssertEqual(ReminderText.plural("day"), "days", "a vowel before y keeps it")
    }

    func testReadySentencesUseDisplayNames() {
        XCTAssertEqual(ReminderText.message(for: garden([bloom(.commonEverlasting, 1)])),
                       "Your common everlasting is ready to pick")
        XCTAssertEqual(ReminderText.message(for: garden([bloom(.chocolateLily, 1), bloom(.chocolateLily, 2, at: p2)])),
                       "2 chocolate lilies are ready to pick")
        XCTAssertEqual(ReminderText.message(for: garden([bloom(.basil, 1), bloom(.basil, 2, at: p2)])),
                       "2 basil are ready to harvest")
        XCTAssertEqual(ReminderText.message(for: garden([plant(.lettuce, 1, moisture: 5), plant(.lettuce, 2, at: p2, moisture: 5)])),
                       "Your lettuces are thirsty")
    }

    // MARK: Projection to the notification time

    func testDryGardenProjectedForwardBecomesThirsty() {
        // 30 moisture drains about 1 a hour in neutral weather, so a day later it is below 20.
        let g = garden([plant(.daisy, 1, moisture: 30)], soil: 30)
        XCTAssertEqual(ReminderText.message(for: g), ReminderText.fallback)
        XCTAssertEqual(ReminderText.message(for: g, at: F.at(hours: 24)), "Your daisy is thirsty")
    }

    func testRainInTheForecastKeepsTheGardenFine() {
        // Dry at the start, but 5 mm an hour for a day refills it, so the projected garden is fine.
        let g = garden([plant(.daisy, 1, moisture: 10)], soil: 10)
        let rain = F.weather(hours: 24, rain: 5)
        XCTAssertEqual(ReminderText.message(for: g, at: F.at(hours: 24), weather: rain), ReminderText.fallback)
    }

    func testProjectionWithNoForecastUsesNeutralWeather() {
        let g = garden([plant(.daisy, 1, moisture: 30)], soil: 30)
        let direct = ReminderText.message(for: GardenEngine.advance(g, weather: [], to: F.at(hours: 24)))
        XCTAssertEqual(ReminderText.message(for: g, at: F.at(hours: 24), weather: []), direct)
    }

    func testReadyFlowerAtBloomStaysReadyWhenProjectedWithinTheBloomWindow() {
        // Full bloom with no time elapsed: a day later it is still in its bloom window (about 10 days).
        XCTAssertEqual(ReminderText.message(for: garden([bloom(.sunflower, 1, moisture: 90)]), at: F.at(hours: 24)),
                       "Your sunflower is ready to pick")
    }

    func testMessageProjectsForwardWithTheForecast() {
        // Watered and growing now; with no rain for two days the soil dries and the plant turns thirsty.
        let g = garden([plant(.daisy, 1, progress: 0.4)], soil: 60)
        XCTAssertEqual(ReminderText.message(for: g, at: F.at(hours: 2 * 24), weather: F.weather(hours: 2 * 24)),
                       "Your daisy is thirsty")
        XCTAssertEqual(ReminderText.message(for: g, at: F.at(hours: 2 * 24), weather: F.weather(hours: 2 * 24, rain: 5)),
                       ReminderText.fallback)
    }
}
