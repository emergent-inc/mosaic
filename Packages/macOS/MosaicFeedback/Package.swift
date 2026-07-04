// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicFeedback",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicFeedback",
            targets: ["MosaicFeedback"]
        ),
    ],
    dependencies: [
        .package(path: "../MosaicFoundation"),
    ],
    targets: [
        .target(
            name: "MosaicFeedback",
            dependencies: [
                "MosaicFoundation",
            ],
            resources: [
                // Folded from MosaicFeedbackUI: the composer's localized strings.
                .process("ComposerUI/Resources"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicFeedbackTests",
            dependencies: ["MosaicFeedback"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
