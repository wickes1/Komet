// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Komet",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Komet", path: "Sources"),
        .testTarget(name: "KometTests", dependencies: ["Komet"], path: "Tests"),
    ]
)
