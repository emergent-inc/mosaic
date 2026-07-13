import Combine
import Foundation
import Observation
import Testing

import MosaicSidebar

#if canImport(Mosaic_DEV)
@testable import Mosaic_DEV
#elseif canImport(Mosaic)
@testable import Mosaic
#endif

@MainActor
struct WorkspaceSidebarObservationTests {
    @Test func sidebarObservationPublisherEmitsForLateStatusSubscriber() {
        let workspace = Workspace()
        workspace.statusEntries["test_probe"] = SidebarStatusEntry(
            key: "test_probe",
            value: "VISIBLE?",
            icon: "star.fill",
            color: "#FF0000",
            priority: 200
        )

        var publishCount = 0
        let cancellable = workspace.sidebarObservationPublisher.sink {
            publishCount += 1
        }
        defer { cancellable.cancel() }

        #expect(
            publishCount > 0,
            "A sidebar row that subscribes after status metadata already exists must still refresh from the current workspace state."
        )
    }

    @Test func agentRuntimeObservationChangesWhenAgentPIDMakesExistingStatusVisible() throws {
        let workspace = Workspace()
        let panelId = try #require(workspace.focusedPanelId)
        workspace.statusEntries["codex"] = SidebarStatusEntry(
            key: "codex",
            value: "Running",
            icon: "bolt.fill",
            color: "#4C8DFF"
        )
        #expect(
            !workspace.sidebarStatusEntriesInDisplayOrder().contains { $0.key == "codex" },
            "Structured agent statuses stay hidden until a live agent runtime owns the status key."
        )

        let generationBeforeRecord = workspace.sidebarAgentRuntimeObservation.changeGeneration
        var workspaceWillChangeCount = 0
        let objectWillChangeCancellable = workspace.objectWillChange.sink {
            workspaceWillChangeCount += 1
        }
        defer { objectWillChangeCancellable.cancel() }

        workspace.recordAgentPID(
            key: "codex.session-b",
            pid: 12_345,
            panelId: panelId,
            refreshPorts: false
        )

        #expect(
            workspace.sidebarStatusEntriesInDisplayOrder().contains { $0.key == "codex" },
            "Recording the agent PID makes the existing Running status visible."
        )
        #expect(
            workspace.sidebarAgentRuntimeObservation.changeGeneration > generationBeforeRecord,
            "Agent PID ownership changes must notify the sidebar row runtime observation stream."
        )
        #expect(
            workspaceWillChangeCount == 0,
            "Agent PID ownership is sidebar presentation state and must not broadly invalidate Workspace observers."
        )
    }

    @Test func terminalAgentContextDoesNotObserveAgentRuntimeMaps() throws {
        let workspace = Workspace()
        let panelId = try #require(workspace.focusedPanelId)
        let panel = try #require(workspace.panels[panelId])
        let changeFlag = ObservationChangeFlag()

        withObservationTracking {
            _ = WorkspaceContentView.terminalAgentContext(panel: panel, workspace: workspace)
        } onChange: {
            changeFlag.mark()
        }

        workspace.recordAgentPID(
            key: "codex.session-c",
            pid: 12_346,
            panelId: panelId,
            refreshPorts: false
        )

        #expect(
            changeFlag.fired == false,
            "Terminal content must not subscribe to sidebar-only agent runtime map churn."
        )
    }

    @Test func sidebarImmediateObservationPublisherEmitsForLateTitleSubscriber() {
        let workspace = Workspace()
        workspace.title = "Restored Workspace"

        var publishCount = 0
        let cancellable = workspace.sidebarImmediateObservationPublisher.sink {
            publishCount += 1
        }
        defer { cancellable.cancel() }

        #expect(
            publishCount > 0,
            "A sidebar row that subscribes after immediate workspace fields already exist must still refresh from the current workspace state."
        )
    }

    // The push-path signal behind the agent-room wire port: hooks register the
    // agent PID over the socket at session-start, and the wire dot must key off
    // that registration instantly (the restorable-session index reloads seconds
    // later). Covers the liveness rules of `hasLiveStructuredAgentPID`.
    @Test func structuredAgentPIDWithLiveProcessCountsAsLiveCodingAgent() throws {
        let workspace = Workspace()
        let panelId = try #require(workspace.focusedPanelId)
        workspace.recordAgentPID(
            key: "claude_code",
            pid: 54_321,
            panelId: panelId,
            refreshPorts: false
        )

        #expect(
            workspace.hasLiveStructuredAgentPID(forPanelId: panelId, isProcessAlive: { $0 == 54_321 }),
            "A structured agent key with a live pid must count as a live coding agent."
        )
        #expect(
            !workspace.hasLiveStructuredAgentPID(forPanelId: panelId, isProcessAlive: { _ in false }),
            "A structured agent key whose pid is dead (SIGKILL, no session-end hook) must not pin the signal."
        )
        #expect(
            !workspace.hasLiveStructuredAgentPID(forPanelId: UUID(), isProcessAlive: { _ in true }),
            "Panels without an agent registration must not count."
        )
    }

    @Test func structuredAgentPIDKeyWithDotSuffixMapsToStatusKey() throws {
        let workspace = Workspace()
        let panelId = try #require(workspace.focusedPanelId)
        workspace.recordAgentPID(
            key: "codex.session-b",
            pid: 12_345,
            panelId: panelId,
            refreshPorts: false
        )

        #expect(
            workspace.hasLiveStructuredAgentPID(forPanelId: panelId, isProcessAlive: { $0 == 12_345 }),
            "Suffixed PID keys (codex.session-b) must resolve to their structured status key."
        )
    }

    @Test func nonStructuredAgentPIDKeyIsIgnored() throws {
        let workspace = Workspace()
        let panelId = try #require(workspace.focusedPanelId)
        workspace.recordAgentPID(
            key: "my_custom_script",
            pid: 999,
            panelId: panelId,
            refreshPorts: false
        )

        #expect(
            !workspace.hasLiveStructuredAgentPID(forPanelId: panelId, isProcessAlive: { _ in true }),
            "Arbitrary set_agent_pid keys outside the structured agent set must not count as coding agents."
        )
    }

    @Test func structuredAgentOwnershipWithoutPIDCountsAsLive() throws {
        let workspace = Workspace()
        let panelId = try #require(workspace.focusedPanelId)
        // Ownership registered without a pid (hooks that never captured one).
        workspace.agentPIDKeysByPanelId[panelId] = ["claude_code"]

        #expect(
            workspace.hasLiveStructuredAgentPID(forPanelId: panelId, isProcessAlive: { _ in false }),
            "Registration without a pid has nothing to validate and must be trusted."
        )
    }

    @Test func codingAgentCommandMatcherCoversDirectWrappedAndNestedLaunches() {
        #expect(MosaicTaskManagerCodingAgentDefinition.matchingCommand("claude --resume abc")?.id == "claude")
        #expect(MosaicTaskManagerCodingAgentDefinition.matchingCommand("env FOO=bar codex")?.id == "codex")
        #expect(MosaicTaskManagerCodingAgentDefinition.matchingCommand("bash -lc 'cd /tmp && opencode'")?.id == "opencode")
        #expect(MosaicTaskManagerCodingAgentDefinition.matchingCommand("printf done; cursor-agent")?.id == "cursor")
        #expect(MosaicTaskManagerCodingAgentDefinition.matchingCommand("swift test") == nil)
        #expect(MosaicTaskManagerCodingAgentDefinition.matchingCommand("echo codex") == nil)
        #expect(MosaicTaskManagerCodingAgentDefinition.matchingCommand("git commit -m 'use gemini'") == nil)
    }

    @Test func foregroundCodingAgentHintAppearsAtCommandStartAndClearsAtPrompt() throws {
        let workspace = Workspace()
        let panelId = try #require(workspace.focusedPanelId)
        let generationBeforeLaunch = workspace.sidebarAgentRuntimeObservation.changeGeneration

        workspace.updateForegroundCodingAgentHint(
            panelId: panelId,
            shellState: .commandRunning,
            command: "env DEBUG=1 gemini"
        )

        #expect(workspace.foregroundCodingAgentKind(forPanelId: panelId) == "gemini")
        #expect(workspace.sidebarAgentRuntimeObservation.changeGeneration > generationBeforeLaunch)

        workspace.updateForegroundCodingAgentHint(
            panelId: panelId,
            shellState: .promptIdle,
            command: nil
        )

        #expect(workspace.foregroundCodingAgentKind(forPanelId: panelId) == nil)
    }

    @Test func promptClearsOnlyOptimisticHintAndKeepsConfirmedPID() throws {
        let workspace = Workspace()
        let panelId = try #require(workspace.focusedPanelId)
        workspace.updateForegroundCodingAgentHint(
            panelId: panelId,
            shellState: .commandRunning,
            command: "codex"
        )
        workspace.recordAgentPID(
            key: "codex.session-confirmed",
            pid: 42_424,
            panelId: panelId,
            refreshPorts: false
        )

        workspace.updateForegroundCodingAgentHint(
            panelId: panelId,
            shellState: .promptIdle,
            command: nil
        )

        #expect(workspace.foregroundCodingAgentKind(forPanelId: panelId) == nil)
        #expect(workspace.hasLiveStructuredAgentPID(
            forPanelId: panelId,
            isProcessAlive: { $0 == 42_424 }
        ))
    }

    @Test func confirmedAgentEndClearsOptimisticLaunchHint() throws {
        let workspace = Workspace()
        let panelId = try #require(workspace.focusedPanelId)
        workspace.updateForegroundCodingAgentHint(
            panelId: panelId,
            shellState: .commandRunning,
            command: "claude"
        )
        workspace.recordAgentPID(
            key: "claude_code",
            pid: 54_321,
            panelId: panelId,
            refreshPorts: false
        )

        #expect(workspace.clearAgentPID(
            key: "claude_code",
            panelId: panelId,
            refreshPorts: false
        ))
        #expect(workspace.foregroundCodingAgentKind(forPanelId: panelId) == nil)
    }

    @Test func foregroundCodingAgentHintsArePrunedWithSurfaceMetadata() throws {
        let workspace = Workspace()
        let panelId = try #require(workspace.focusedPanelId)
        workspace.updateForegroundCodingAgentHint(
            panelId: panelId,
            shellState: .commandRunning,
            command: "qodercli"
        )

        workspace.pruneSurfaceMetadata(validSurfaceIds: [])

        #expect(workspace.foregroundCodingAgentKind(forPanelId: panelId) == nil)
    }

    @Test func sidebarObservationPublisherIgnoresRemoteHeartbeatOnlyChanges() {
        let workspace = Workspace()

        var publishCount = 0
        let cancellable = workspace.sidebarObservationPublisher.sink {
            publishCount += 1
        }
        defer { cancellable.cancel() }
        publishCount = 0

        workspace.remoteHeartbeatCount = 1
        workspace.remoteLastHeartbeatAt = Date()

        #expect(
            publishCount == 0,
            "Expected non-visible remote heartbeat updates to avoid invalidating sidebar rows"
        )
    }
}

// Mutable flag captured by Observation's Sendable onChange closure in this test.
private final class ObservationChangeFlag: @unchecked Sendable {
    private(set) var fired = false

    func mark() {
        fired = true
    }
}
