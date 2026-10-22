import XCTest
@testable import WeedsCore

final class BedStyleTests: XCTestCase {
    typealias F = GardenFixture

    // MARK: Styles and regions

    func testStylesHaveNamesAndRawValues() {
        XCTAssertEqual(BedStyle.allCases, [.soilPatch, .mounds, .grid, .plantersBoxes])
        for style in BedStyle.allCases {
            XCTAssertFalse(style.displayName.isEmpty)
            XCTAssertFalse(style.blurb.isEmpty)
            XCTAssertEqual(BedStyle(rawValue: style.rawValue), style)
        }
        XCTAssertEqual(BedStyle.soilPatch.rawValue, "soilPatch")
    }

    func testRegionCountsPerStyle() {
        XCTAssertEqual(PlotShape(style: .soilPatch).regions.count, 1)
        XCTAssertEqual(PlotShape(style: .mounds).regions.count, 4)
        XCTAssertEqual(PlotShape(style: .grid).regions.count, 1)
        XCTAssertEqual(PlotShape(style: .plantersBoxes).regions.count, 3)
    }

    func testRegionCentresAreInsideEveryStyle() {
        for style in BedStyle.allCases {
            let plot = PlotShape(style: style)
            for region in plot.regions {
                XCTAssertTrue(plot.contains(region.centre, inset: 0.05), "\(style)")
            }
        }
    }

    func testCornersAreOutsideEveryStyle() {
        for style in BedStyle.allCases {
            let plot = PlotShape(style: style)
            XCTAssertFalse(plot.contains(GroundPoint(x: 0.02, y: 0.98)), "\(style)")
            XCTAssertFalse(plot.contains(GroundPoint(x: 0.98, y: 0.98)), "\(style)")
        }
    }

    func testLawnBetweenRegionsIsOutside() {
        XCTAssertFalse(PlotShape(style: .mounds).contains(GroundPoint(x: 0.5, y: 0.5)))
        XCTAssertFalse(PlotShape(style: .plantersBoxes).contains(GroundPoint(x: 0.5, y: 0.47)), "path between the rows")
        XCTAssertFalse(PlotShape(style: .plantersBoxes).contains(GroundPoint(x: 0.47, y: 0.2)), "path between the back boxes")
        XCTAssertFalse(PlotShape(style: .plantersBoxes).contains(GroundPoint(x: 0.85, y: 0.7)), "lawn beside the front box")
        XCTAssertFalse(PlotShape(style: .plantersBoxes).contains(GroundPoint(x: 0.05, y: 0.6)))
    }

    /// Every gap between two planter frames, and between two mounds, is at least 0.08 both ways (edge to edge).
    func testGapsBetweenRegionsAreClear() {
        let boxes = PlotShape(style: .plantersBoxes).regions
        for i in boxes.indices {
            for j in boxes.indices where j > i {
                XCTAssertGreaterThanOrEqual(frameGap(boxes[i], boxes[j]), 0.08 - 1e-9, "boxes \(i) and \(j)")
            }
        }
        let mounds = PlotShape(style: .mounds).regions
        for i in mounds.indices {
            for j in mounds.indices where j > i {
                XCTAssertGreaterThanOrEqual(ellipseGap(mounds[i], mounds[j]), 0.07, "mounds \(i) and \(j)")
            }
        }
    }

    /// The clear distance between two planter inside regions, counting the timber of both (each frame is one plank out).
    private func frameGap(_ a: BedRegion, _ b: BedRegion) -> Double {
        let t = PlotShape.plankThickness * 2
        let dx = max(b.centre.x - b.halfWidth - (a.centre.x + a.halfWidth),
                     a.centre.x - a.halfWidth - (b.centre.x + b.halfWidth))
        let dy = max(b.centre.y - b.halfHeight - (a.centre.y + a.halfHeight),
                     a.centre.y - a.halfHeight - (b.centre.y + b.halfHeight))
        return max(dx, dy) - t
    }

