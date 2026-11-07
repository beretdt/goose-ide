// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GooseIDE",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "GooseCore", targets: ["GooseCore"]),
        .library(name: "GooseGitHub", targets: ["GooseGitHub"]),
        .executable(name: "goosectl", targets: ["goosectl"]),
    ],
    targets: [
        .target(name: "GooseCore"),
        .target(name: "GooseGitHub"),
        .executableTarget(name: "goosectl", dependencies: ["GooseCore"]),
        .testTarget(name: "GooseCoreTests", dependencies: ["GooseCore"]),
        .testTarget(name: "GooseGitHubTests", dependencies: ["GooseGitHub"]),
    ]
)
