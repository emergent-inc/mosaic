import Foundation
import Testing
@_spi(MosaicHostTransport) @testable import MosaicExtensionKit

@Suite
struct MosaicExtensionKitTests {
    @Test
    func testSidebarSnapshotRoundTripsStableContract() throws {
        let workspaceID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let snapshot = MosaicSidebarSnapshot(
            sequence: 42,
            windowID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            selectedWorkspaceID: workspaceID,
            grantedReadScopes: [.workspaceMetadata, .workspacePaths, .notifications, .networkPorts, .pullRequests],
            grantedActionScopes: [.selectWorkspace],
            workspaces: [
                MosaicSidebarWorkspace(
                    id: workspaceID,
                    title: "Build",
                    detail: "main",
                    isPinned: true,
                    rootPath: "/repo",
                    projectRootPath: "/repo",
                    gitBranch: "main",
                    unreadCount: 2,
                    latestNotification: "Tests passed",
                    listeningPorts: [3000],
                    pullRequestURLs: ["https://github.com/emergent-inc/mosaic/pull/1"]
                ),
            ]
        )

        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(MosaicSidebarSnapshot.self, from: encoded)

        #expect(decoded == snapshot)
        #expect(decoded.apiVersion == MosaicExtensionAPIVersion.sidebarV2)
        #expect(decoded.grantedReadScopes.contains(.workspaceMetadata))
        #expect(decoded.grantedActionScopes == [.selectWorkspace])
    }

    @Test
    func testManifestValidationAcceptsSidebarV2() throws {
        let manifest = MosaicExtensionManifest(
            id: "dev.example.sidebar",
            displayName: "Example Sidebar",
            readScopes: [.workspaceMetadata, .workspacePaths],
            actionScopes: [.selectWorkspace, .openURL]
        )

        try validateSidebarManifest(manifest)
    }

    @Test
    func testManifestDecodingDefaultsMissingActionScopesToNone() throws {
        let payload = Data("""
        {
          "id": "dev.example.sidebar",
          "displayName": "Example Sidebar",
          "minimumAPIVersion": { "major": 2, "minor": 0 },
          "readScopes": ["workspaceMetadata"]
        }
        """.utf8)

        let manifest = try JSONDecoder().decode(MosaicExtensionManifest.self, from: payload)

        #expect(manifest.readScopes == [.workspaceMetadata])
        #expect(manifest.actionScopes.isEmpty)
        try validateSidebarManifest(manifest)
    }

    @Test
    func testManifestInitializerDefaultsActionScopesToNone() throws {
        let manifest = MosaicExtensionManifest(
            id: "dev.example.sidebar",
            displayName: "Example Sidebar"
        )

        #expect(manifest.readScopes.isEmpty)
        #expect(manifest.actionScopes.isEmpty)
        try validateSidebarManifest(manifest)
    }

    @Test
    func testSidebarSnapshotFilteringRemovesUngrantedScopeData() throws {
        let workspaceID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let snapshot = MosaicSidebarSnapshot(
            sequence: 44,
            selectedWorkspaceID: workspaceID,
            workspaces: [
                MosaicSidebarWorkspace(
                    id: workspaceID,
                    title: "Build",
                    detail: "Running tests",
                    isPinned: true,
                    rootPath: "/Users/example/secret",
                    projectRootPath: "/Users/example/secret",
                    gitBranch: "feature/sidebar",
                    unreadCount: 2,
                    latestNotification: "Private notification",
                    listeningPorts: [3000, 5173],
                    pullRequestURLs: ["https://github.com/emergent-inc/mosaic/pull/4994"]
                ),
            ]
        )

        let filtered = snapshot.filtered(for: [MosaicExtensionScope.workspaceMetadata])
        let workspace = try #require(filtered.workspaces.first)

        #expect(filtered.grantedReadScopes == [.workspaceMetadata])
        #expect(filtered.grantedActionScopes.isEmpty)
        #expect(workspace.id == workspaceID)
        #expect(workspace.title == "Build")
        #expect(workspace.detail == "Running tests")
        #expect(workspace.gitBranch == "feature/sidebar")
        #expect(workspace.unreadCount == 2)
        #expect(workspace.rootPath == nil)
        #expect(workspace.projectRootPath == nil)
        #expect(workspace.latestNotification == nil)
        #expect(workspace.listeningPorts.isEmpty)
        #expect(workspace.pullRequestURLs.isEmpty)
    }