    /// The approximate clear distance between two mounds: the nearest point of one outside the other, sampled on
    /// the outline of the first.
    private func ellipseGap(_ a: BedRegion, _ b: BedRegion) -> Double {
        var best = Double.infinity
        for k in 0..<120 {
            let t = Double(k) / 120 * 2 * Double.pi
            let p = GroundPoint(x: a.centre.x + a.halfWidth * cos(t), y: a.centre.y + a.halfHeight * sin(t))
            best = min(best, -b.edgeDistance(p))
        }
        return best
    }

    func testInsetShrinksEveryRegion() {
        for style in BedStyle.allCases {
            let plot = PlotShape(style: style)
            for region in plot.regions {
                XCTAssertTrue(plot.contains(region.centre, inset: 0.05), "\(style)")
                XCTAssertFalse(plot.contains(region.centre, inset: 0.5), "\(style)")
            }
        }
    }

    func testPlanterPlanksKeepSoilOffTheTimber() {
        let plot = PlotShape(style: .plantersBoxes)
        XCTAssertEqual(PlotShape.plankThickness, 0.025)
        let front = plot.regions[2]
        XCTAssertTrue(plot.contains(GroundPoint(x: front.centre.x, y: front.centre.y)))
        XCTAssertFalse(plot.contains(GroundPoint(x: front.centre.x, y: front.centre.y - front.halfHeight - 0.005)),
                       "top plank")
        XCTAssertTrue(plot.contains(GroundPoint(x: front.centre.x, y: front.centre.y - front.halfHeight + 0.005)))
    }

    /// Every planter box, frame, full wall height and corner post (which stands above the rim) stays inside the visible
    /// frame with a margin of 0.05 on each side, in both the first-person and the backyard camera.
    func testPlanterBoxesStayInsideTheView() {
        let postTop = 0.075 * Camera.patchSide * (1 + 0.3)
        for camera in [Camera(), Camera.backyard] {
            for region in PlotShape(style: .plantersBoxes).regions {
                let t = PlotShape.plankThickness
                for x in [region.centre.x - region.halfWidth - t, region.centre.x + region.halfWidth + t] {
                    for y in [region.centre.y - region.halfHeight - t, region.centre.y + region.halfHeight + t] {
                        for h in [0, postTop] {
                            let q = camera.groundPoint(x: x, y: y, height: h)
                            XCTAssertTrue((0.05...0.95).contains(q.x), "x \(q.x) at \(x),\(y)")
                            XCTAssertTrue((0.05...0.95).contains(q.y), "y \(q.y) at \(x),\(y)")
                        }
                    }
                }
            }
        }
    }

    /// The corners of a box hold the posts, so nothing can be planted there.
    func testPlanterCornersAreOutside() {
        let plot = PlotShape(style: .plantersBoxes)
        var garden = Garden(now: F.t0)
        garden.plot.style = .plantersBoxes
        for region in plot.regions {
            for sx in [-1.0, 1.0] {
                for sy in [-1.0, 1.0] {
                    let corner = GroundPoint(x: region.centre.x + sx * (region.halfWidth - 0.01),
                                             y: region.centre.y + sy * (region.halfHeight - 0.01))
                    XCTAssertFalse(plot.contains(corner))
                    XCTAssertFalse(plot.contains(corner, inset: 0.01))
                    XCTAssertFalse(GardenEngine.canPlant(at: corner, in: garden))
                }
            }
            // Along the walls, away from the corners, the ground is still plantable.
            XCTAssertTrue(plot.contains(GroundPoint(x: region.centre.x, y: region.centre.y - region.halfHeight + 0.01)))
        }
    }

    /// Plants moved by a style switch land clear of the box corners.
    func testRelocatedPlantsAvoidPlanterCorners() {
        var g = Garden(now: F.t0)
        g.plants = (0..<12).map { F.plant(.daisy, id: $0 + 1, at: GroundPoint(x: 0.05 + 0.07 * Double($0), y: 0.98)) }
        g.nextID = 100
        GardenEngine.setBedStyle(.plantersBoxes, in: &g)
        let plot = PlotShape(style: .plantersBoxes)
        for plant in g.plants {
            XCTAssertTrue(plot.contains(plant.position))
            for region in plot.regions {
                let dx = region.halfWidth - abs(plant.position.x - region.centre.x)
                let dy = region.halfHeight - abs(plant.position.y - region.centre.y)
                XCTAssertFalse(dx < 0.03 && dy < 0.03 && region.edgeDistance(plant.position) >= 0, "plant \(plant.id) in a corner")
            }
        }
    }

