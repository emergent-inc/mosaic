// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MosaicAgentLaunch",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicAgentLaunch",
            targets: ["MosaicAgentLaunch"]
        ),
    ],
    targets: [
        .target(
            name: "MosaicAgentLaunch"
        ),
        .testTarget(
            name: "MosaicAgentLaunchTests",
            dependencies: ["MosaicAgentLaunch"]
        ),
    ]
)
