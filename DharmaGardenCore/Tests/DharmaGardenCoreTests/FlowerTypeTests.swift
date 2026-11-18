import XCTest
@testable import DharmaGardenCore

/// The flower catalogue (durations, prices, categories, traits), growth rules per flower on the free-form patch,
/// and the southern-hemisphere seasons.
final class FlowerTypeTests: XCTestCase {
    typealias F = GardenFixture

    func testNewPlantDurationsAndEconomy() {
        XCTAssertEqual(FlowerType.chocolateLily.daysToBloom, 100)
        XCTAssertEqual(FlowerType.commonEverlasting.daysToBloom, 80)
        XCTAssertEqual(FlowerType.calendula.daysToBloom, 56)
        XCTAssertEqual(FlowerType.cosmos.daysToBloom, 60)
        XCTAssertEqual(FlowerType.basil.daysToBloom, 28)
        XCTAssertEqual(FlowerType.zucchini.daysToBloom, 63)
        XCTAssertEqual(FlowerType.lettuce.daysToBloom, 42)
        XCTAssertEqual(FlowerType.chocolateLily.sellValue, 25)
        XCTAssertEqual(FlowerType.commonEverlasting.sellValue, 20)
        XCTAssertEqual(FlowerType.calendula.sellValue, 14)
        XCTAssertEqual(FlowerType.cosmos.sellValue, 15)
        XCTAssertEqual(FlowerType.basil.sellValue, 7)
        XCTAssertEqual(FlowerType.zucchini.sellValue, 15)
        XCTAssertEqual(FlowerType.lettuce.sellValue, 10)
        XCTAssertEqual(FlowerType.chocolateLily.seedPrice, 2)
        XCTAssertEqual(FlowerType.commonEverlasting.seedPrice, 2)
        XCTAssertEqual(FlowerType.calendula.seedPrice, 1)
        XCTAssertEqual(FlowerType.cosmos.seedPrice, 1, "60 days is still quick")
        XCTAssertEqual(FlowerType.basil.seedPrice, 1)
        XCTAssertEqual(FlowerType.zucchini.seedPrice, 2)
        XCTAssertEqual(FlowerType.lettuce.seedPrice, 1)
        XCTAssertTrue(FlowerType.allCases.allSatisfy { [1, 2].contains($0.seedPrice) }, "every seed costs 1 or 2 carrots")
        XCTAssertEqual(Tuning.seasolCost, 1)
        XCTAssertEqual(Tuning.fertiliserCost, 2)
    }

    func testCatalogueCategoriesAndNames() {
        XCTAssertEqual(FlowerType.allCases.count, 30)
        XCTAssertEqual(Array(FlowerType.allCases.prefix(4)), [.sunflower, .daisy, .lavender, .poppy], "original order kept")
        XCTAssertEqual(FlowerType.allCases.filter(\.isNative), [.chocolateLily, .commonEverlasting, .nativeViolet, .billyButtons, .bulbineLily])
        XCTAssertEqual(FlowerType.calendula.category, .exoticFlower)
        XCTAssertEqual(FlowerType.basil.category, .herb)
        XCTAssertEqual(FlowerType.zucchini.category, .vegetable)
        XCTAssertEqual(FlowerType.lettuce.category, .vegetable)
        XCTAssertEqual(FlowerType.basil.readyWord, "harvest")
        XCTAssertEqual(FlowerType.zucchini.readyWord, "harvest")
        XCTAssertEqual(FlowerType.cosmos.readyWord, "bloom")
        XCTAssertEqual(FlowerType.commonEverlasting.displayName, "Common everlasting")
        XCTAssertEqual(FlowerType.chocolateLily.displayName, "Chocolate lily")
        XCTAssertEqual(FlowerType.lettuce.sowSeasonHint, "Sow autumn to winter")
        XCTAssertEqual(FlowerType.calendula.sowSeasonHint, "Sow autumn or spring")
        XCTAssertEqual(FlowerType.basil.sowSeasonHint, "Sow spring to summer")
        XCTAssertEqual(FlowerType.chocolateLily.sowSeasonHint, "Sow autumn")
        for f in FlowerType.allCases {
            XCTAssertFalse(f.displayName.isEmpty)
            XCTAssertFalse(f.sowSeasonHint.isEmpty)
        }
    }

