// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GooseIDE",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "GooseCore", targets: ["GooseCore"])
    ],
    targets: [
        .target(name: "GooseCore"),
        .testTarget(name: "GooseCoreTests", dependencies: ["GooseCore"])
    ]
)
