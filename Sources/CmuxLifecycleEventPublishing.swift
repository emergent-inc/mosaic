import Foundation
import AppKit
import Bonsplit

@MainActor
private enum CmuxSelectionEventState {
    static var selectedSurfaceByWorkspacePane: [String: UUID] = [:]
    static var focusedPaneByWorkspace: [UUID: UUID] = [:]
    static var focusedSurfaceByWorkspace: [UUID: UUID] = [:]

    static func paneKey(workspaceId: UUID, paneId: UUID) -> String {
        "\(workspaceId.uuidString):\(paneId.uuidString)"
    }

    static func clearWorkspace(_ workspaceId: UUID) {
        selectedSurfaceByWorkspacePane = selectedSurfaceByWorkspacePane.filter {
            !$0.key.hasPrefix("\(workspaceId.uuidString):")
        }
        focusedPaneByWorkspace.removeValue(forKey: workspaceId)
        focusedSurfaceByWorkspace.removeValue(forKey: workspaceId)
    }

    static func clearPane(workspaceId: UUID, paneId: UUID) {
        selectedSurfaceByWorkspacePane.removeValue(forKey: paneKey(workspaceId: workspaceId, paneId: paneId))
        if focusedPaneByWorkspace[workspaceId] == paneId {
            focusedPaneByWorkspace.removeValue(forKey: workspaceId)
        }
    }

    static func clearSurface(workspaceId: UUID, surfaceId: UUID) {
        selectedSurfaceByWorkspacePane = selectedSurfaceByWorkspacePane.filter { $0.value != surfaceId }
        if focusedSurfaceByWorkspace[workspaceId] == surfaceId {
            focusedSurfaceByWorkspace.removeValue(forKey: workspaceId)
        }
    }
}

extension TabManager {
    func publishCmuxWorkspaceCreated(_ workspace: Workspace, selected: Bool) {
        CmuxEventBus.shared.publishWorkspaceCreated(
            workspaceId: workspace.id,
            title: workspace.cmuxEventWorkspaceTitle,
            customTitle: workspace.customTitle,
            currentDirectory: workspace.currentDirectory,
            selected: selected,
            index: tabs.firstIndex(where: { $0.id == workspace.id }),
            tabCount: tabs.count
        )
        ProductAnalytics.shared.trackSemantic(
            .workspaceCreated,
            featureArea: .workspace,
            entrypoint: .system,
            result: .completed,
            properties: [
                "workspace_id_hash": ProductAnalyticsPrivacy.hashIdentifier(workspace.id.uuidString),
                "workspace_count": tabs.count,
                "workspace_index": tabs.firstIndex(where: { $0.id == workspace.id }) ?? -1,
                "selected": selected,
            ]
        )
    }

    func publishCmuxInitialSurfaceCreated(_ workspace: Workspace, selected: Bool) {
        guard let panelId = workspace.focusedSurfaceId,
              let panel = workspace.panels[panelId] else { return }
        workspace.publishCmuxSurfaceCreated(
            panelId,
            paneId: workspace.paneId(forPanelId: panelId),
            kind: Workspace.cmuxEventSurfaceKind(panel),
            origin: "workspace_initial",
            focused: selected
        )
    }

    func publishCmuxWorkspaceClosed(_ workspace: Workspace) {
        CmuxEventBus.shared.publishWorkspaceClosed(
            workspaceId: workspace.id,
            title: workspace.cmuxEventWorkspaceTitle,
            customTitle: workspace.customTitle,
            currentDirectory: workspace.currentDirectory,
            remainingTabCount: tabs.count
        )
        ProductAnalytics.shared.trackSemantic(
            .workspaceClosed,
            featureArea: .workspace,
            entrypoint: .system,
            result: .completed,
            properties: [
                "workspace_id_hash": ProductAnalyticsPrivacy.hashIdentifier(workspace.id.uuidString),
                "workspace_count": tabs.count,
            ]
        )
        CmuxSelectionEventState.clearWorkspace(workspace.id)
    }

