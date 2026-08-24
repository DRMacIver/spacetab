// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SpaceTab",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "SpaceTabCore", path: "Sources/SpaceTabCore"),
        .executableTarget(
            name: "SpaceTab",
            dependencies: ["SpaceTabCore"],
            path: "Sources/SpaceTab"
        ),
        // Plain executable test runner: the installed toolchain (Command Line
        // Tools without Xcode) does not ship XCTest.
        .executableTarget(
            name: "ModelTests",
            dependencies: ["SpaceTabCore"],
            path: "Sources/ModelTests"
        ),
    ]
)
