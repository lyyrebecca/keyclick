// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeyClick",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KeyClickCore", targets: ["KeyClickCore"]),
        .executable(name: "KeyClick", targets: ["KeyClick"]),
        .executable(name: "KeyClickChecks", targets: ["KeyClickChecks"])
    ],
    targets: [
        .target(name: "KeyClickCore"),
        .executableTarget(name: "KeyClick", dependencies: ["KeyClickCore"], path: "Sources/KeyClickApp"),
        .executableTarget(name: "KeyClickChecks", dependencies: ["KeyClickCore"], path: "Tests/KeyClickChecks"),
        .testTarget(
            name: "KeyClickCoreTests",
            dependencies: ["KeyClickCore"]
        )
    ]
)
