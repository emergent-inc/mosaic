// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MosaicWorkspaces",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MosaicWorkspaces",
            targets: ["MosaicWorkspaces"]
        ),
    ],
    dependencies: [
        // WorkspaceGroupNewPlacement (the typed setting value for new
        // in-group workspace placement) is owned by MosaicSettings.
        .package(path: "../MosaicSettings"),
        // Bonsplit drives the Window/ tmux pane-overlay geometry.
        .package(path: "../../../vendor/bonsplit"),
        // MosaicDebugLog backs the Session/ snapshot-restore logging.
        .package(path: "../MosaicDebugLog"),
        // MosaicTestSupport backs FileOpen/ PreferredEditorService UI-test capture.
        .package(path: "../MosaicTestSupport"),
    ],
    targets: [
        .target(
            name: "MosaicWorkspaces",
            dependencies: [
                .product(name: "MosaicSettings", package: "MosaicSettings"),
                .product(name: "Bonsplit", package: "bonsplit"),
                .product(name: "MosaicDebugLog", package: "MosaicDebugLog"),
                .product(name: "MosaicTestSupport", package: "MosaicTestSupport"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "MosaicWorkspacesTests",
            dependencies: [
                "MosaicWorkspaces",
                .product(name: "Bonsplit", package: "bonsplit"),
                .product(name: "MosaicTestSupport", package: "MosaicTestSupport"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
