// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenSense",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ScreenSense", targets: ["ScreenSenseApp"]),
        .library(name: "ScreenSenseCore", targets: ["ScreenSenseCore"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ScreenSenseCore",
            dependencies: [],
            path: "Sources/ScreenSenseCore"
        ),
        .executableTarget(
            name: "ScreenSenseApp",
            dependencies: ["ScreenSenseCore"],
            path: "Sources/ScreenSenseApp"
        ),
        .testTarget(
            name: "ScreenSenseTests",
            dependencies: ["ScreenSenseCore"],
            path: "Tests/ScreenSenseTests"
        )
    ]
)
