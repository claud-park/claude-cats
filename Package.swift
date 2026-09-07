// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeCats",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClaudeCatsCore"),
        .executableTarget(name: "ClaudeCats", dependencies: ["ClaudeCatsCore"]),
        .testTarget(name: "ClaudeCatsCoreTests", dependencies: ["ClaudeCatsCore"]),
    ]
)