    func publishCmuxWorkspaceSelected(_ workspace: Workspace) {
        CmuxEventBus.shared.publishWorkspaceSelected(
            workspaceId: workspace.id,
            title: workspace.cmuxEventWorkspaceTitle,
            customTitle: workspace.customTitle,
            currentDirectory: workspace.currentDirectory,
            previousWorkspaceId: nil,
            index: tabs.firstIndex(where: { $0.id == workspace.id }),
            tabCount: tabs.count
        )
        ProductAnalytics.shared.trackSemantic(
            .workspaceSelected,
            featureArea: .workspace,
            entrypoint: .system,
            result: .completed,
            properties: [
                "workspace_id_hash": ProductAnalyticsPrivacy.hashIdentifier(workspace.id.uuidString),
                "workspace_count": tabs.count,
                "workspace_index": tabs.firstIndex(where: { $0.id == workspace.id }) ?? -1,
            ]
        )
    }

    func publishCmuxWorkspaceSelectedChange(from previousWorkspaceId: UUID?) {
        guard let selectedTabId,
              let workspace = tabs.first(where: { $0.id == selectedTabId }) else { return }
        CmuxEventBus.shared.publishWorkspaceSelected(
            workspaceId: workspace.id,
            title: workspace.cmuxEventWorkspaceTitle,
            customTitle: workspace.customTitle,
            currentDirectory: workspace.currentDirectory,
            previousWorkspaceId: previousWorkspaceId,
            index: tabs.firstIndex(where: { $0.id == workspace.id }),
            tabCount: tabs.count
        )
        var properties: [String: Any] = [
            "workspace_id_hash": ProductAnalyticsPrivacy.hashIdentifier(workspace.id.uuidString),
            "workspace_count": tabs.count,
            "workspace_index": tabs.firstIndex(where: { $0.id == workspace.id }) ?? -1,
        ]
        if let previousWorkspaceId {
            properties["previous_workspace_id_hash"] = ProductAnalyticsPrivacy.hashIdentifier(previousWorkspaceId.uuidString)
        }
        ProductAnalytics.shared.trackSemantic(
            .workspaceSelected,
            featureArea: .workspace,
            entrypoint: .system,
            result: .completed,
            properties: properties
        )
    }
}

extension Workspace {
    var cmuxEventWorkspaceTitle: String {
        customTitle ?? title
    }

    func publishCmuxSplitCreated(
        _ paneId: PaneID,
        sourcePaneId: PaneID?,
        orientation: SplitOrientation,
        surfaceId: UUID?,
        kind: String,
        origin: String,
        focused: Bool
    ) {
        CmuxEventBus.shared.publishPaneCreated(
            workspaceId: id,
            paneId: paneId.id,
            sourcePaneId: sourcePaneId?.id,
            orientation: orientation.rawValue,
            surfaceId: surfaceId,
            origin: origin
        )
        var properties = cmuxAnalyticsLayoutProperties(snapshotReason: "split_created")
        properties["pane_id_hash"] = ProductAnalyticsPrivacy.hashIdentifier(paneId.id.uuidString)
        properties["origin"] = origin
        properties["orientation"] = orientation.rawValue
        properties["surface_kind"] = kind
        if let sourcePaneId {
            properties["source_pane_id_hash"] = ProductAnalyticsPrivacy.hashIdentifier(sourcePaneId.id.uuidString)
        }
        if let surfaceId {
            properties["surface_id_hash"] = ProductAnalyticsPrivacy.hashIdentifier(surfaceId.uuidString)
        }
        let splitEvent: MacAnalyticsEvent = kind == "browser" ? .browserSplitCreated : (kind == "terminal" ? .terminalSplitCreated : .surfaceSplitCreated)
        ProductAnalytics.shared.trackSemantic(
            splitEvent,
            featureArea: kind == "browser" ? .browser : (kind == "terminal" ? .terminal : .workspace),
            entrypoint: ProductAnalyticsEntrypoint(origin: origin),
            result: .completed,
            properties: properties
        )
        if let surfaceId {
            publishCmuxSurfaceCreated(surfaceId, paneId: paneId, kind: kind, origin: origin, focused: focused)
        }
    }

