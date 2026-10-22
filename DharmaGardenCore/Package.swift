// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DharmaGardenCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DharmaGardenCore", targets: ["DharmaGardenCore"]),
        .library(name: "DharmaGardenArt", targets: ["DharmaGardenArt"]),
    ],
    targets: [
        .target(name: "DharmaGardenCore"),
        .target(name: "DharmaGardenArt", dependencies: ["DharmaGardenCore"]),
        .testTarget(name: "DharmaGardenCoreTests", dependencies: ["DharmaGardenCore", "DharmaGardenArt"]),
    ]
)