    @Test
    func testSidebarSnapshotFilteringWithNoScopesRemovesWorkspaceMetadata() {
        let workspaceID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let windowID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let snapshot = MosaicSidebarSnapshot(
            sequence: 45,
            windowID: windowID,
            selectedWorkspaceID: workspaceID,
            workspaces: [
                MosaicSidebarWorkspace(
                    id: workspaceID,
                    title: "Private Workspace",
                    detail: "Sensitive detail",
                    isPinned: true,
                    rootPath: "/Users/example/private",
                    projectRootPath: "/Users/example/private",
                    gitBranch: "secret",
                    unreadCount: 9,
                    latestNotification: "Sensitive notification",
                    listeningPorts: [8080],
                    pullRequestURLs: ["https://github.com/emergent-inc/mosaic/pull/4994"]
                ),
            ]
        )

        let filtered = snapshot.filtered(for: [MosaicExtensionScope]())

        #expect(filtered.apiVersion == .sidebarV2)
        #expect(filtered.sequence == 45)
        #expect(filtered.windowID == nil)
        #expect(filtered.selectedWorkspaceID == nil)
        #expect(filtered.grantedReadScopes.isEmpty)
        #expect(filtered.grantedActionScopes.isEmpty)
        #expect(filtered.workspaces.isEmpty)
    }

    @Test
    func testSidebarSnapshotDecodingDefaultsMissingGrantedScopes() throws {
        let payload = Data("""
        {
          "apiVersion": { "major": 2, "minor": 0 },
          "sequence": 50,
          "selectedWorkspaceID": null,
          "workspaces": []
        }
        """.utf8)

        let snapshot = try JSONDecoder().decode(MosaicSidebarSnapshot.self, from: payload)

        #expect(snapshot.sequence == 50)
        #expect(snapshot.grantedReadScopes.isEmpty)
        #expect(snapshot.grantedActionScopes.isEmpty)
    }

    @Test
    func testSidebarXPCCodecRoundTripsSnapshotActionAndResult() throws {
        let workspaceID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let snapshot = MosaicSidebarSnapshot(
            sequence: 43,
            selectedWorkspaceID: workspaceID,
            workspaces: [
                MosaicSidebarWorkspace(
                    id: workspaceID,
                    title: "Build",
                    detail: "Running tests",
                    isPinned: true,
                    rootPath: "/tmp/mosaic",
                    projectRootPath: "/tmp/mosaic",
                    gitBranch: "feature/sidebar",
                    unreadCount: 2,
                    latestNotification: "Tests failed",
                    listeningPorts: [3000],
                    pullRequestURLs: ["https://github.com/emergent-inc/mosaic/pull/4994"]
                ),
            ]
        )
        let decodedSnapshot = try MosaicSidebarXPCCodec.decodeSnapshot(
            try MosaicSidebarXPCCodec.encodeSnapshot(snapshot)
        )
        #expect(decodedSnapshot == snapshot)

        let actionScopedSnapshot = snapshot.filtered(
            for: [MosaicExtensionScope.workspaceMetadata],
            actionScopes: [MosaicExtensionActionScope.selectWorkspace]
        )
        #expect(actionScopedSnapshot.grantedActionScopes == [.selectWorkspace])

        let manifest = MosaicExtensionManifest(
            id: "dev.example.sidebar",
            displayName: "Example Sidebar",
            readScopes: [.workspaceMetadata, .networkPorts],
            actionScopes: [.selectWorkspace, .closeWorkspace]
        )
        let decodedManifest = try MosaicSidebarXPCCodec.decodeManifest(
            try MosaicSidebarXPCCodec.encodeManifest(manifest)
        )
        #expect(decodedManifest == manifest)

        let action = MosaicSidebarAction.selectWorkspace(workspaceID)
        #expect(action.requiredScopes == [.selectWorkspace])
        let decodedAction = try MosaicSidebarXPCCodec.decodeAction(
            try MosaicSidebarXPCCodec.encodeAction(action)
        )
        #expect(decodedAction == action)

        let result = MosaicSidebarActionResult.rejected("Not found")
        let decodedResult = try MosaicSidebarXPCCodec.decodeActionResult(
            try MosaicSidebarXPCCodec.encodeActionResult(result)
        )
        #expect(decodedResult == result)

        let cancelledResult = MosaicSidebarActionResult.cancelled
        let decodedCancelledResult = try MosaicSidebarXPCCodec.decodeActionResult(
            try MosaicSidebarXPCCodec.encodeActionResult(cancelledResult)
        )
        #expect(decodedCancelledResult.rejectionReason == .cancelled)
    }