    func publishCmuxSurfaceCreated(
        _ surfaceId: UUID,
        paneId: PaneID?,
        kind: String,
        origin: String,
        focused: Bool
    ) {
        CmuxEventBus.shared.publishSurfaceCreated(
            workspaceId: id,
            surfaceId: surfaceId,
            paneId: paneId?.id,
            kind: kind,
            origin: origin,
            focused: focused
        )
        var properties = cmuxAnalyticsLayoutProperties(snapshotReason: kind == "browser" ? "browser_opened" : "surface_created")
        properties["surface_id_hash"] = ProductAnalyticsPrivacy.hashIdentifier(surfaceId.uuidString)
        properties["surface_kind"] = kind
        properties["origin"] = origin
        properties["focused"] = focused
        if let paneId {
            properties["pane_id_hash"] = ProductAnalyticsPrivacy.hashIdentifier(paneId.id.uuidString)
        }
        let event: MacAnalyticsEvent
        let featureArea: ProductAnalyticsFeatureArea
        switch kind {
        case "browser":
            event = origin.contains("split") ? .browserSplitCreated : .browserOpened
            featureArea = .browser
        case "terminal":
            event = origin.contains("split") ? .terminalSplitCreated : .terminalCreated
            featureArea = .terminal
        default:
            event = .surfaceCreated
            featureArea = .workspace
        }
        ProductAnalytics.shared.trackSemantic(
            event,
            featureArea: featureArea,
            entrypoint: ProductAnalyticsEntrypoint(origin: origin),
            result: .completed,
            properties: properties
        )
        ProductAnalytics.shared.trackSemantic(
            .workspaceLayoutSnapshotRecorded,
            featureArea: .workspace,
            entrypoint: ProductAnalyticsEntrypoint(origin: origin),
            result: .completed,
            properties: properties
        )
    }

    func publishCmuxSurfaceClosed(_ surfaceId: UUID, paneId: PaneID?, panel: (any Panel)?, origin: String) {
        CmuxEventBus.shared.publishSurfaceClosed(
            workspaceId: id,
            surfaceId: surfaceId,
            paneId: paneId?.id,
            kind: panel.map(Self.cmuxEventSurfaceKind),
            origin: origin
        )
        var properties = cmuxAnalyticsLayoutProperties(snapshotReason: "surface_closed")
        properties["surface_id_hash"] = ProductAnalyticsPrivacy.hashIdentifier(surfaceId.uuidString)
        properties["origin"] = origin
        if let kind = panel.map(Self.cmuxEventSurfaceKind) {
            properties["surface_kind"] = kind
        }
        if let paneId {
            properties["pane_id_hash"] = ProductAnalyticsPrivacy.hashIdentifier(paneId.id.uuidString)
        }
        ProductAnalytics.shared.trackSemantic(
            .surfaceClosed,
            featureArea: .workspace,
            entrypoint: ProductAnalyticsEntrypoint(origin: origin),
            result: .completed,
            properties: properties
        )
        CmuxSelectionEventState.clearSurface(workspaceId: id, surfaceId: surfaceId)
    }

    func publishCmuxPaneClosed(_ paneId: PaneID, closedPanelIds: [UUID], origin: String) {
        CmuxEventBus.shared.publishPaneClosed(
            workspaceId: id,
            paneId: paneId.id,
            closedSurfaceIds: closedPanelIds,
            origin: origin
        )
        CmuxSelectionEventState.clearPane(workspaceId: id, paneId: paneId.id)
    }

    func publishCmuxFocusedSelection(paneId: PaneID, surfaceId: UUID, origin: String) {
        let paneKey = CmuxSelectionEventState.paneKey(workspaceId: id, paneId: paneId.id)
        let previousSelectedSurfaceId = CmuxSelectionEventState.selectedSurfaceByWorkspacePane[paneKey]
        let kind = panels[surfaceId].map(Self.cmuxEventSurfaceKind)

        if previousSelectedSurfaceId != surfaceId {
            CmuxSelectionEventState.selectedSurfaceByWorkspacePane[paneKey] = surfaceId
            CmuxEventBus.shared.publishSurfaceSelected(
                workspaceId: id,
                surfaceId: surfaceId,
                paneId: paneId.id,
                kind: kind,
                previousSurfaceId: previousSelectedSurfaceId,
                focused: true,
                origin: origin
            )
            var properties: [String: Any] = [
                "workspace_id_hash": ProductAnalyticsPrivacy.hashIdentifier(id.uuidString),
                "surface_id_hash": ProductAnalyticsPrivacy.hashIdentifier(surfaceId.uuidString),
                "pane_id_hash": ProductAnalyticsPrivacy.hashIdentifier(paneId.id.uuidString),
                "origin": origin,
                "focused": true,
            ]
            if let kind {
                properties["surface_kind"] = kind
            }
            if let previousSelectedSurfaceId {
                properties["previous_surface_id_hash"] = ProductAnalyticsPrivacy.hashIdentifier(previousSelectedSurfaceId.uuidString)
            }
            ProductAnalytics.shared.trackSemantic(
                .surfaceSelected,
                featureArea: .workspace,
                entrypoint: ProductAnalyticsEntrypoint(origin: origin),
                result: .completed,
                properties: properties
            )
        }

        if CmuxSelectionEventState.focusedPaneByWorkspace[id] != paneId.id {
            CmuxSelectionEventState.focusedPaneByWorkspace[id] = paneId.id
            CmuxEventBus.shared.publishPaneFocused(
                workspaceId: id,
                paneId: paneId.id,
                selectedSurfaceId: surfaceId,
                origin: origin
            )
        }

        if CmuxSelectionEventState.focusedSurfaceByWorkspace[id] != surfaceId {
            CmuxSelectionEventState.focusedSurfaceByWorkspace[id] = surfaceId
            CmuxEventBus.shared.publishSurfaceFocused(
                workspaceId: id,
                surfaceId: surfaceId,
                paneId: paneId.id,
                kind: kind,
                origin: origin
            )
        }
    }

