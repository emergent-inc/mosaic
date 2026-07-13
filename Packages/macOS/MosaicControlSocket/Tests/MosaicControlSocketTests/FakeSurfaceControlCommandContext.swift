import Foundation
@testable import MosaicControlSocket

@MainActor
final class FakeSurfaceControlCommandContext: ControlCommandContext {
    var paneCreateResolution: ControlPaneCreateResolution = .tabManagerUnavailable
    var createResolution: ControlSurfaceCreateResolution = .tabManagerUnavailable
    var reportPWDResolution: ControlSurfaceReportPWDResolution = .recorded(surfaceID: UUID())
    var reportedPWD: (workspaceID: UUID, requestedSurfaceID: UUID?, path: String)?
    var reportShellStateResolution: ControlSurfaceReportShellStateResolution = .pending
    var reportedShellState: (
        workspaceID: UUID,
        requestedSurfaceID: UUID?,
        stateRawValue: String,
        command: String?
    )?
    var reportedSidebarShellState: (
        scope: ControlSidebarPanelScope,
        stateRawValue: String,
        command: String?
    )?

    func controlWindowSummaries() -> [ControlWindowSummary] { [] }
    func controlResolveCurrentWindow(routing: ControlRoutingSelectors) -> ControlCurrentWindowResolution {
        .tabManagerUnavailable
    }
    func controlFocusWindow(id: UUID) -> Bool { false }
    func controlCreateWindowAndActivate() -> UUID? { nil }
    func controlCloseWindow(id: UUID) -> Bool { false }
    func controlAvailableDisplays() -> [ControlDisplayInfo] { [] }
    func controlWindowExists(id: UUID) -> Bool { false }
    func controlMoveWindow(id: UUID, toDisplayMatching query: String) -> String? { nil }
    func controlMoveAllWindows(toDisplayMatching query: String) -> ControlMoveAllWindowsResult? { nil }
    func controlSurfaceRoutingResolvesTabManager(routing: ControlRoutingSelectors) -> Bool { true }
    func controlPaneRoutingResolvesTabManager(routing: ControlRoutingSelectors) -> Bool { true }

    func controlPaneCreate(
        routing: ControlRoutingSelectors,
        inputs: ControlPaneCreateInputs
    ) -> ControlPaneCreateResolution {
        paneCreateResolution
    }

    func controlSurfaceCreate(
        routing: ControlRoutingSelectors,
        inputs: ControlSurfaceCreateInputs
    ) -> ControlSurfaceCreateResolution {
        createResolution
    }

    func controlSurfaceReportPWD(
        workspaceID: UUID,
        requestedSurfaceID: UUID?,
        path: String
    ) -> ControlSurfaceReportPWDResolution {
        reportedPWD = (workspaceID, requestedSurfaceID, path)
        return reportPWDResolution
    }

    func controlSurfaceParseShellActivityState(_ rawState: String) -> String? {
        ["prompt", "running", "unknown"].contains(rawState) ? rawState : nil
    }

    func controlSurfaceReportShellState(
        workspaceID: UUID,
        requestedSurfaceID: UUID?,
        stateRawValue: String,
        command: String?
    ) -> ControlSurfaceReportShellStateResolution {
        reportedShellState = (workspaceID, requestedSurfaceID, stateRawValue, command)
        return reportShellStateResolution
    }

    func controlSidebarScheduleScopedShellState(
        scope: ControlSidebarPanelScope,
        stateRawValue: String,
        command: String?
    ) {
        reportedSidebarShellState = (scope, stateRawValue, command)
    }
}
