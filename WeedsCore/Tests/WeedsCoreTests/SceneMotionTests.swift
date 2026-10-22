import XCTest
import SwiftUI
import WeedsCore
@testable import WeedsArt

@MainActor
final class SceneMotionTests: XCTestCase {
    /// Sample times across several minutes, in fractions of a second, to cover the slow sine periods.
    let times: [Double] = stride(from: 0.0, through: 900.0, by: 0.37).map { $0 }

    // MARK: Drift

    func testDriftStaysWithinBounds() {
        let maxOffset = SceneMotion.driftOffsetAmplitude * 1.5 + 1e-12
        let maxPitch = SceneMotion.driftPitchAmplitudeDegrees * 1.5 + 1e-12
        for wind in [0.0, 0.5, 1.0] {
            for t in times {
                let d = SceneMotion.drift(at: t, wind: wind)
                XCTAssertLessThanOrEqual(abs(d.offsetX), maxOffset, "x at t=\(t) wind=\(wind)")
                XCTAssertLessThanOrEqual(abs(d.offsetY), maxOffset, "y at t=\(t) wind=\(wind)")
                XCTAssertLessThanOrEqual(abs(d.pitchDegrees), maxPitch, "pitch at t=\(t) wind=\(wind)")
            }
        }
    }

    func testDriftIsDeterministic() {
        for t in [0.0, 3.25, 17.5, 123.456] {
            let a = SceneMotion.drift(at: t, wind: 0.4)
            let b = SceneMotion.drift(at: t, wind: 0.4)
            XCTAssertEqual(a.offsetX, b.offsetX)
            XCTAssertEqual(a.offsetY, b.offsetY)
            XCTAssertEqual(a.pitchDegrees, b.pitchDegrees)
        }
    }

    func testDriftActuallyMoves() {
        let a = SceneMotion.drift(at: 2, wind: 0.25)
        let b = SceneMotion.drift(at: 6, wind: 0.25)
        XCTAssertNotEqual(a.offsetX, b.offsetX)
        XCTAssertNotEqual(a.pitchDegrees, b.pitchDegrees)
    }

    func testWindScalesDriftAmplitudeByOnePointFive() {
        for t in times.prefix(400) {
            let calm = SceneMotion.drift(at: t, wind: 0)
            let gusty = SceneMotion.drift(at: t, wind: 1)
            XCTAssertEqual(gusty.offsetX, 1.5 * calm.offsetX, accuracy: 1e-12)
            XCTAssertEqual(gusty.offsetY, 1.5 * calm.offsetY, accuracy: 1e-12)
            XCTAssertEqual(gusty.pitchDegrees, 1.5 * calm.pitchDegrees, accuracy: 1e-12)
        }
        let calmMax = times.map { abs(SceneMotion.drift(at: $0, wind: 0).offsetX) }.max()!
        let gustyMax = times.map { abs(SceneMotion.drift(at: $0, wind: 1).offsetX) }.max()!
        XCTAssertGreaterThan(calmMax, 0, "calm air still drifts")
        XCTAssertEqual(gustyMax / calmMax, 1.5, accuracy: 0.05)
    }

    // MARK: Parallax

    func testParallaxMultipliersAreOrderedByDepth() {
        let layers: [SceneMotion.Layer] = [.sky, .hills, .fence, .ground, .foreground]
        XCTAssertEqual(layers.map(\.multiplier), [0.15, 0.3, 0.6, 1.0, 1.6])
        XCTAssertEqual(layers.map(\.multiplier), layers.map(\.multiplier).sorted())
    }

    func testLayerShiftScalesTheDrift() {
        let frame = SceneMotion.Frame(time: 5, wind: 0.5, enabled: true)
        let shift = frame.layerShift(.foreground)
        XCTAssertEqual(shift.x, frame.offsetX * 1.6, accuracy: 1e-12)
        XCTAssertEqual(shift.y, frame.offsetY * 1.6, accuracy: 1e-12)
    }

    // MARK: Sway

    func testSwayStaysWithinMinusOneToOne() {
        for seed in [UInt64(0), 1, 42, 0xDEAD_BEEF] {
            for wind in [0.0, 0.5, 1.0] {
                for t in times.prefix(500) {
                    let s = SceneMotion.sway(at: t, plantSeed: seed, wind: wind)
                    XCTAssertTrue((-1.0...1.0).contains(s), "sway \(s) out of range")
                }
            }
        }
    }

    func testSwayGrowsWithWind() {
        let calm = (0..<200).map { abs(SceneMotion.sway(at: Double($0) * 0.1, plantSeed: 7, wind: 0)) }.max()!
        let windy = (0..<200).map { abs(SceneMotion.sway(at: Double($0) * 0.1, plantSeed: 7, wind: 1)) }.max()!
        XCTAssertGreaterThan(calm, 0, "a little sway when calm")
        XCTAssertLessThan(calm, 0.2, "still gentle when calm")
        XCTAssertGreaterThan(windy, 0.9, "strong sway in strong wind")
    }

