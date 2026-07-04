// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MosaicSidebarProviderKit",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicSidebarProviderKit",
            targets: ["MosaicSidebarProviderKit"]
        ),
    ],
    dependencies: [
        .package(path: "../MosaicFoundation"),
    ],
    targets: [
        .target(
            name: "MosaicSidebarProviderKit",
            dependencies: ["MosaicFoundation"]
        ),
    ]
)