    @Test
    @MainActor
    func testSidebarHostTypedHelpersSendExpectedActions() async throws {
        var actions = [MosaicSidebarAction]()
        var refreshCount = 0
        let workspaceID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let url = URL(string: "https://example.com/pr/1")!
        let host = MosaicSidebarHost(
            performAction: { action, reply in
                actions.append(action)
                reply(MosaicSidebarActionResult(accepted: true))
            },
            refreshSnapshot: {
                refreshCount += 1
            }
        )

        host.refresh()
        try await host.selectWorkspace(workspaceID)
        try await host.closeWorkspace(workspaceID)
        try await host.createWorkspace(title: "Scratch", select: false)
        try await host.createWorkspace(title: "Path Scratch", at: "/tmp/scratch", select: false)
        try await host.selectNextWorkspace()
        try await host.selectPreviousWorkspace()
        try await host.createTerminalSurface(in: workspaceID)
        try await host.createBrowserSurface(in: workspaceID, url: url)
        try await host.openURL(url)

        #expect(refreshCount == 1)
        #expect(actions == [
            .selectWorkspace(workspaceID),
            .closeWorkspace(workspaceID),
            .createWorkspace(title: "Scratch", workingDirectory: nil, select: false),
            .createWorkspace(title: "Path Scratch", workingDirectory: "/tmp/scratch", select: false),
            .selectNextWorkspace,
            .selectPreviousWorkspace,
            .createTerminalSurface(workspaceID: workspaceID),
            .createBrowserSurface(workspaceID: workspaceID, url: "https://example.com/pr/1"),
            .openURL("https://example.com/pr/1"),
        ])
    }

    @Test
    func testWorkspaceListScopeDoesNotExposeMetadata() throws {
        let workspaceID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let snapshot = MosaicSidebarSnapshot(
            sequence: 47,
            selectedWorkspaceID: workspaceID,
            workspaces: [
                MosaicSidebarWorkspace(
                    id: workspaceID,
                    title: "Private Workspace",
                    detail: "Sensitive detail",
                    isPinned: true,
                    rootPath: "/Users/example/private",
                    projectRootPath: "/Users/example/private",
                    gitBranch: "secret",
                    unreadCount: 9,
                    latestNotification: "Sensitive notification",
                    listeningPorts: [8080],
                    pullRequestURLs: ["https://github.com/emergent-inc/mosaic/pull/4994"],
                    surfaces: [
                        MosaicSidebarSurface(id: UUID(), title: "Private Surface", kind: .terminal),
                    ]
                ),
            ]
        )

        let filtered = snapshot.filtered(for: [MosaicExtensionScope.workspaceList])
        let workspace = try #require(filtered.workspaces.first)

        #expect(filtered.grantedReadScopes == [.workspaceList])
        #expect(filtered.windowID == nil)
        #expect(filtered.selectedWorkspaceID == nil)
        #expect(workspace.id == workspaceID)
        #expect(workspace.title.isEmpty)
        #expect(workspace.detail == nil)
        #expect(!workspace.isPinned)
        #expect(workspace.rootPath == nil)
        #expect(workspace.projectRootPath == nil)
        #expect(workspace.gitBranch == nil)
        #expect(workspace.unreadCount == 0)
        #expect(workspace.latestNotification == nil)
        #expect(workspace.listeningPorts.isEmpty)
        #expect(workspace.pullRequestURLs.isEmpty)
        #expect(workspace.surfaces.isEmpty)
    }

    @Test
    func testURLBearingBrowserActionsRequireOpenURLScope() {
        let workspaceID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let surfaceID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!

        #expect(MosaicSidebarAction.createBrowserSurface(workspaceID: workspaceID, url: nil).requiredScopes == [.createSurface])
        #expect(MosaicSidebarAction.createBrowserSurface(workspaceID: workspaceID, url: "https://example.com").requiredScopes == [.createSurface, .openURL])
        #expect(MosaicSidebarAction.splitBrowser(workspaceID: workspaceID, surfaceID: surfaceID, direction: .right, url: nil).requiredScopes == [.splitSurface])
        #expect(MosaicSidebarAction.splitBrowser(workspaceID: workspaceID, surfaceID: surfaceID, direction: .right, url: "https://example.com").requiredScopes == [.splitSurface, .openURL])
    }

    @Test
    func testWorkspaceCreationWithPathRequiresWorkspacePathScope() {
        #expect(MosaicSidebarAction.createWorkspace(title: nil, workingDirectory: nil, select: true).requiredScopes == [.createWorkspace])
        #expect(MosaicSidebarAction.createWorkspace(title: nil, workingDirectory: "/tmp/project", select: true).requiredScopes == [.createWorkspace, .createWorkspaceWithPath])
    }

    @Test
    @MainActor
    func testSidebarHostCancelsPendingAsyncAction() async {
        let cancellationBox = CancellationBox()
        let startBox = ActionStartBox()
        let workspaceID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        let host = MosaicSidebarHost(
            performCancellableAction: { _, _ in
                startBox.markStarted()
                return MosaicSidebarActionCancellation {
                    cancellationBox.cancel()
                }
            }
        )

        let task = Task { @MainActor in
            try await host.selectWorkspace(workspaceID)
        }
        await startBox.waitUntilStarted()
        task.cancel()
        do {
            try await task.value
            Issue.record("Expected cancellation to throw")
        } catch {
            #expect(error as? MosaicSidebarActionError == .cancelled)
        }
        #expect(cancellationBox.didCancel)
    }

    @Test
    func testSidebarXPCCodecRejectsOversizedManifestPayload() {
        let payload = Data(repeating: 0x20, count: MosaicSidebarXPCCodec.maximumManifestPayloadBytes + 1) as NSData

        do {
            _ = try MosaicSidebarXPCCodec.decodeManifest(payload)
            Issue.record("Expected oversized manifest payload to be rejected")
        } catch {
            #expect(
                error as? MosaicExtensionValidationError == .payloadTooLarge(
                    kind: "manifest",
                    actualBytes: payload.length,
                    maximumBytes: MosaicSidebarXPCCodec.maximumManifestPayloadBytes
                )
            )
        }
    }

    @Test
    func testSidebarXPCCodecRejectsOversizedActionPayload() {
        let payload = Data(repeating: 0x20, count: MosaicSidebarXPCCodec.maximumActionPayloadBytes + 1) as NSData

        do {
            _ = try MosaicSidebarXPCCodec.decodeAction(payload)
            Issue.record("Expected oversized action payload to be rejected")
        } catch {
            #expect(
                error as? MosaicExtensionValidationError == .payloadTooLarge(
                    kind: "action",
                    actualBytes: payload.length,
                    maximumBytes: MosaicSidebarXPCCodec.maximumActionPayloadBytes
                )
            )
        }
    }

    @Test
    func testSidebarXPCCodecRejectsOversizedSnapshotOnEncodeAndDecode() {
        let oversizedTitle = String(repeating: "x", count: MosaicSidebarXPCCodec.maximumSnapshotPayloadBytes)
        let snapshot = MosaicSidebarSnapshot(
            sequence: 46,
            selectedWorkspaceID: nil,
            workspaces: [
                MosaicSidebarWorkspace(id: UUID(), title: oversizedTitle),
            ]
        )

        do {
            _ = try MosaicSidebarXPCCodec.encodeSnapshot(snapshot)
            Issue.record("Expected oversized snapshot payload to be rejected on encode")
        } catch {
            if case let MosaicExtensionValidationError.payloadTooLarge(kind, actualBytes, maximumBytes) = error {
                #expect(kind == "snapshot")
                #expect(actualBytes > maximumBytes)
                #expect(maximumBytes == MosaicSidebarXPCCodec.maximumSnapshotPayloadBytes)
            } else {
                Issue.record("Unexpected error: \(error)")
            }
        }

        let payload = Data(repeating: 0x20, count: MosaicSidebarXPCCodec.maximumSnapshotPayloadBytes + 1) as NSData
        do {
            _ = try MosaicSidebarXPCCodec.decodeSnapshot(payload)
            Issue.record("Expected oversized snapshot payload to be rejected on decode")
        } catch {
            #expect(
                error as? MosaicExtensionValidationError == .payloadTooLarge(
                    kind: "snapshot",
                    actualBytes: payload.length,
                    maximumBytes: MosaicSidebarXPCCodec.maximumSnapshotPayloadBytes
                )
            )
        }
    }

    @Test
    func testSidebarXPCCodecRejectsOversizedActionResultOnEncodeAndDecode() {
        let result = MosaicSidebarActionResult(
            accepted: false,
            message: String(repeating: "x", count: MosaicSidebarXPCCodec.maximumActionResultPayloadBytes)
        )

        do {
            _ = try MosaicSidebarXPCCodec.encodeActionResult(result)
            Issue.record("Expected oversized action result payload to be rejected on encode")
        } catch {
            if case let MosaicExtensionValidationError.payloadTooLarge(kind, actualBytes, maximumBytes) = error {
                #expect(kind == "actionResult")
                #expect(actualBytes > maximumBytes)
                #expect(maximumBytes == MosaicSidebarXPCCodec.maximumActionResultPayloadBytes)
            } else {
                Issue.record("Unexpected error: \(error)")
            }
        }

        let payload = Data(repeating: 0x20, count: MosaicSidebarXPCCodec.maximumActionResultPayloadBytes + 1) as NSData
        do {
            _ = try MosaicSidebarXPCCodec.decodeActionResult(payload)
            Issue.record("Expected oversized action result payload to be rejected on decode")
        } catch {
            #expect(
                error as? MosaicExtensionValidationError == .payloadTooLarge(
                    kind: "actionResult",
                    actualBytes: payload.length,
                    maximumBytes: MosaicSidebarXPCCodec.maximumActionResultPayloadBytes
                )
            )
        }
    }

    @Test
    func testManifestValidationRejectsUnsupportedAPIVersion() throws {
        let payload = Data("""
        {
          "id": "dev.example.sidebar",
          "displayName": "Example Sidebar",
          "minimumAPIVersion": { "major": 2, "minor": 1 },
          "readScopes": []
        }
        """.utf8)
        let manifest = try JSONDecoder().decode(MosaicExtensionManifest.self, from: payload)

        do {
            try validateSidebarManifest(manifest)
            Issue.record("Expected unsupported API version error")
        } catch {
            #expect(
                error as? MosaicExtensionValidationError == .unsupportedAPIVersion(
                    requested: MosaicExtensionAPIVersion(major: 2, minor: 1),
                    supported: .sidebarV2
                )
            )
        }
    }

    @Test
    func testManifestValidationRejectsOldMajorVersion() throws {
        let payload = Data("""
        {
          "id": "dev.example.sidebar",
          "displayName": "Example Sidebar",
          "minimumAPIVersion": { "major": 1, "minor": 0 },
          "readScopes": []
        }
        """.utf8)
        let manifest = try JSONDecoder().decode(MosaicExtensionManifest.self, from: payload)

        do {
            try validateSidebarManifest(manifest)
            Issue.record("Expected unsupported API version error")
        } catch {
            #expect(
                error as? MosaicExtensionValidationError == .unsupportedAPIVersion(
                    requested: MosaicExtensionAPIVersion(major: 1, minor: 0),
                    supported: .sidebarV2
                )
            )
        }
    }
}

private final class CancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    var didCancel: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func cancel() {
        lock.lock()
        storage = true
        lock.unlock()
    }
}

private final class ActionStartBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var started = false

    func waitUntilStarted() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if started {
                lock.unlock()
                continuation.resume()
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }

    func markStarted() {
        lock.lock()
        started = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
    }
}
