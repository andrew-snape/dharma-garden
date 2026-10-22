import XCTest
import SwiftUI
import DharmaGardenCore
@testable import DharmaGardenArt

/// Depth order, seed ghost rules, feedback rings, and the always-run render checks for the free-form scene.
@MainActor
final class SceneTests: XCTestCase {
    private func plant(_ id: Int, _ f: FlowerType, at p: GroundPoint) -> Plant {
        Plant(id: id, flower: f, position: p, plantSeed: 1 << 63, moisture: 80)
    }

    func testDepthOrderIsBackToFrontAcrossPlantsAndDharmaGarden() {
        var g = Garden(now: GardenFixture.t0)
        g.plants = [plant(1, .daisy, at: GroundPoint(x: 0.3, y: 0.8)),
                    plant(2, .poppy, at: GroundPoint(x: 0.6, y: 0.2)),
                    plant(3, .basil, at: GroundPoint(x: 0.5, y: 0.5))]
        g.weeds = [Weed(id: 4, position: GroundPoint(x: 0.4, y: 0.35)),
                   Weed(id: 5, position: GroundPoint(x: 0.1, y: 0.95))]
        let order = SceneContent.depthOrder(of: g)
        XCTAssertEqual(order.map(\.id), [2, 4, 3, 1, 5], "smaller y (further back) first")
        XCTAssertEqual(order.map(\.isPlant), [true, false, true, true, false])
        XCTAssertEqual(order.map(\.depth), order.map(\.depth).sorted())
    }

    func testDepthOrderBreaksTiesByIdAndIsEmptyForAnEmptyGarden() {
        XCTAssertTrue(SceneContent.depthOrder(of: Garden(now: GardenFixture.t0)).isEmpty)
        var g = Garden(now: GardenFixture.t0)
        let same = GroundPoint(x: 0.5, y: 0.5)
        g.plants = [plant(7, .daisy, at: same), plant(2, .daisy, at: same)]
        XCTAssertEqual(SceneContent.depthOrder(of: g).map(\.id), [2, 7])
    }

    func testSeedSpotsNeedThePatchAndClearOfPlants() {
        var g = Garden(now: GardenFixture.t0)
        g.plants = [plant(1, .daisy, at: GroundPoint(x: 0.5, y: 0.5))]
        XCTAssertTrue(GardenEngine.canPlant(at: GroundPoint(x: 0.5, y: 0.7), in: g))
        XCTAssertFalse(GardenEngine.canPlant(at: GroundPoint(x: 0.5, y: 0.52), in: g), "on top of a plant")
        XCTAssertFalse(GardenEngine.canPlant(at: GroundPoint(x: 0.02, y: 0.02), in: g), "off the patch")
    }

    func testRingsAreActiveOnlyWithinTheirDuration() {
        let start = GardenFixture.t0
        let rings = [SceneRipple(point: GroundPoint(x: 0.5, y: 0.5), startedAt: start, kind: .water),
                     SceneRipple(point: GroundPoint(x: 0.2, y: 0.2), startedAt: start, kind: .pick)]
        XCTAssertEqual(SceneContent.activeRings(rings, now: start.addingTimeInterval(-1)).count, 0, "not started")
        let mid = SceneContent.activeRings(rings, now: start.addingTimeInterval(0.45))
        XCTAssertEqual(mid.count, 2)
        XCTAssertEqual(mid.first(where: { $0.kind == .pick })?.progress ?? -1, 0.5, accuracy: 1e-6)
        let late = SceneContent.activeRings(rings, now: start.addingTimeInterval(1.0))
        XCTAssertEqual(late.map(\.kind), [.water], "the pick ring has finished, the water ring is still going")
        XCTAssertEqual(SceneContent.activeRings(rings, now: start.addingTimeInterval(2)).count, 0)
    }

    func testWaterRingSpreadsWiderThanOtherRings() {
        XCTAssertGreaterThan(SceneRipple(point: GroundPoint(x: 0, y: 0), startedAt: .distantPast, kind: .water).maxRadius,
                             SceneRipple(point: GroundPoint(x: 0, y: 0), startedAt: .distantPast, kind: .plant).maxRadius)
        XCTAssertGreaterThan(SceneRipple(point: GroundPoint(x: 0, y: 0), startedAt: .distantPast, kind: .water).duration,
                             SceneRipple(point: GroundPoint(x: 0, y: 0), startedAt: .distantPast, kind: .pull).duration)
    }

    func testDharmaGardenGrowWithAge() {
        XCTAssertLessThan(SceneContent.weedGrowth(ageHours: 0), SceneContent.weedGrowth(ageHours: 48))
        XCTAssertEqual(SceneContent.weedGrowth(ageHours: 10_000), 1, accuracy: 1e-12)
    }

    /// Always runs: both styles render with a seed ghost (valid and not) and a ripple, in every weather state.
    func testBothStylesRenderGhostAndRipplesInEveryCondition() throws {
        let garden = SceneRenderTests.sampleGarden()
        let now = GardenFixture.t0
        for style in SceneStyle.allCases {
            for condition in [WeatherCondition.clear, .fog, .rain, .thunderstorm, .snow] {
                for phase in [SunPhase.day, .night] {
                    let palette = ScenePalette.resolve(season: .winter, phase: phase, condition: condition,
                                                       temperatureC: 1, cloudCover: 50)
                    for valid in [true, false] {
                        let view = SceneContent(garden: garden, palette: palette, camera: Camera(),
                                                hoverPoint: GroundPoint(x: 0.4, y: 0.6),
                                                ghostFlower: .lavender, ghostValid: valid,
                                                ripples: [SceneRipple(point: GroundPoint(x: 0.5, y: 0.5),
                                                                      startedAt: now, kind: .pick)],
                                                now: now.addingTimeInterval(0.2),
                                                motion: SceneMotion.Frame(time: 3, wind: 0.4, enabled: true),
                                                style: style)
                            .frame(width: 640, height: 480)
                        let r = ImageRenderer(content: view)
                        r.scale = 1
                        XCTAssertNotNil(r.nsImage, "\(style) \(condition) \(phase) valid \(valid)")
                    }
                }
            }
        }
    }
}
