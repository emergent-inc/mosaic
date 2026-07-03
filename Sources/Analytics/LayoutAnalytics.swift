import Bonsplit
import Foundation

/// Describes the analytics representation of a workspace layout.
struct TerminalLayoutSnapshot {
    let paneCount: Int
    let terminalPaneCount: Int
    let browserPaneCount: Int
    let fileViewerPaneCount: Int
    let otherPaneCount: Int
    let splitOrientation: String
    let activePaneType: String
    let layoutDescriptor: String
    let workspaceIndex: Int

    var properties: [String: Any] {
        [
            "pane_count": paneCount,
            "terminal_pane_count": terminalPaneCount,
            "browser_pane_count": browserPaneCount,
            "file_viewer_pane_count": fileViewerPaneCount,
            "other_pane_count": otherPaneCount,
            "split_orientation": splitOrientation,
            "active_pane_type": activePaneType,
            "layout_descriptor": layoutDescriptor,
            "workspace_index": workspaceIndex,
        ]
    }
}

@MainActor
struct LayoutAnalytics {
    static let snapshotEventName = "terminal_layout_snapshot"
    static let changedEventName = "terminal_layout_changed"

    static func buildLayoutSnapshot(workspace: Workspace, workspaceIndex: Int) -> TerminalLayoutSnapshot {
        var terminalCount = 0
        var browserCount = 0
        var fileViewerCount = 0
        var otherCount = 0

        let paneIds = workspace.bonsplitController.allPaneIds
        for paneId in paneIds {
            switch selectedPaneType(workspace: workspace, paneId: paneId) {
            case "terminal":
                terminalCount += 1
            case "browser":
                browserCount += 1
            case "file_viewer":
                fileViewerCount += 1
            default:
                otherCount += 1
            }
        }

        let splitOrientation = deriveSplitOrientation(workspace: workspace)
        let descriptor = buildDescriptor(
            terminal: terminalCount,
            browser: browserCount,
            fileViewer: fileViewerCount,
            other: otherCount,
            orientation: splitOrientation
        )

        return TerminalLayoutSnapshot(
            paneCount: paneIds.count,
            terminalPaneCount: terminalCount,
            browserPaneCount: browserCount,
            fileViewerPaneCount: fileViewerCount,
            otherPaneCount: otherCount,
            splitOrientation: splitOrientation,
            activePaneType: deriveActivePaneType(workspace: workspace),
            layoutDescriptor: descriptor,
            workspaceIndex: workspaceIndex
        )
    }

    static func captureSnapshot(workspace: Workspace, workspaceIndex: Int, trigger: Trigger) {
        capture(snapshotEventName, workspace: workspace, workspaceIndex: workspaceIndex, trigger: trigger)
    }

    static func captureChanged(workspace: Workspace, workspaceIndex: Int, trigger: Trigger) {
        capture(changedEventName, workspace: workspace, workspaceIndex: workspaceIndex, trigger: trigger)
    }

    private static func capture(_ eventName: String, workspace: Workspace, workspaceIndex: Int, trigger: Trigger) {
        let snapshot = buildLayoutSnapshot(workspace: workspace, workspaceIndex: workspaceIndex)
        var properties = snapshot.properties
        properties["trigger"] = trigger.rawValue
        PostHogAnalytics.shared.capture(eventName, properties: properties)
    }

    private static func deriveSplitOrientation(workspace: Workspace) -> String {
        let orientations = splitOrientations(in: workspace.bonsplitController.treeSnapshot())
        guard !orientations.isEmpty else { return "none" }
        guard orientations.count == 1, let orientation = orientations.first else { return "mixed" }
        return orientation
    }

    private static func deriveActivePaneType(workspace: Workspace) -> String {
        guard let focusedPaneId = workspace.bonsplitController.focusedPaneId else {
            return "other"
        }
        return selectedPaneType(workspace: workspace, paneId: focusedPaneId)
    }

    private static func selectedPaneType(workspace: Workspace, paneId: PaneID) -> String {
        guard let tab = workspace.bonsplitController.selectedTab(inPane: paneId),
              let panelId = workspace.panelIdFromSurfaceId(tab.id),
              let panel = workspace.panels[panelId] else {
            return "other"
        }
        return paneType(for: panel)
    }

    private static func paneType(for panel: any Panel) -> String {
        switch panel.panelType {
        case .terminal:
            return "terminal"
        case .browser:
            return "browser"
        case .filePreview:
            return "file_viewer"
        case .markdown, .rightSidebarTool, .customSidebar, .agentSession, .project, .extensionBrowser:
            return "other"
        }
    }

    private static func splitOrientations(in node: ExternalTreeNode) -> Set<String> {
        switch node {
        case .pane:
            return []
        case .split(let split):
            var orientations = splitOrientations(in: split.first)
            orientations.formUnion(splitOrientations(in: split.second))
            if split.orientation == "horizontal" || split.orientation == "vertical" {
                orientations.insert(split.orientation)
            }
            return orientations
        }
    }

    static func buildDescriptor(
        terminal: Int,
        browser: Int,
        fileViewer: Int,
        other: Int,
        orientation: String
    ) -> String {
        var parts: [String] = []
        if terminal > 0 { parts.append("\(terminal)T") }
        if browser > 0 { parts.append("\(browser)B") }
        if fileViewer > 0 { parts.append("\(fileViewer)F") }
        if other > 0 { parts.append("\(other)X") }

        let base = parts.isEmpty ? "0X" : parts.joined()

        switch orientation {
        case "horizontal":
            return "\(base)-H"
        case "vertical":
            return "\(base)-V"
        case "mixed":
            return "\(base)-mixed"
        default:
            return base
        }
    }

    enum Trigger: String {
        case appLaunched = "app_launched"
        case paneCreated = "pane_created"
        case paneClosed = "pane_closed"
        case splitHorizontal = "split_horizontal"
        case splitVertical = "split_vertical"
        case splitClosed = "split_closed"
        case paneMoved = "pane_moved"
    }
}

@MainActor
private enum TerminalLayoutLaunchCaptureState {
    static var capturedTabManagers: Set<ObjectIdentifier> = []

    static func shouldCapture(tabManager: TabManager) -> Bool {
        capturedTabManagers.insert(ObjectIdentifier(tabManager)).inserted
    }
}

extension TabManager {
    func publishTerminalLayoutLaunchSnapshotsIfNeeded() {
        guard TerminalLayoutLaunchCaptureState.shouldCapture(tabManager: self) else { return }

        for (index, workspace) in tabs.enumerated() {
            LayoutAnalytics.captureSnapshot(
                workspace: workspace,
                workspaceIndex: index,
                trigger: .appLaunched
            )
        }
    }
}

extension Workspace {
    func publishTerminalLayoutChanged(trigger: LayoutAnalytics.Trigger) {
        guard let manager = owningTabManager,
              let workspaceIndex = manager.tabs.firstIndex(where: { $0.id == id }) else {
            return
        }
        LayoutAnalytics.captureChanged(
            workspace: self,
            workspaceIndex: workspaceIndex,
            trigger: trigger
        )
    }
}
