import Testing

import MosaicSettings

@Suite struct SocketControlSettingsTests {
    @Test func migrateModeMapsLegacyAndUnknownValues() {
        #expect(SocketControlSettings.migrateMode("off") == .off)
        #expect(SocketControlSettings.migrateMode("mosaic_only") == .mosaicOnly)
        #expect(SocketControlSettings.migrateMode("ALLOW-ALL") == .allowAll)
        // Legacy aliases.
        #expect(SocketControlSettings.migrateMode("notifications") == .automation)
        #expect(SocketControlSettings.migrateMode("full") == .allowAll)
        // Unknown falls back to the default.
        #expect(SocketControlSettings.migrateMode("bogus") == .mosaicOnly)
    }

    @Test func effectiveModeHonorsEnableOverride() {
        #expect(
            SocketControlSettings.effectiveMode(
                userMode: .password,
                environment: ["MOSAIC_SOCKET_ENABLE": "0"]
            ) == .off
        )
        #expect(
            SocketControlSettings.effectiveMode(
                userMode: .off,
                environment: ["MOSAIC_SOCKET_ENABLE": "1"]
            ) == .mosaicOnly
        )
    }

    @Test func effectiveModeHonorsModeOverride() {
        #expect(
            SocketControlSettings.effectiveMode(
                userMode: .mosaicOnly,
                environment: ["MOSAIC_SOCKET_MODE": "allowall"]
            ) == .allowAll
        )
    }

    @Test func effectiveModeFallsBackToUserMode() {
        #expect(
            SocketControlSettings.effectiveMode(userMode: .automation, environment: [:]) == .automation
        )
    }

    @Test func truthyParsing() {
        for value in ["1", "true", "YES", "on"] {
            #expect(SocketControlSettings.isTruthy(value))
        }
        for value in ["0", "false", "", "nope"] {
            #expect(!SocketControlSettings.isTruthy(value))
        }
    }

    @Test func taggedDevBuildDetection() {
        #expect(SocketControlSettings.isTaggedDevBuild(bundleIdentifier: "mosaic.com.emergent.app.debug.my-tag"))
        #expect(!SocketControlSettings.isTaggedDevBuild(bundleIdentifier: "mosaic.com.emergent.app.debug"))
        #expect(!SocketControlSettings.isTaggedDevBuild(bundleIdentifier: "mosaic.com.emergent.app"))
    }

    @Test func untaggedDebugLaunchIsBlockedOnlyForBareDebugBundle() {
        // Bare debug bundle, no tag, not under test => blocked.
        #expect(
            SocketControlSettings.shouldBlockUntaggedDebugLaunch(
                environment: [:],
                bundleIdentifier: "mosaic.com.emergent.app.debug",
                isDebugBuild: true
            )
        )
        // XCUITest launches the app as a separate process without XCTest env vars,
        // so any MOSAIC_UI_TEST_ marker must bypass blocking for a bare debug bundle.
        #expect(
            !SocketControlSettings.shouldBlockUntaggedDebugLaunch(
                environment: ["MOSAIC_UI_TEST_RUN": "1"],
                bundleIdentifier: "mosaic.com.emergent.app.debug",
                isDebugBuild: true
            )
        )
        // Tagged debug bundle => allowed.
        #expect(
            !SocketControlSettings.shouldBlockUntaggedDebugLaunch(
                environment: [:],
                bundleIdentifier: "mosaic.com.emergent.app.debug.tag",
                isDebugBuild: true
            )
        )
        // Release build => never blocked.
        #expect(
            !SocketControlSettings.shouldBlockUntaggedDebugLaunch(
                environment: [:],
                bundleIdentifier: "mosaic.com.emergent.app",
                isDebugBuild: false
            )
        )
    }

    @Test func socketPathHonorsOverrideForTaggedDevWhenAllowed() {
        let path = SocketControlSettings.socketPath(
            environment: [
                "MOSAIC_SOCKET_PATH": "/tmp/mosaic-custom.sock",
                "MOSAIC_ALLOW_SOCKET_OVERRIDE": "1",
            ],
            bundleIdentifier: "mosaic.com.emergent.app.debug.tag",
            isDebugBuild: true,
            currentUserID: 501,
            probeStableDefaultPathEntry: { _ in .missing }
        )
        #expect(path == "/tmp/mosaic-custom.sock")
    }

    @Test func bareDebugXCTestLaunchUsesScopedSocketFallback() {
        let environment = [
            "XCTestConfigurationFilePath": "/tmp/Test-mosaic-unit-2026.06.17.xctestconfiguration",
        ]
        let path = SocketControlSettings.socketPath(
            environment: environment,
            bundleIdentifier: "mosaic.com.emergent.app.debug",
            isDebugBuild: true,
            currentUserID: 501,
            probeStableDefaultPathEntry: { _ in .missing }
        )
        let defaultPath = SocketControlSettings.defaultSocketPath(
            bundleIdentifier: "mosaic.com.emergent.app.debug",
            environment: environment,
            isDebugBuild: true,
            currentUserID: 501,
            probeStableDefaultPathEntry: { _ in .missing }
        )
        #expect(path.hasPrefix("/tmp/mosaic-xctest-"))
        #expect(path.hasSuffix(".sock"))
        #expect(path != "/tmp/mosaic-debug.sock")
        #expect(path == defaultPath)
    }

    @Test func explicitSocketOverrideStillWinsUnderXCTest() {
        let path = SocketControlSettings.socketPath(
            environment: [
                "MOSAIC_SOCKET_PATH": "/tmp/mosaic-forced.sock",
                "XCTestConfigurationFilePath": "/tmp/Test-mosaic-unit-2026.06.17.xctestconfiguration",
            ],
            bundleIdentifier: "mosaic.com.emergent.app.debug",
            isDebugBuild: true,
            currentUserID: 501,
            probeStableDefaultPathEntry: { _ in .missing }
        )
        #expect(path == "/tmp/mosaic-forced.sock")
    }

    @Test func dyldOnlyXCTestLaunchUsesScopedSocketFallback() {
        let path = SocketControlSettings.socketPath(
            environment: [
                "DYLD_INSERT_LIBRARIES": "/Applications/Xcode.app/Contents/Developer/usr/lib/libXCTestSwiftSupport.dylib",
            ],
            bundleIdentifier: "mosaic.com.emergent.app.debug",
            isDebugBuild: true,
            currentUserID: 501,
            probeStableDefaultPathEntry: { _ in .missing }
        )
        #expect(path.hasPrefix("/tmp/mosaic-xctest-"))
        #expect(path.hasSuffix(".sock"))
        #expect(path != "/tmp/mosaic-debug.sock")
    }

    @Test func xctestSocketFallbackHashesFullPath() {
        let first = SocketControlSettings.socketPath(
            environment: [
                "XCTestConfigurationFilePath": "/tmp/first/Test-mosaic-unit.xctestconfiguration",
            ],
            bundleIdentifier: "mosaic.com.emergent.app.debug",
            isDebugBuild: true,
            currentUserID: 501,
            probeStableDefaultPathEntry: { _ in .missing }
        )
        let second = SocketControlSettings.socketPath(
            environment: [
                "XCTestConfigurationFilePath": "/tmp/second/Test-mosaic-unit.xctestconfiguration",
            ],
            bundleIdentifier: "mosaic.com.emergent.app.debug",
            isDebugBuild: true,
            currentUserID: 501,
            probeStableDefaultPathEntry: { _ in .missing }
        )
        #expect(first.hasPrefix("/tmp/mosaic-xctest-"))
        #expect(second.hasPrefix("/tmp/mosaic-xctest-"))
        #expect(first != second)
    }

    @Test func taggedDebugXCTestLaunchStillUsesTaggedSocket() {
        let path = SocketControlSettings.socketPath(
            environment: [
                "MOSAIC_TAG": "ci-split-theme",
                "XCTestConfigurationFilePath": "/tmp/Test-mosaic-unit-2026.06.17.xctestconfiguration",
            ],
            bundleIdentifier: "mosaic.com.emergent.app.debug",
            isDebugBuild: true,
            currentUserID: 501,
            probeStableDefaultPathEntry: { _ in .missing }
        )
        #expect(path == "/tmp/mosaic-debug-ci-split-theme.sock")
    }
}