    static func cmuxEventSurfaceKind(_ panel: any Panel) -> String {
        switch panel.panelType {
        case .terminal:
            return "terminal"
        case .browser:
            return "browser"
        case .markdown:
            return "markdown"
        case .filePreview:
            return "file_preview"
        case .rightSidebarTool:
            return "right_sidebar_tool"
        case .customSidebar:
            return "custom_sidebar"
        case .agentSession:
            return "agent_session"
        case .project:
            return "project"
        case .extensionBrowser:
            return "extension_browser"
        }
    }

    func cmuxAnalyticsLayoutProperties(snapshotReason: String) -> [String: Any] {
        let paneIds = bonsplitController.allPaneIds
        var terminalCount = 0
        var browserCount = 0
        var otherCount = 0
        var tabCount = 0
        var paneSummaries: [[String: Any]] = []

        for (paneIndex, paneId) in paneIds.enumerated() {
            let tabs = bonsplitController.tabs(inPane: paneId)
            tabCount += tabs.count
            var tabKinds: [String] = []
            for tab in tabs {
                guard let panelId = panelIdFromSurfaceId(tab.id),
                      let panel = panels[panelId] else { continue }
                let kind = Self.cmuxEventSurfaceKind(panel)
                tabKinds.append(kind)
                switch kind {
                case "terminal":
                    terminalCount += 1
                case "browser":
                    browserCount += 1
                default:
                    otherCount += 1
                }
            }
            paneSummaries.append([
                "pane_index": paneIndex,
                "selected": bonsplitController.focusedPaneId == paneId,
                "tab_count": tabs.count,
                "kinds": tabKinds,
            ])
        }

        let focusedPaneKind = bonsplitController.focusedPaneId
            .flatMap { paneId in
                bonsplitController.selectedTab(inPane: paneId)
                    .flatMap { panelIdFromSurfaceId($0.id) }
                    .flatMap { panels[$0] }
                    .map(Self.cmuxEventSurfaceKind)
            } ?? "none"
        let layoutTree = Self.cmuxAnalyticsJSONString([
            "panes": paneSummaries,
        ])
        let fingerprintSource = "\(paneSummaries)"

        return [
            "workspace_id_hash": ProductAnalyticsPrivacy.hashIdentifier(id.uuidString),
            "pane_count": paneIds.count,
            "terminal_pane_count": terminalCount,
            "browser_pane_count": browserCount,
            "other_pane_count": otherCount,
            "local_pane_count": tabCount,
            "remote_pane_count": 0,
            "shared_pane_count": 0,
            "split_count": max(0, paneIds.count - 1),
            "split_depth": paneIds.count,
            "tab_count": tabCount,
            "focused_pane_kind": focusedPaneKind,
            "layout_tree": layoutTree,
            "layout_fingerprint": ProductAnalyticsPrivacy.hashIdentifier(fingerprintSource),
            "snapshot_reason": snapshotReason,
        ]
    }

    private static func cmuxAnalyticsJSONString(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string.count <= 2_048 ? string : String(string.prefix(2_048))
    }
}