    func testGridCornersAreRounded() {
        let grid = PlotShape(style: .grid)
        XCTAssertTrue(grid.contains(GroundPoint(x: 0.5, y: 0.2)))
        XCTAssertFalse(grid.contains(GroundPoint(x: 0.085, y: 0.195)))
    }

    func testEveryStyleIsWithinAQuarterOfTheOval() {
        let oval = PlotShape(style: .soilPatch).area
        for style in BedStyle.allCases {
            let ratio = PlotShape(style: style).area / oval
            XCTAssertLessThan(abs(ratio - 1), 0.25, "\(style) ratio \(ratio)")
        }
    }

    // MARK: point(seed:)

    func testPointAlwaysLandsInsideEveryStyle() {
        for style in BedStyle.allCases {
            let plot = PlotShape(style: style)
            for seed in 0..<300 {
                let s = UInt64(seed) &* 7919 &+ 3
                let p = plot.point(seed: s, inset: 0.03)
                XCTAssertTrue(plot.contains(p, inset: 0.03), "\(style) seed \(seed)")
                XCTAssertEqual(p, plot.point(seed: s, inset: 0.03))
            }
        }
    }

    func testPointsReachEveryRegion() {
        for style in [BedStyle.mounds, .plantersBoxes] {
            let plot = PlotShape(style: style)
            var hit = Array(repeating: false, count: plot.regions.count)
            for seed in 0..<200 {
                let p = plot.point(seed: UInt64(seed) &* 31 &+ 5)
                for (i, region) in plot.regions.enumerated() where region.edgeDistance(p) >= 0 { hit[i] = true }
            }
            XCTAssertTrue(hit.allSatisfy { $0 }, "\(style)")
        }
    }

    // MARK: Saves

    func testPlotJSONWithoutStyleLoadsAsSoilPatch() throws {
        let json = #"{"centre":{"x":0.5,"y":0.5},"rx":0.46,"ry":0.42}"#
        let plot = try JSONDecoder().decode(PlotShape.self, from: Data(json.utf8))
        XCTAssertEqual(plot.style, .soilPatch)
        XCTAssertEqual(plot, PlotShape())
    }

    func testOldGardenSaveWithoutStyleLoads() throws {
        let data = try JSONEncoder().encode(Garden(now: F.t0))
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var plot = try XCTUnwrap(root["plot"] as? [String: Any])
        plot.removeValue(forKey: "style")
        root["plot"] = plot
        let old = try JSONSerialization.data(withJSONObject: root)
        let garden = try XCTUnwrap(Garden.decodeSave(old))
        XCTAssertEqual(garden.plot.style, .soilPatch)
        XCTAssertEqual(garden.plot, PlotShape())
    }

    func testStyleSurvivesSaveRoundTrip() throws {
        var g = Garden(now: F.t0)
        g.plot.style = .plantersBoxes
        let data = try JSONEncoder().encode(g)
        XCTAssertEqual(Garden.decodeSave(data)?.plot.style, .plantersBoxes)
    }

    // MARK: Switching style

    func testSwitchingStyleMovesOutsidePlantsAndKeepsTheRest() {
        let inside = GroundPoint(x: 0.5, y: 0.5)
        let outside = GroundPoint(x: 0.3, y: 0.15)   // inside the soil oval, below the grid bed
        XCTAssertTrue(PlotShape().contains(outside, inset: Tuning.sowInset))
        XCTAssertFalse(PlotShape(style: .grid).contains(outside))

        var g = Garden(now: F.t0)
        g.plants = [F.plant(.daisy, id: 1, at: inside), F.plant(.daisy, id: 2, at: outside)]
        g.weeds = [Weed(id: 50, position: outside), Weed(id: 51, position: inside)]
        g.nextID = 60
        let seedsBefore = g.seedCount(.daisy)

        let change = GardenEngine.setBedStyle(.grid, in: &g)

        XCTAssertEqual(g.plot.style, .grid)
        XCTAssertEqual(change, GardenEngine.BedStyleChange(plantsMoved: 1, seedsReturned: 0, weedsRemoved: 1))
        XCTAssertEqual(g.plants.map(\.id), [1, 2])
        XCTAssertEqual(g.plants[0].position, inside)
        let moved = g.plants[1].position
        XCTAssertTrue(PlotShape(style: .grid).contains(moved, inset: Tuning.sowInset))
        XCTAssertGreaterThanOrEqual(moved.distance(to: inside), Tuning.sowSpacing)
        XCTAssertLessThan(moved.distance(to: outside), 0.1, "moved to the nearest spot")
        XCTAssertEqual(g.weeds.map(\.id), [51])
        XCTAssertEqual(g.seedCount(.daisy), seedsBefore)
    }

