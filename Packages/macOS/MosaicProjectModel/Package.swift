// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MosaicProjectModel",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicProjectModel",
            targets: ["MosaicProjectModel"]
        ),
        .executable(
            name: "mosaic-project-dump",
            targets: ["MosaicProjectDump"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/tuist/XcodeProj.git",
            from: "9.0.0"
        ),
    ],
    targets: [
        .target(
            name: "MosaicProjectModel",
            dependencies: [
                .product(name: "XcodeProj", package: "XcodeProj"),
            ]
        ),
        .executableTarget(
            name: "MosaicProjectDump",
            dependencies: ["MosaicProjectModel"]
        ),
        .testTarget(
            name: "MosaicProjectModelTests",
            dependencies: ["MosaicProjectModel"]
        ),
    ]
)
