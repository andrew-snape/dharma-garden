import XCTest
@testable import WeedsCore

final class VisitorMotionTests: XCTestCase {
    static let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    static let perch = GroundPoint(x: 0.4, y: 0.6)

    func visitor(_ s: VisitorSpecies, id: Int = 7, at p: GroundPoint = perch, life: TimeInterval = 40) -> Visitor {
        Visitor(id: id, species: s, position: p, spawnedAt: Self.t0, lifetime: life)
    }

    /// Evenly spaced times from spawn to departure, inclusive.
    func samples(_ v: Visitor, count: Int = 60) -> [Date] {
        (0...count).map { v.spawnedAt.addingTimeInterval(v.lifetime * Double($0) / Double(count)) }
    }

    /// Species that hover over the patch at a steady height.
    let flyers: [VisitorSpecies] = [.bee, .cabbageWhiteButterfly, .orangeButterfly, .dragonfly, .moth]
    /// Creatures that stay on the lawn.
    let groundCreatures: [VisitorSpecies] = [.blueTongueLizard, .snail, .frog, .ladybird]
    let birds: [VisitorSpecies] = [.magpieLark, .willieWagtail, .cockatoo]

    func testSamePoseForTheSameVisitorAndTime() {
        for s in VisitorSpecies.allCases {
            let t = Self.t0.addingTimeInterval(13.7)
            let v = visitor(s)
            XCTAssertEqual(VisitorMotion.pose(of: v, at: t), VisitorMotion.pose(of: v, at: t), "\(s)")
            XCTAssertEqual(VisitorMotion.pose(of: v, at: t), VisitorMotion.pose(of: visitor(s), at: t), "\(s) copy")
        }
    }

    func testVisitorsArriveFromDifferentEdges() {
        let starts = (1...20).map { VisitorMotion.pose(of: visitor(.bee, id: $0), at: Self.t0).position }
        XCTAssertTrue(starts.contains { $0 != starts[0] }, "ids should spread arrivals around the lawn")
    }

    func testStartsAndEndsFadedOutAndIsFullyVisibleInTheStay() {
        for s in VisitorSpecies.allCases {
            let v = visitor(s)
            XCTAssertEqual(VisitorMotion.pose(of: v, at: v.spawnedAt).opacity, 0, accuracy: 1e-9, "\(s) arrives")
            XCTAssertEqual(VisitorMotion.pose(of: v, at: v.departsAt).opacity, 0, accuracy: 1e-9, "\(s) leaves")
            let mid = v.spawnedAt.addingTimeInterval(v.lifetime / 2)
            XCTAssertEqual(VisitorMotion.pose(of: v, at: mid).opacity, 1, accuracy: 1e-9, "\(s) mid stay")
        }
    }

    func testFadesInOnArrivalAndOutOnLeaving() {
        for s in VisitorSpecies.allCases {
            let v = visitor(s)
            let n = 40
            let arrival = (0...n).map { k in
                VisitorMotion.pose(of: v, at: v.spawnedAt.addingTimeInterval(v.lifetime * VisitorMotion.transitShare * Double(k) / Double(n))).opacity
            }
            XCTAssertTrue(zip(arrival, arrival.dropFirst()).allSatisfy { $0 <= $1 + 1e-12 }, "\(s) fades in")
            let leaving = (0...n).map { k in
                VisitorMotion.pose(of: v, at: v.spawnedAt.addingTimeInterval(v.lifetime * (1 - VisitorMotion.transitShare * (1 - Double(k) / Double(n))))).opacity
            }
            XCTAssertTrue(zip(leaving, leaving.dropFirst()).allSatisfy { $0 >= $1 - 1e-12 }, "\(s) fades out")
        }
    }

    func testStaysWithinTheGroundSquare() {
        for s in VisitorSpecies.allCases {
            for id in 1...5 {
                for t in samples(visitor(s, id: id)) {
                    let p = VisitorMotion.pose(of: visitor(s, id: id), at: t).position
                    XCTAssertTrue((0...1).contains(p.x) && (0...1).contains(p.y), "\(s) \(id) at \(p)")
                }
            }
        }
    }

