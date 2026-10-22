import XCTest
@testable import DharmaGardenCore

final class GardenAchievementTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    let t0 = Date(timeIntervalSince1970: 1_699_999_200)

    func day(_ n: Int, hour: Int = 0) -> Date {
        calendar.date(byAdding: .hour, value: hour, to: calendar.date(byAdding: .day, value: n, to: calendar.startOfDay(for: t0))!)!
    }

    // MARK: Daily visits

    func testFirstOpenStartsTheStreak() {
        var g = Garden(now: t0)
        XCTAssertTrue(GardenEngine.recordOpen(in: &g, now: day(0, hour: 9), calendar: calendar))
        XCTAssertEqual(g.openStreak, 1)
    }

    func testOpeningAgainTheSameDayChangesNothing() {
        var g = Garden(now: t0)
        GardenEngine.recordOpen(in: &g, now: day(0, hour: 9), calendar: calendar)
        XCTAssertFalse(GardenEngine.recordOpen(in: &g, now: day(0, hour: 22), calendar: calendar))
        XCTAssertEqual(g.openStreak, 1)
    }

    func testConsecutiveDaysExtendTheStreak() {
        var g = Garden(now: t0)
        for n in 0..<7 { GardenEngine.recordOpen(in: &g, now: day(n, hour: 12), calendar: calendar) }
        XCTAssertEqual(g.openStreak, 7)
    }

    func testAMissedDayRestartsTheStreak() {
        var g = Garden(now: t0)
        for n in 0..<3 { GardenEngine.recordOpen(in: &g, now: day(n), calendar: calendar) }
        GardenEngine.recordOpen(in: &g, now: day(5), calendar: calendar)
        XCTAssertEqual(g.openStreak, 1)
    }

    func testAClockSetBackKeepsTheStreak() {
        var g = Garden(now: t0)
        for n in 0..<3 { GardenEngine.recordOpen(in: &g, now: day(n), calendar: calendar) }
        XCTAssertFalse(GardenEngine.recordOpen(in: &g, now: day(-4), calendar: calendar))
        XCTAssertEqual(g.openStreak, 3)
    }

    // MARK: Earned goals

    func testFreshGardenHasEarnedNothing() {
        XCTAssertTrue(GardenAchievement.earned(in: Garden(now: t0)).isEmpty)
    }

    func testFirstBloomNeedsAFullyGrownPlant() {
        var g = Garden(now: t0)
        g.plants = [Plant(id: 1, flower: .daisy, position: GroundPoint(x: 0.5, y: 0.5))]
        g.plants[0].progress = 0.9
        XCTAssertFalse(GardenAchievement.earned(in: g).contains(.firstBloom))
        g.plants[0].progress = 1
        XCTAssertTrue(GardenAchievement.earned(in: g).contains(.firstBloom))
    }

    func testClaimedMilestonesEarnTheirAchievements() {
        var g = Garden(now: t0)
        g.claimedMilestones = [4, VisitorSpecies.allCases.count]
        XCTAssertEqual(GardenAchievement.earned(in: g), [.fourVisitors, .fullBook])
    }

    func testWeekStreakNeedsSevenDays() {
        var g = Garden(now: t0)
        g.openStreak = 6
        XCTAssertFalse(GardenAchievement.earned(in: g).contains(.weekStreak))
        g.openStreak = 7
        XCTAssertTrue(GardenAchievement.earned(in: g).contains(.weekStreak))
    }

    func testIdentifiersAreUnique() {
        XCTAssertEqual(Set(GardenAchievement.allCases.map(\.identifier)).count, GardenAchievement.allCases.count)
    }

    func testMilestoneAchievementsMatchTheMilestoneTable() {
        let mirrored = GardenAchievement.allCases.compactMap(\.milestoneSpecies)
        XCTAssertEqual(mirrored, VisitorMilestone.all.map(\.species))
    }

    func testOldSavesLoadWithNoStreak() throws {
        let data = try JSONEncoder().encode(Garden(now: t0))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "lastOpenedAt")
        json.removeValue(forKey: "openStreak")
        let old = try JSONSerialization.data(withJSONObject: json)
        let g = try XCTUnwrap(Garden.decodeSave(old))
        XCTAssertEqual(g.openStreak, 0)
        XCTAssertNil(g.lastOpenedAt)
    }
}
