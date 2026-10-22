import XCTest
import SwiftUI
import DharmaGardenCore
@testable import DharmaGardenArt

/// Time-lapse sheet for the wave 5A plants, one row per plant: 10 progress columns (0...1), then droop 0.7,
/// fade 0.5 and a seed head. Written to PLANT_SHEET_PATH; the test does nothing when that variable is unset.
@MainActor
final class PlantSheetTests: XCTestCase {
    static let newPlants: [FlowerType] = [.chocolateLily, .commonEverlasting, .calendula, .cosmos, .basil, .zucchini, .lettuce]

    private func row(_ f: FlowerType) -> [FlowerArt] {
        var arts = (0..<10).map { FlowerArt(flower: f, progress: Double($0) / 9) }
        arts.append(FlowerArt(flower: f, progress: 1, droop: 0.7))
        arts.append(FlowerArt(flower: f, progress: 1, fade: 0.5))
        arts.append(FlowerArt(flower: f, progress: 1, isSeedHead: true))
        return arts
    }

    private func pngData<V: View>(_ view: V) throws -> Data {
        let r = ImageRenderer(content: view)
        r.scale = 1
        let img = try XCTUnwrap(r.nsImage)
        let tiff = try XCTUnwrap(img.tiffRepresentation)
        return try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }

    func testRenderPlantSheet() throws {
        guard let out = ProcessInfo.processInfo.environment["PLANT_SHEET_PATH"] else { return }
        let cell: CGFloat = 120
        let sky = LinearGradient(colors: [Color(hex: 0xBFE0EE), Color(hex: 0xF7EBC8), Color(hex: 0xA9C26A)],
                                 startPoint: .top, endPoint: .bottom)
        let rows = Self.newPlants.map { row($0) }
        let view = ZStack {
            sky
            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(rows[r].indices, id: \.self) { i in
                            rows[r][i].frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
        .frame(width: cell * 13, height: cell * CGFloat(Self.newPlants.count))
        let url = URL(fileURLWithPath: out)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try pngData(view).write(to: url)
    }
}