    func testTraitFlags() {
        XCTAssertEqual(FlowerType.allCases.filter(\.lovesHeat), [.sunflower, .basil, .zucchini, .corn, .zinnia])
        XCTAssertEqual(FlowerType.allCases.filter(\.dryTolerant), [.lavender, .chocolateLily, .commonEverlasting, .billyButtons, .bulbineLily, .thyme])
        XCTAssertEqual(FlowerType.allCases.filter(\.frostTender), [.poppy, .cosmos, .basil, .zucchini, .corn, .zinnia, .marigold])
        XCTAssertEqual(FlowerType.allCases.filter(\.frostTolerant), [.chocolateLily, .commonEverlasting, .calendula, .lettuce, .beetroot, .broccoli, .rocket, .broadBean, .radish, .spinach, .alyssum, .nativeViolet, .billyButtons, .bulbineLily, .parsley, .chives, .thyme])
        XCTAssertEqual(FlowerType.allCases.filter(\.coolSeason), [.lettuce, .rocket, .spinach])
        XCTAssertEqual(FlowerType.allCases.filter(\.thirsty), [.zucchini, .corn])
    }

    /// Each flower reaches ready (progress 1) in about its days under watered, mild weather (speed factor 1).
    func testNewPlantsReachReadyInTheirDays() {
        for f in FlowerType.allCases {
            let days = f.daysToBloom
            let before = F.advance(F.garden([F.plant(f, id: 1)]), hours: Int(days * 24) - 24, temp: 20, rain: 1)
            let after = F.advance(F.garden([F.plant(f, id: 1)]), hours: Int(days * 24) + 24, temp: 20, rain: 1)
            XCTAssertLessThan(before.plants[0].progress, 1, "\(f) is not ready a day early")
            XCTAssertEqual(after.plants[0].progress, 1, "\(f) is ready a day late")
        }
    }

    func testLettuceBoltsInHeatAndLikesCool() {
        let mild = F.advance(F.garden([F.plant(.lettuce, id: 1)]), hours: 48, temp: 20, rain: 3)
        let hot = F.advance(F.garden([F.plant(.lettuce, id: 1)]), hours: 48, temp: 32, rain: 3)
        let cool = F.advance(F.garden([F.plant(.lettuce, id: 1)]), hours: 48, temp: 10, rain: 3)
        XCTAssertGreaterThan(mild.plants[0].progress, 0)
        XCTAssertEqual(hot.plants[0].progress / mild.plants[0].progress, 0.4, accuracy: 0.01, "bolts above 28 C")
        XCTAssertGreaterThan(cool.plants[0].progress, mild.plants[0].progress, "small bonus below 15 C")
    }

    func testHeatLovingPlantsGetTheHeatBoost() {
        for f in [FlowerType.sunflower, .basil, .zucchini] {
            let warm = F.advance(F.garden([F.plant(f, id: 1)]), hours: 48, temp: 26, rain: 3)
            let mild = F.advance(F.garden([F.plant(f, id: 1)]), hours: 48, temp: 20, rain: 3)
            XCTAssertEqual(warm.plants[0].progress / mild.plants[0].progress, Tuning.heatGrowthMultiplier, accuracy: 0.01, "\(f)")
        }
    }

    func testCommonEverlastingSurvivesDryWeatherBetterThanDaisy() {
        // Starting from a full patch with no rain: the daisy runs dry at 100 hours and dies 96 hours later.
        let daisy = F.advance(F.garden([F.plant(.daisy, id: 1)]), hours: 200)
        let everlasting = F.advance(F.garden([F.plant(.commonEverlasting, id: 1)]), hours: 200)
        XCTAssertTrue(daisy.plants[0].isDead, "daisy dies after about 196 hours without rain")
        XCTAssertFalse(everlasting.plants[0].isDead, "common everlasting is still alive after 200 dry hours")
    }

    func testSouthernHemisphereSeasons() {
        let dec = Date(timeIntervalSince1970: 1_734_000_000) // Dec 2024
        XCTAssertEqual(SeasonProvider.season(on: dec, latitude: -38.2), .summer)
        XCTAssertEqual(SeasonProvider.season(on: dec, latitude: 51.5), .winter)
    }
}
