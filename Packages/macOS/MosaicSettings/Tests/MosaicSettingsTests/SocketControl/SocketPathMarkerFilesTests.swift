import Testing
@testable import MosaicSettings

@Test func markerFilesAreVariantAware() {
    #expect(SocketPathMarkerFiles.variant(
        bundleIdentifier: "mosaic.com.emergent.app",
        environment: [:]
    ) == .stable)
    #expect(SocketPathMarkerFiles.variant(
        bundleIdentifier: "mosaic.com.emergent.app.nightly",
        environment: [:]
    ) == .nightly(slug: nil))
    #expect(SocketPathMarkerFiles.variant(
        bundleIdentifier: "mosaic.com.emergent.app.debug.agent",
        environment: [:]
    ) == .dev(slug: "agent"))
    #expect(SocketPathMarkerFiles.variant(
        bundleIdentifier: "mosaic.com.emergent.app.debug",
        environment: ["MOSAIC_TAG": "Issue 3542"]
    ) == .dev(slug: "issue-3542"))
    #expect(SocketPathMarkerFiles.variant(
        bundleIdentifier: "mosaic.com.emergent.app.debug",
        environment: ["MOSAIC_TAG": "café"]
    ) == .dev(slug: "caf"))
}

@Test func defaultSocketPathsStayVariantScoped() {
    #expect(SocketPathMarkerFiles.defaultSocketPath(
        bundleIdentifier: "mosaic.com.emergent.app",
        environment: [:],
        isDebugBuild: false,
        stableSocketPath: "/stable/mosaic.sock"
    ) == "/stable/mosaic.sock")
    #expect(SocketPathMarkerFiles.defaultSocketPath(
        bundleIdentifier: "mosaic.com.emergent.app.nightly",
        environment: [:],
        isDebugBuild: false,
        stableSocketPath: "/stable/mosaic.sock"
    ) == "/tmp/mosaic-nightly.sock")
    #expect(SocketPathMarkerFiles.defaultSocketPath(
        bundleIdentifier: "mosaic.com.emergent.app.staging.my-feature",
        environment: [:],
        isDebugBuild: false,
        stableSocketPath: "/stable/mosaic.sock"
    ) == "/tmp/mosaic-staging-my-feature.sock")
    #expect(SocketPathMarkerFiles.defaultSocketPath(
        bundleIdentifier: "mosaic.com.emergent.app.debug",
        environment: ["MOSAIC_TAG": "Issue 3542"],
        isDebugBuild: false,
        stableSocketPath: "/stable/mosaic.sock"
    ) == "/tmp/mosaic-debug-issue-3542.sock")
}