    func testWitheredPlantOutsideIsClearedWithoutASeed() {
        var dead = F.plant(.daisy, id: 1, at: GroundPoint(x: 0.3, y: 0.15))
        dead.isDead = true
        var g = Garden(now: F.t0)
        g.plants = [dead]
        let seedsBefore = g.seedCount(.daisy)

        let change = GardenEngine.setBedStyle(.grid, in: &g)

        XCTAssertEqual(change, GardenEngine.BedStyleChange(plantsMoved: 0, seedsReturned: 0, weedsRemoved: 0))
        XCTAssertTrue(g.plants.isEmpty)
        XCTAssertEqual(g.seedCount(.daisy), seedsBefore)
    }

    func testPlantWithNoRoomGoesBackToTheSeedStock() {
        // Pack every planter box's soil with plants on a lattice 0.05 apart (corners left out). Every point of a box is then within 0.035 of
        // a plant, closer than the sowing spacing, so a stray plant on the lawn between the boxes has nowhere to go.
        var packed: [Plant] = []
        for region in PlotShape(style: .plantersBoxes).regions {
            let inside = lattice(x0: region.centre.x - region.halfWidth, y0: region.centre.y - region.halfHeight,
                                 x1: region.centre.x + region.halfWidth, y1: region.centre.y + region.halfHeight,
                                 firstID: 100 + packed.count)
            packed += inside.filter { region.edgeDistance($0.position) >= Tuning.sowInset }
        }
        var g = Garden(now: F.t0)
        g.plants = [F.plant(.daisy, id: 1, at: GroundPoint(x: 0.5, y: 0.47))] + packed
        g.nextID = 1000
        let seedsBefore = g.seedCount(.daisy)

        let change = GardenEngine.setBedStyle(.plantersBoxes, in: &g)

        XCTAssertEqual(change, GardenEngine.BedStyleChange(plantsMoved: 0, seedsReturned: 1, weedsRemoved: 0))
        XCTAssertFalse(g.plants.contains { $0.id == 1 })
        XCTAssertEqual(g.plants.count, packed.count)
        XCTAssertEqual(g.seedCount(.daisy), seedsBefore + 1)
    }

    func testSwitchingStyleIsDeterministic() {
        var a = Garden(now: F.t0)
        a.plants = (0..<6).map { F.plant(.daisy, id: $0 + 1, at: GroundPoint(x: 0.1 + 0.12 * Double($0), y: 0.12)) }
        var b = a
        GardenEngine.setBedStyle(.mounds, in: &a)
        GardenEngine.setBedStyle(.mounds, in: &b)
        XCTAssertEqual(a, b)
    }

    /// Plants on a square lattice 0.05 apart, edges included, covering the rectangle (x0, y0)-(x1, y1).
    private func lattice(x0: Double, y0: Double, x1: Double, y1: Double, firstID: Int) -> [Plant] {
        let nx = Int(((x1 - x0) / 0.05).rounded(.up)), ny = Int(((y1 - y0) / 0.05).rounded(.up))
        var plants: [Plant] = []
        for i in 0...nx {
            for j in 0...ny {
                let p = GroundPoint(x: x0 + 0.011 + (x1 - x0 - 0.022) * Double(i) / Double(nx),
                                    y: y0 + 0.011 + (y1 - y0 - 0.022) * Double(j) / Double(ny))
                plants.append(F.plant(.daisy, id: firstID + plants.count, at: p))
            }
        }
        return plants
    }
}