    func testDifferentPlantsSwayDifferently() {
        var differing = 0
        for t in [0.5, 1.0, 2.0, 3.0, 5.0, 8.0] {
            let a = SceneMotion.sway(at: t, plantSeed: 1, wind: 0.8)
            let b = SceneMotion.sway(at: t, plantSeed: 2, wind: 0.8)
            if abs(a - b) > 1e-6 { differing += 1 }
        }
        XCTAssertGreaterThanOrEqual(differing, 5, "neighbouring seeds do not sway in step")
    }

    // MARK: Still frames

    func testDisabledFrameIsTheStaticFrame() {
        let frozen = SceneMotion.Frame(time: 9, wind: 1, enabled: false)
        XCTAssertEqual(frozen, SceneMotion.Frame.still)
        XCTAssertEqual(frozen.offsetX, 0)
        XCTAssertEqual(frozen.offsetY, 0)
        XCTAssertEqual(frozen.pitchDegrees, 0)
        XCTAssertEqual(frozen.sway(plantSeed: 99), 0)
        XCTAssertEqual(frozen.cloudTravel, 0)
        XCTAssertEqual(frozen.rainFall(strength: 1), 0)
        XCTAssertEqual(frozen.fogPulse, 1)
    }

    func testDisabledFrameGivesTheBaseCameraExactly() {
        let base = Camera()
        let cam = SceneMotion.camera(base, frame: SceneMotion.Frame(time: 9, wind: 1, enabled: false))
        for p in Self.groundSamples {
            let a = base.groundPoint(x: p.x, y: p.y)
            let b = cam.groundPoint(x: p.x, y: p.y)
            XCTAssertEqual(a.x, b.x, accuracy: 1e-12)
            XCTAssertEqual(a.y, b.y, accuracy: 1e-12)
        }
    }

    // MARK: Camera and hit testing

    func testDriftMovesTheGardenCentreByTheDriftOffset() {
        let base = Camera()
        let frame = SceneMotion.Frame(time: 5, wind: 0.25, enabled: true)
        let cam = SceneMotion.camera(base, frame: frame)
        let moved = cam.project(x: 0, z: 0).x - base.project(x: 0, z: 0).x
        // Vertical drift changes the eye's depth a little, which nudges x too, so this is close rather than exact.
        XCTAssertEqual(moved, frame.offsetX, accuracy: 1e-4)
    }

    /// A spread of ground points across the patch.
    static let groundSamples: [GroundPoint] = stride(from: 0.1, through: 0.9, by: 0.2).flatMap { x in
        stride(from: 0.1, through: 0.9, by: 0.2).map { y in GroundPoint(x: x, y: y) }
    }

    func testTapHitsTheGroundPointTheDriftedCameraDraws() {
        let base = Camera()
        for t in [0.0, 4.5, 9.0, 20.0, 333.3] {
            let frame = SceneMotion.Frame(time: t, wind: 0.25, enabled: true)
            let cam = SceneMotion.camera(base, frame: frame)
            for p in Self.groundSamples {
                let c = cam.groundPoint(x: p.x, y: p.y)
                let hit = cam.groundPoint(atScreen: (x: c.x, y: c.y))
                XCTAssertEqual(hit?.x ?? -1, p.x, accuracy: 1e-9, "t=\(t)")
                XCTAssertEqual(hit?.y ?? -1, p.y, accuracy: 1e-9, "t=\(t)")
            }
        }
    }

    // MARK: Clouds

    func testCloudWrapStaysInRangeAndIsContinuous() {
        var x = -0.3
        while x < 1.5 {
            let w = SceneMotion.wrapCloudX(x)
            XCTAssertTrue(w >= -0.2 && w < 1.2, "wrapped \(w) from \(x)")
            x += 0.013
        }
        XCTAssertEqual(SceneMotion.wrapCloudX(0.3), 0.3, accuracy: 1e-12, "in range is unchanged")
    }

    // MARK: Render

    /// Renders the same garden at t=0 and t=9 side by side into SCENE_MOTION_PATH, to judge the motion by eye.
    func testRenderMotionSideBySide() throws {
        guard let out = ProcessInfo.processInfo.environment["SCENE_MOTION_PATH"] else { return }
        let palette = ScenePalette.resolve(season: .summer, phase: .day, condition: .clear,
                                           temperatureC: 26, cloudCover: 30)
        let garden = SceneRenderTests.sampleGarden()
        let pair = HStack(spacing: 0) {
            SceneContent(garden: garden, palette: palette, camera: Camera(),
                         motion: SceneMotion.Frame(time: 0, wind: 0.25, enabled: true))
                .frame(width: 960, height: 720)
            SceneContent(garden: garden, palette: palette, camera: Camera(),
                         motion: SceneMotion.Frame(time: 9, wind: 0.25, enabled: true))
                .frame(width: 960, height: 720)
        }
        let r = ImageRenderer(content: pair)
        r.scale = 1
        let img = try XCTUnwrap(r.nsImage)
        let tiff = try XCTUnwrap(img.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: out)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
    }
}
