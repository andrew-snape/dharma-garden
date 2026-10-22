// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WeedsCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WeedsCore", targets: ["WeedsCore"]),
        .library(name: "WeedsArt", targets: ["WeedsArt"]),
    ],
    targets: [
        .target(name: "WeedsCore"),
        .target(name: "WeedsArt", dependencies: ["WeedsCore"]),
        .testTarget(name: "WeedsCoreTests", dependencies: ["WeedsCore", "WeedsArt"]),
    ]
)
