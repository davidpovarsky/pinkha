// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PinkhaTorah",
    defaultLocalization: "en",
    platforms: [.iOS("26.0"), .macOS("14.0")],
    products: [
        .library(name: "PinkhaTorahCore", targets: ["PinkhaTorahCore"]),
        .library(name: "PinkhaTorahUI", targets: ["PinkhaTorahUI"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
        .target(
            name: "PinkhaTorahCore",
            dependencies: ["CSQLite"],
            path: "Sources/PinkhaTorahCore"
        ),
        .target(
            name: "PinkhaTorahUI",
            dependencies: ["PinkhaTorahCore"],
            path: "Sources/PinkhaTorahUI",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "PinkhaTorahCoreTests",
            dependencies: ["PinkhaTorahCore", "CSQLite"],
            path: "Tests/PinkhaTorahCoreTests"
        )
    ]
)
