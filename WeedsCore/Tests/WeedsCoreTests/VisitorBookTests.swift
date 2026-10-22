import XCTest
@testable import WeedsCore

final class VisitorBookTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_699_999_200)

    func fresh() -> Garden { Garden(now: t0) }

    /// Records one sighting of each of the first `count` species in `VisitorSpecies.allCases` order.
    func spotted(_ count: Int) -> Garden {
        var g = fresh()
        for species in VisitorSpecies.allCases.prefix(count) {
            g.sightings[species.rawValue] = 1
        }
        return g
    }

    // MARK: Milestone table

    func testMilestoneThresholdsEndWithEverySpecies() {
        let all = VisitorMilestone.all
        XCTAssertEqual(all.map(\.species), [4, 8, VisitorSpecies.allCases.count])
        XCTAssertEqual(all.map(\.coins), [10, 15, 60])
        XCTAssertEqual(all[1].seeds, [.lavender: 2])
        XCTAssertEqual(all[2].seeds, [.chocolateLily: 3])
    }

    // MARK: Counting and reaching

    func testSpottedCountCountsDistinctSpecies() {
        var g = fresh()
        XCTAssertEqual(GardenEngine.spottedSpeciesCount(in: g), 0)
        g.sightings[VisitorSpecies.bee.rawValue] = 5
        g.sightings[VisitorSpecies.frog.rawValue] = 1
        XCTAssertEqual(GardenEngine.spottedSpeciesCount(in: g), 2)
    }

    func testNothingClaimableBelowFirstThreshold() {
        XCTAssertTrue(GardenEngine.claimableMilestones(in: spotted(3)).isEmpty)
    }

    func testMilestonesBecomeClaimableAtEachThreshold() {
        XCTAssertEqual(GardenEngine.claimableMilestones(in: spotted(4)).map(\.species), [4])
        XCTAssertEqual(GardenEngine.claimableMilestones(in: spotted(7)).map(\.species), [4])
        XCTAssertEqual(GardenEngine.claimableMilestones(in: spotted(8)).map(\.species), [4, 8])
        XCTAssertEqual(GardenEngine.claimableMilestones(in: spotted(11)).map(\.species), [4, 8])
        XCTAssertEqual(GardenEngine.claimableMilestones(in: spotted(12)).map(\.species),
                       [4, 8, VisitorSpecies.allCases.count])
    }

    // MARK: Claiming

    func testClaimPaysCoinsAndSeedsAndRecordsThreshold() {
        var g = spotted(8)
        let coins = g.coins
        XCTAssertTrue(GardenEngine.claimMilestone(VisitorMilestone.all[1], in: &g))
        XCTAssertEqual(g.coins, coins + 15)
        XCTAssertEqual(g.seedCount(.lavender), 2)
        XCTAssertEqual(g.claimedMilestones, [8])
    }

    func testClaimOfFirstMilestoneGivesCoinsOnly() {
        var g = spotted(4)
        let seedsBefore = g.seeds
        XCTAssertTrue(GardenEngine.claimMilestone(VisitorMilestone.all[0], in: &g))
        XCTAssertEqual(g.coins, Tuning.startingCoins + 10)
        XCTAssertEqual(g.seeds, seedsBefore)
    }

    func testFullBookRewardAddsChocolateLilySeeds() {
        var g = spotted(VisitorSpecies.allCases.count)
        XCTAssertTrue(GardenEngine.claimMilestone(VisitorMilestone.all[2], in: &g))
        XCTAssertEqual(g.seedCount(.chocolateLily), 3)
        XCTAssertEqual(g.seedCount(.daisy), Tuning.startingDaisySeeds)
        XCTAssertEqual(g.coins, Tuning.startingCoins + 60)
    }

    func testDoubleClaimIsRefused() {
        var g = spotted(4)
        XCTAssertTrue(GardenEngine.claimMilestone(VisitorMilestone.all[0], in: &g))
        let after = g
        XCTAssertFalse(GardenEngine.claimMilestone(VisitorMilestone.all[0], in: &g))
        XCTAssertEqual(g, after)
        XCTAssertEqual(g.coins, Tuning.startingCoins + 10)
        XCTAssertEqual(g.claimedMilestones, [4])
    }

    func testClaimBeforeReachedIsRefused() {
        var g = spotted(7)
        let before = g
        XCTAssertFalse(GardenEngine.claimMilestone(VisitorMilestone.all[1], in: &g))
        XCTAssertEqual(g, before)
    }

    func testClaimedMilestoneLeavesClaimableList() {
        var g = spotted(8)
        XCTAssertTrue(GardenEngine.claimMilestone(VisitorMilestone.all[0], in: &g))
        XCTAssertEqual(GardenEngine.claimableMilestones(in: g).map(\.species), [8])
    }

    // MARK: Saves

    func testClaimedMilestonesSurviveEncoding() throws {
        var g = spotted(8)
        XCTAssertTrue(GardenEngine.claimMilestone(VisitorMilestone.all[0], in: &g))
        let data = try JSONEncoder().encode(g)
        let decoded = try JSONDecoder().decode(Garden.self, from: data)
        XCTAssertEqual(decoded.claimedMilestones, [4])
        XCTAssertEqual(decoded, g)
    }

    func testOldSaveWithoutClaimedMilestonesDecodes() throws {
        let data = try JSONEncoder().encode(spotted(4))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "claimedMilestones")
        let old = try JSONSerialization.data(withJSONObject: object)
        let g = try JSONDecoder().decode(Garden.self, from: old)
        XCTAssertEqual(g.claimedMilestones, [])
        XCTAssertEqual(GardenEngine.claimableMilestones(in: g).map(\.species), [4])
    }
}
