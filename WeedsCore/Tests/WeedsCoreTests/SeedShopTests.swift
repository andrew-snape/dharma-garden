import XCTest
@testable import WeedsCore

final class SeedShopTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_699_999_200)

    func fresh() -> Garden { Garden(now: t0) }

    // MARK: Starting inventory

    func testNewGardenStartsWithThreeDaisySeeds() {
        let g = fresh()
        XCTAssertEqual(g.seeds, [.daisy: Tuning.startingDaisySeeds])
        XCTAssertEqual(g.seedCount(.daisy), 3)
        XCTAssertEqual(g.seedCount(.poppy), 0)
        XCTAssertEqual(Tuning.startingDaisySeeds, 3)
        XCTAssertEqual(g.coins, Tuning.startingCoins)
    }

    // MARK: Buying

    func testBuySeedsSpendsCoinsAndAddsToInventory() {
        var g = fresh()
        XCTAssertTrue(GardenEngine.buySeeds(.daisy, count: 3, in: &g))
        XCTAssertEqual(g.coins, Tuning.startingCoins - 3 * FlowerType.daisy.seedPrice)
        XCTAssertEqual(g.seedCount(.daisy), 6)
    }

    func testBuySeedsInsufficientCoinsChangesNothing() {
        var g = fresh()
        g.coins = FlowerType.daisy.seedPrice - 1
        let before = g
        XCTAssertFalse(GardenEngine.buySeeds(.daisy, count: 1, in: &g))
        XCTAssertEqual(g, before)
    }

    func testBuyingThreeWhenOnlyTwoAffordableChangesNothing() {
        var g = fresh()
        g.coins = 2 * FlowerType.poppy.seedPrice
        let before = g
        XCTAssertFalse(GardenEngine.buySeeds(.poppy, count: 3, in: &g))
        XCTAssertEqual(g, before)
    }

    func testBuyingExactlyAffordableLeavesZeroCoins() {
        var g = fresh()
        g.coins = 2 * FlowerType.daisy.seedPrice
        XCTAssertTrue(GardenEngine.buySeeds(.daisy, count: 2, in: &g))
        XCTAssertEqual(g.coins, 0)
        XCTAssertEqual(g.seedCount(.daisy), 5)
    }

    func testBuySeedsCountMathAcrossPurchases() {
        var g = fresh()
        XCTAssertTrue(GardenEngine.buySeeds(.daisy, count: 1, in: &g))
        XCTAssertTrue(GardenEngine.buySeeds(.daisy, count: 3, in: &g))
        XCTAssertEqual(g.seedCount(.daisy), 3 + 1 + 3)
        XCTAssertEqual(g.coins, Tuning.startingCoins - 4 * FlowerType.daisy.seedPrice)
    }

    func testBuyingZeroOrNegativeChangesNothing() {
        var g = fresh()
        let before = g
        XCTAssertFalse(GardenEngine.buySeeds(.daisy, count: 0, in: &g))
        XCTAssertFalse(GardenEngine.buySeeds(.daisy, count: -2, in: &g))
        XCTAssertEqual(g, before)
    }

    func testEveryTypeCanBeBoughtAtItsOwnPrice() {
        for f in FlowerType.allCases {
            var g = fresh()
            g.seeds = [:]
            g.coins = f.seedPrice
            XCTAssertTrue(GardenEngine.buySeeds(f, count: 1, in: &g), "\(f)")
            XCTAssertEqual(g.seedCount(f), 1)
            XCTAssertEqual(g.coins, 0)
        }
    }

    // MARK: Sowing

    /// Points on the patch, well apart from each other.
    let spots = [GroundPoint(x: 0.3, y: 0.3), GroundPoint(x: 0.6, y: 0.3), GroundPoint(x: 0.3, y: 0.6),
                 GroundPoint(x: 0.6, y: 0.6), GroundPoint(x: 0.45, y: 0.45)]

    func testSowConsumesOneSeedAndPlants() {
        var g = fresh()
        XCTAssertTrue(GardenEngine.sow(.daisy, at: spots[0], in: &g, now: t0))
        XCTAssertEqual(g.plants.first?.flower, .daisy)
        XCTAssertEqual(g.plants.first?.position, spots[0])
        XCTAssertEqual(g.seedCount(.daisy), 2)
        XCTAssertEqual(g.coins, Tuning.startingCoins, "sowing costs no coins")
    }

    func testSowFailsWithZeroSeedsAndChangesNothing() {
        var g = fresh()
        g.seeds = [:]
        let before = g
        XCTAssertFalse(GardenEngine.sow(.daisy, at: spots[0], in: &g, now: t0))
        XCTAssertEqual(g, before)
    }

    func testSowFailsForATypeTheGardenHasNoSeedsOf() {
        var g = fresh()
        XCTAssertFalse(GardenEngine.sow(.poppy, at: spots[0], in: &g, now: t0))
        XCTAssertTrue(g.plants.isEmpty)
        XCTAssertEqual(g.seedCount(.daisy), 3)
    }

    func testSowOnTopOfAPlantKeepsTheSeed() {
        var g = fresh()
        XCTAssertTrue(GardenEngine.sow(.daisy, at: spots[0], in: &g, now: t0))
        XCTAssertFalse(GardenEngine.sow(.daisy, at: GroundPoint(x: spots[0].x + 0.01, y: spots[0].y), in: &g, now: t0))
        XCTAssertEqual(g.seedCount(.daisy), 2)
    }

    func testSowingTheLastSeedLeavesNoSeeds() {
        var g = fresh()
        for p in spots.prefix(3) { XCTAssertTrue(GardenEngine.sow(.daisy, at: p, in: &g, now: t0)) }
        XCTAssertEqual(g.seedCount(.daisy), 0)
        XCTAssertEqual(g.seeds, [:])
        XCTAssertFalse(GardenEngine.sow(.daisy, at: spots[3], in: &g, now: t0))
    }

    func testSowingOverAWitheredPlantUsesASeedAndClearsIt() {
        var g = fresh()
        _ = GardenEngine.plant(.daisy, at: spots[4], in: &g, now: t0)
        g.plants[0].isDead = true
        XCTAssertTrue(GardenEngine.sow(.daisy, at: spots[4], in: &g, now: t0))
        XCTAssertEqual(g.seedCount(.daisy), 2)
        XCTAssertEqual(g.plants.count, 1, "the withered plant is replaced")
        XCTAssertFalse(g.plants[0].isDead)
    }

    func testPlainPlantIsFreeAndIgnoresInventory() {
        var g = fresh()
        let before = g
        XCTAssertTrue(GardenEngine.plant(.poppy, at: spots[1], in: &g, now: t0))
        XCTAssertEqual(g.seeds, before.seeds)
        XCTAssertEqual(g.coins, before.coins)
    }

    // MARK: Saves

    func testCodableRoundTripKeepsInventory() throws {
        var g = fresh()
        XCTAssertTrue(GardenEngine.buySeeds(.lettuce, count: 2, in: &g))
        XCTAssertTrue(GardenEngine.sow(.daisy, at: spots[0], in: &g, now: t0))
        let data = try JSONEncoder().encode(g)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"seedStock\""))
        let back = try JSONDecoder().decode(Garden.self, from: data)
        XCTAssertEqual(back, g)
        XCTAssertEqual(back.seedCount(.lettuce), 2)
        XCTAssertEqual(back.seedCount(.daisy), 2)
    }

    func testSaveWithoutInventoryDecodesWithNoSeeds() throws {
        let data = try JSONEncoder().encode(fresh())
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        obj.removeValue(forKey: "seedStock")
        let back = try JSONDecoder().decode(Garden.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertEqual(back.seeds, [:])
    }

    func testVersionFiveIsCurrentAndOlderVersionsAreNotCurrent() throws {
        XCTAssertEqual(Garden.currentVersion, 5)
        XCTAssertEqual(fresh().version, 5)
        let data = try JSONEncoder().encode(fresh())
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for old in [1, 3] {
            obj["version"] = old
            let saved = try JSONDecoder().decode(Garden.self, from: JSONSerialization.data(withJSONObject: obj))
            XCTAssertEqual(saved.version, old)
            XCTAssertNotEqual(saved.version, Garden.currentVersion, "the app discards it and starts fresh")
        }
    }

    // MARK: Debug tools stay outside the inventory

    func testDebugFillAndAdvanceDoNotTouchInventoryOrCoins() {
        var start = fresh()
        start.coins = 40
        start.seeds = [.daisy: 1, .basil: 4]
        let filled = DebugTools.fillWithPlants(garden: start, count: 5)
        XCTAssertEqual(filled.seeds, start.seeds)
        XCTAssertEqual(filled.coins, 40)
        XCTAssertEqual(filled.plants.count, 5)

        let aged = DebugTools.advance(garden: filled, days: 30, autoWater: true)
        XCTAssertEqual(aged.seeds, start.seeds)
        XCTAssertEqual(aged.coins, 40, "no harvest happens in debug fast-forward")
    }
}