    func testArrivesFromAndLeavesToTheLawnEdge() {
        for s in VisitorSpecies.allCases {
            for id in 1...5 {
                let v = visitor(s, id: id)
                for t in [v.spawnedAt, v.departsAt] {
                    let p = VisitorMotion.pose(of: v, at: t).position
                    let edge = min(p.x, 1 - p.x, p.y, 1 - p.y)
                    XCTAssertLessThan(edge, 1e-9, "\(s) \(id) starts or ends on the edge")
                }
            }
        }
    }

    func testFlyersHoverAboveTheLawn() {
        for s in flyers {
            for t in samples(visitor(s)) {
                XCTAssertGreaterThan(VisitorMotion.pose(of: visitor(s), at: t).height, 0, "\(s)")
            }
        }
    }

    func testGroundCreaturesStayOnTheLawn() {
        for s in groundCreatures {
            for t in samples(visitor(s)) {
                XCTAssertEqual(VisitorMotion.pose(of: visitor(s), at: t).height, 0, "\(s)")
            }
        }
    }

    func testBirdsLiftOnlyWhileMoving() {
        for s in birds {
            for t in samples(visitor(s)) {
                let p = VisitorMotion.pose(of: visitor(s), at: t)
                if p.isMoving {
                    XCTAssertGreaterThan(p.height, 0, "\(s) moving")
                } else {
                    XCTAssertEqual(p.height, 0, "\(s) pecking on the lawn")
                }
            }
        }
    }

    func testReachesThePerchMidLifetime() {
        for s in VisitorSpecies.allCases {
            let v = visitor(s)
            let mid = v.spawnedAt.addingTimeInterval(v.lifetime / 2)
            let p = VisitorMotion.pose(of: v, at: mid).position
            XCTAssertLessThanOrEqual(p.distance(to: Self.perch), 0.05, "\(s)")
        }
    }

    func testStillSpeciesSitExactlyOnThePerch() {
        for s in [VisitorSpecies.blueTongueLizard, .frog, .moth, .magpieLark, .willieWagtail, .cockatoo] {
            let v = visitor(s)
            let mid = v.spawnedAt.addingTimeInterval(v.lifetime / 2)
            XCTAssertEqual(VisitorMotion.pose(of: v, at: mid).position, Self.perch, "\(s)")
        }
    }

    func testSnailCrawlsVerySlowly() {
        let v = visitor(.snail)
        let early = VisitorMotion.pose(of: v, at: v.spawnedAt.addingTimeInterval(v.lifetime * 0.3)).position
        let late = VisitorMotion.pose(of: v, at: v.spawnedAt.addingTimeInterval(v.lifetime * 0.7)).position
        XCTAssertLessThan(early.distance(to: late), 0.05)
        XCTAssertGreaterThan(early.distance(to: late), 0, "it still moves")
    }

    func testBeesHopToASecondSpotMidStay() {
        let v = visitor(.bee)
        let before = VisitorMotion.pose(of: v, at: v.spawnedAt.addingTimeInterval(v.lifetime * 0.3)).position
        let after = VisitorMotion.pose(of: v, at: v.spawnedAt.addingTimeInterval(v.lifetime * 0.7)).position
        XCTAssertEqual(before, Self.perch)
        XCTAssertGreaterThan(after.distance(to: Self.perch), 0.005)
        XCTAssertLessThan(after.distance(to: Self.perch), 0.05, "a nearby spot")
    }

    func testFacingIsLeftOrRight() {
        for s in VisitorSpecies.allCases {
            for t in samples(visitor(s), count: 20) {
                XCTAssertTrue([-1.0, 1.0].contains(VisitorMotion.pose(of: visitor(s), at: t).facing), "\(s)")
            }
        }
    }

    func testPhaseAdvancesWithTime() {
        let v = visitor(.bee)
        let a = VisitorMotion.pose(of: v, at: v.spawnedAt.addingTimeInterval(20)).phase
        let b = VisitorMotion.pose(of: v, at: v.spawnedAt.addingTimeInterval(21)).phase
        XCTAssertEqual(b - a, 1, accuracy: 1e-9)
    }
}
