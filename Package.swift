// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CAPlateWatch",
    platforms: [.macOS(.v13), .iOS("18.7")],
    products: [
        .library(name: "CAPlateWatchCore", targets: ["CAPlateWatchCore"]),
        .executable(name: "CAPlateWatch", targets: ["CAPlateWatch"])
    ],
    targets: [
        .target(name: "CAPlateWatchCore"),
        .executableTarget(name: "CAPlateWatch", dependencies: ["CAPlateWatchCore"]),
        .executableTarget(name: "CAPlateWatchCoreTests", dependencies: ["CAPlateWatchCore"], path: "Tests/CAPlateWatchCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
