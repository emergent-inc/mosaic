// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicCollaboration",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicCollaboration",
            targets: ["MosaicCollaboration"]
        ),
    ],
    targets: [
        .target(
            name: "MosaicCollaboration",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicCollaborationTests",
            dependencies: ["MosaicCollaboration"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
