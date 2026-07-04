// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StubAgentSidebarExtension",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "StubAgentSidebarExtension",
            targets: ["StubAgentSidebarExtension"]
        ),
    ],
    dependencies: [
        .package(path: "../../Packages/macOS/MosaicExtensionKit"),
    ],
    targets: [
        .target(
            name: "StubAgentSidebarExtension",
            dependencies: [
                .product(name: "MosaicExtensionKit", package: "MosaicExtensionKit"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
