import XCTest
import SwiftUI
import WeedsCore
@testable import WeedsArt

/// Shadow direction, length and opacity from the sun, plus a render of the scene at four times of day.
@MainActor
final class SceneLightingTests: XCTestCase {
    func sun(elevation: Double, azimuth: Double, intensity: Double = 1, warmth: Double = 0) -> SunLight {
        SunLight(elevationDegrees: elevation, azimuthDegrees: azimuth, intensity: intensity, warmth: warmth)
    }

    func testShadowLengthDecreasesAsSunRises() {
        let lengths = [40.0, 50, 60, 80].map { SceneLighting.shadowLength(elevationDegrees: $0) }
        for (a, b) in zip(lengths, lengths.dropFirst()) {
            XCTAssertGreaterThan(a, b)
        }
        XCTAssertEqual(SceneLighting.shadowLength(elevationDegrees: 60), 1 / tan(60 * .pi / 180), accuracy: 1e-9)
    }

    func testShadowLengthIsCapped() {
        XCTAssertEqual(SceneLighting.shadowLength(elevationDegrees: 5), SceneLighting.maxShadowLength)
        XCTAssertEqual(SceneLighting.shadowLength(elevationDegrees: 3), SceneLighting.maxShadowLength)
        XCTAssertEqual(SceneLighting.maxShadowLength, 1.3)
    }

    func testNoShadowsAtNight() {
        XCTAssertEqual(SceneLighting.shadowLength(elevationDegrees: -5), 0)
        XCTAssertEqual(SceneLighting.shadowLength(elevationDegrees: 0), 0)
        XCTAssertNil(SceneLighting.shadowDirection(for: sun(elevation: -5, azimuth: 300, intensity: 0)))
        XCTAssertNil(SceneLighting.shadowDirection(for: sun(elevation: 40, azimuth: 90, intensity: 0)),
                     "no direct light means no shadow")
        XCTAssertEqual(SceneLighting.shadowOpacity(for: sun(elevation: -5, azimuth: 300, intensity: 0)), 0)
    }

    func testShadowDirectionIsUnitLength() {
        for az in stride(from: 0.0, to: 360, by: 37) {
            let d = try? XCTUnwrap(SceneLighting.shadowDirection(for: sun(elevation: 40, azimuth: az)))
            XCTAssertNotNil(d)
            XCTAssertEqual(hypot(d?.x ?? 0, d?.y ?? 0), 1, accuracy: 1e-9)
        }
    }

    func testShadowFallsOppositeTheSun() {
        // Camera looks west (default). Sun in the east: shadow goes west, away from the viewer, so up the screen.
        let fromEast = SceneLighting.shadowDirection(for: sun(elevation: 20, azimuth: 90))!
        XCTAssertEqual(fromEast.x, 0, accuracy: 1e-9)
        XCTAssertEqual(fromEast.y, -1, accuracy: 1e-9)

        // Sun in the west (dusk): shadow comes toward the viewer, down the screen.
        let fromWest = SceneLighting.shadowDirection(for: sun(elevation: 14, azimuth: 270))!
        XCTAssertEqual(fromWest.y, 1, accuracy: 1e-9)

        // Sun due north is on the viewer's right, so its shadow falls to the left.
        let fromNorth = SceneLighting.shadowDirection(for: sun(elevation: 60, azimuth: 0))!
        XCTAssertEqual(fromNorth.x, -1, accuracy: 1e-9)
        XCTAssertEqual(fromNorth.y, 0, accuracy: 1e-9)
    }

    func testShadowDirectionOppositeForOpposingSun() {
        for az in stride(from: 0.0, to: 360, by: 45) {
            let a = SceneLighting.shadowDirection(for: sun(elevation: 30, azimuth: az))!
            let b = SceneLighting.shadowDirection(for: sun(elevation: 30, azimuth: az + 180))!
            XCTAssertEqual(a.x, -b.x, accuracy: 1e-9)
            XCTAssertEqual(a.y, -b.y, accuracy: 1e-9)
        }
    }

    func testCameraFacingIsConfigurable() {
        // Camera looks north: east is on the right, so an eastern sun throws its shadow to the left.
        let d = SceneLighting.shadowDirection(for: sun(elevation: 30, azimuth: 90), cameraFacingAzimuth: 0)!
        XCTAssertEqual(d.x, -1, accuracy: 1e-9)
        XCTAssertEqual(d.y, 0, accuracy: 1e-9)
    }

    func testPlantGrowthIsFullForSeedHeads() {
        XCTAssertEqual(SceneLighting.plantGrowth(progress: 0.1, isSeedHead: true), 1)
        XCTAssertLessThan(SceneLighting.plantGrowth(progress: 0.2), SceneLighting.plantGrowth(progress: 0.9))
    }

    // MARK: Render

    private func pngData<V: View>(_ view: V) throws -> Data {
        let r = ImageRenderer(content: view)
        r.scale = 1
        let img = try XCTUnwrap(r.nsImage)
        let tiff = try XCTUnwrap(img.tiffRepresentation)
        return try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }

    /// Writes morning, noon, dusk and overcast PNGs of the same garden to LIGHT_DIR. Skipped without the env var.
    func testRenderLightingSheet() throws {
        guard let dir = ProcessInfo.processInfo.environment["LIGHT_DIR"] else { return }
        let sunrise = Date(timeIntervalSince1970: 1_700_000_000)
        let sunset = sunrise.addingTimeInterval(14 * 3600)
        let day = 293   // 20 October, Geelong
        let lat = -38.2167
        func sunAt(_ f: Double, cloud: Double = 0) -> SunLight {
            SunPosition.light(at: sunrise.addingTimeInterval(f * 14 * 3600), sunrise: sunrise, sunset: sunset,
                              latitude: lat, cloudCover: cloud, dayOfYear: day)
        }
        let shots: [(name: String, palette: ScenePalette)] = [
            ("morning", ScenePalette.resolve(season: .spring, phase: .day, condition: .clear, temperatureC: 12,
                                             cloudCover: 5, sun: sunAt(0.08))),
            ("noon", ScenePalette.resolve(season: .spring, phase: .day, condition: .clear, temperatureC: 22,
                                          cloudCover: 5, sun: sunAt(0.5))),
            ("dusk", ScenePalette.resolve(season: .spring, phase: .day, condition: .clear, temperatureC: 17,
                                          cloudCover: 5, sun: sunAt(0.93))),
            ("overcast", ScenePalette.resolve(season: .spring, phase: .day, condition: .overcast, temperatureC: 17,
                                              cloudCover: 100, sun: sunAt(0.5, cloud: 100))),
        ]
        let fm = FileManager.default
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for shot in shots {
            let scene = GardenSceneView(garden: SceneRenderTests.sampleGarden(), palette: shot.palette,
                                        camera: Camera())
                .frame(width: 960, height: 720)
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(shot.name).png")
            try pngData(scene).write(to: url)
        }
    }
}