@MainActor
private enum MainWindowKeyRegainRefresh {
    static func refresh(window: NSWindow, context: AppDelegate.MainWindowContext) {
        // Window focus regain owns the redraw invariant. Cursor tracking and
        // focused subviews can update themselves only after this invalidation.
        invalidateContentDisplayTree(window: window)
        _ = context.keyboardFocusCoordinator.restoreTargetAfterWindowBecameKey()
    }

    private static func invalidateContentDisplayTree(window: NSWindow) {
        guard let contentView = window.contentView else { return }
        invalidateDisplayTree(rootedAt: contentView)
        window.invalidateCursorRects(for: contentView)
    }

    private static func invalidateDisplayTree(rootedAt view: NSView) {
        guard !view.isHidden else { return }
        view.needsDisplay = true
        view.layer?.setNeedsDisplay()
        for subview in view.subviews {
            invalidateDisplayTree(rootedAt: subview)
        }
    }
}

extension AppDelegate {
    func handleCmuxWindowBecameKey(_ note: Notification) {
        guard let window = note.object as? NSWindow else { return }
        MainActor.assumeIsolated {
            let context = contextForMainTerminalWindow(window)
            setActiveMainWindow(window)
            if let windowId = mainWindowId(from: window) {
                publishCmuxWindowLifecycle(name: "window.keyed", windowId: windowId, origin: "appkit_key")
            }
            if let context {
                MainWindowKeyRegainRefresh.refresh(window: window, context: context)
            }
        }
    }

    func handleCmuxWindowResignedKey(_ note: Notification) {
        guard let window = note.object as? NSWindow else { return }
        MainActor.assumeIsolated {
            if let windowId = mainWindowId(from: window) {
                publishCmuxWindowLifecycle(name: "window.unkeyed", windowId: windowId, origin: "appkit_key")
            }
        }
    }

    func publishCmuxWindowLifecycle(name: String, windowId: UUID, origin: String) {
        let manager = tabManagerFor(windowId: windowId)
        let workspaceId = manager?.selectedTabId
        let workspaceCount = manager?.tabs.count
        let selectedWorkspaceIndex = workspaceId.flatMap { selectedId in
            manager?.tabs.firstIndex(where: { $0.id == selectedId })
        }
        let window = mainWindow(for: windowId)
        let isKeyWindow = window?.isKeyWindow
        let isMainWindow = window?.isMainWindow
        CmuxEventBus.shared.publishWindowLifecycle(
            name: name,
            windowId: windowId,
            workspaceId: workspaceId,
            workspaceCount: workspaceCount,
            selectedWorkspaceIndex: selectedWorkspaceIndex,
            isKeyWindow: isKeyWindow,
            isMainWindow: isMainWindow,
            origin: origin
        )
        let event: MacAnalyticsEvent
        switch name {
        case "window.created":
            event = .windowCreated
        case "window.closed":
            event = .windowClosed
        default:
            event = .windowFocused
        }
        var properties: [String: Any] = [
            "window_id_hash": ProductAnalyticsPrivacy.hashIdentifier(windowId.uuidString),
            "origin": origin,
        ]
        if let workspaceId {
            properties["workspace_id_hash"] = ProductAnalyticsPrivacy.hashIdentifier(workspaceId.uuidString)
        }
        if let workspaceCount {
            properties["workspace_count"] = workspaceCount
        }
        if let selectedWorkspaceIndex {
            properties["selected_workspace_index"] = selectedWorkspaceIndex
        }
        if let isKeyWindow {
            properties["is_key_window"] = isKeyWindow
        }
        if let isMainWindow {
            properties["is_main_window"] = isMainWindow
        }
        ProductAnalytics.shared.trackSemantic(
            event,
            featureArea: .windowing,
            entrypoint: ProductAnalyticsEntrypoint(origin: origin),
            result: .completed,
            properties: properties
        )
    }
}

extension ProductAnalyticsEntrypoint {
    init(origin: String) {
        switch origin {
        case let value where value.contains("shortcut"):
            self = .shortcut
        case let value where value.contains("palette"):
            self = .commandPalette
        case let value where value.contains("menu"):
            self = .menu
        case let value where value.contains("socket"):
            self = .socket
        case let value where value.contains("cli"):
            self = .cli
        case let value where value.contains("tab"):
            self = .tabBar
        case let value where value.contains("restore"):
            self = .restore
        default:
            self = .system
        }
    }
}
