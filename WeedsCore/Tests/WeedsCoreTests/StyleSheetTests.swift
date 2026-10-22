import XCTest
import SwiftUI
import WeedsCore
@testable import WeedsArt

/// One row of plants, each cell a square of `cell` points.
@MainActor
private func strip(_ arts: [FlowerArt], cell: CGFloat) -> some View {
    HStack(spacing: 0) {
        ForEach(arts.indices, id: \.self) { i in
            arts[i].frame(width: cell, height: cell)
        }
    }
}

@MainActor
private func timelapseRow(_ f: FlowerType) -> [FlowerArt] {
    var arts = (0..<10).map { FlowerArt(flower: f, progress: Double($0) / 9) }
    arts.append(FlowerArt(flower: f, progress: 1, droop: 0.7))
    arts.append(FlowerArt(flower: f, progress: 1, fade: 0.5))
    arts.append(FlowerArt(flower: f, progress: 1, isSeedHead: true))
    return arts
}

@MainActor
final class StyleSheetTests: XCTestCase {
    private let sky = LinearGradient(colors: [Color(hex: 0xBFE0EE), Color(hex: 0xF7EBC8), Color(hex: 0xA9C26A)],
                                     startPoint: .top, endPoint: .bottom)

    /// Renders a view at 1x scale and returns PNG bytes.
    private func pngData<V: View>(_ view: V) throws -> Data {
        let r = ImageRenderer(content: view)
        r.scale = 1
        let img = try XCTUnwrap(r.nsImage)
        let tiff = try XCTUnwrap(img.tiffRepresentation)
        return try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }

    private func writePNG(_ data: Data, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// Renders the 4 flowers x 4 progress steps (0, 0.3, 0.7, 1.0) to a PNG so the look can be judged by eye.
    func testRenderStyleSheet() throws {
        guard let out = ProcessInfo.processInfo.environment["STYLE_SHEET_PATH"] else { return }
        let progresses: [Double] = [0, 0.3, 0.7, 1.0]
        let view = ZStack {
            sky
            VStack(spacing: 0) {
                ForEach(FlowerType.allCases, id: \.self) { f in
                    strip(progresses.map { FlowerArt(flower: f, progress: $0) }, cell: 190)
                }
            }
        }
        .frame(width: 760, height: 760)
        try writePNG(try pngData(view), to: out)
    }

    /// One row per flower: 10 columns of progress 0...1, then droop 0.7, fade 0.5 and a seed head.
    func testRenderTimelapse() throws {
        guard let out = ProcessInfo.processInfo.environment["TIMELAPSE_PATH"] else { return }
        let cell: CGFloat = 120
        let rows = FlowerType.allCases.map { timelapseRow($0) }
        let view = ZStack {
            sky
            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { r in
                    strip(rows[r], cell: cell)
                }
            }
        }
        .frame(width: cell * 13, height: cell * CGFloat(FlowerType.allCases.count))
        try writePNG(try pngData(view), to: out)
    }

    /// The same inputs must always produce the same image bytes.
    func testSameInputsRenderIdentically() throws {
        func render() throws -> Data {
            try pngData(FlowerArt(flower: .daisy, progress: 0.8, droop: 0.3, fade: 0.2, openness: 0.9,
                                  variation: 42, sway: 0.4)
                .frame(width: 200, height: 200))
        }
        XCTAssertEqual(try render(), try render())
    }

    /// Different variation values give visibly different plants.
    func testDifferentVariationRendersDifferently() throws {
        func render(_ v: UInt64) throws -> Data {
            try pngData(FlowerArt(flower: .daisy, progress: 1, variation: v).frame(width: 200, height: 200))
        }
        XCTAssertNotEqual(try render(1), try render(2))
    }
}
