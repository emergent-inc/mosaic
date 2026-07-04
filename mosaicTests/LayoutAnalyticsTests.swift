import Bonsplit
import Testing

#if canImport(Mosaic_DEV)
@testable import Mosaic_DEV
#elseif canImport(Mosaic)
@testable import Mosaic
#endif

@MainActor
@Suite struct LayoutAnalyticsTests {
    @Test func singleTerminalWorkspaceBuildsOneTerminalDescriptor() throws {
        let workspace = Workspace()

        let snapshot = LayoutAnalytics.buildLayoutSnapshot(workspace: workspace, workspaceIndex: 2)

        #expect(snapshot.paneCount == 1)
        #expect(snapshot.terminalPaneCount == 1)
        #expect(snapshot.browserPaneCount == 0)
        #expect(snapshot.fileViewerPaneCount == 0)
        #expect(snapshot.otherPaneCount == 0)
        #expect(snapshot.splitOrientation == "none")
        #expect(snapshot.activePaneType == "terminal")
        #expect(snapshot.layoutDescriptor == "1T")
        #expect(snapshot.workspaceIndex == 2)
    }

    @Test func horizontalSplitAddsOrientationSuffix() throws {
        let workspace = Workspace()
        let sourcePanelId = try #require(workspace.focusedPanelId)

        _ = try #require(
            workspace.newTerminalSplit(from: sourcePanelId, orientation: .horizontal, focus: true)
        )

        let snapshot = LayoutAnalytics.buildLayoutSnapshot(workspace: workspace, workspaceIndex: 0)

        #expect(snapshot.paneCount == 2)
        #expect(snapshot.terminalPaneCount == 2)
        #expect(snapshot.splitOrientation == "horizontal")
        #expect(snapshot.layoutDescriptor == "2T-H")
        #expect(Self.allowedActivePaneTypes.contains(snapshot.activePaneType))
    }

    @Test func nestedDifferentOrientationSplitReportsMixed() throws {
        let workspace = Workspace()
        let firstPanelId = try #require(workspace.focusedPanelId)
        let secondPanel = try #require(
            workspace.newTerminalSplit(from: firstPanelId, orientation: .horizontal, focus: true)
        )

        _ = try #require(
            workspace.newTerminalSplit(from: secondPanel.id, orientation: .vertical, focus: true)
        )

        let snapshot = LayoutAnalytics.buildLayoutSnapshot(workspace: workspace, workspaceIndex: 0)

        #expect(snapshot.paneCount == 3)
        #expect(snapshot.terminalPaneCount == 3)
        #expect(snapshot.splitOrientation == "mixed")
        #expect(snapshot.layoutDescriptor == "3T-mixed")
    }

    @Test func descriptorIncludesEveryPaneTypeAndNeverReturnsEmptyString() {
        #expect(
            LayoutAnalytics.buildDescriptor(
                terminal: 1,
                browser: 1,
                fileViewer: 1,
                other: 1,
                orientation: "vertical"
            ) == "1T1B1F1X-V"
        )

        #expect(
            LayoutAnalytics.buildDescriptor(
                terminal: 0,
                browser: 0,
                fileViewer: 0,
                other: 0,
                orientation: "none"
            ) == "0X"
        )
    }

    @Test func snapshotPropertiesUseExpectedAnalyticsKeysAndValues() {
        let snapshot = TerminalLayoutSnapshot(
            paneCount: 2,
            terminalPaneCount: 1,
            browserPaneCount: 1,
            fileViewerPaneCount: 0,
            otherPaneCount: 0,
            splitOrientation: "horizontal",
            activePaneType: "browser",
            layoutDescriptor: "1T1B-H",
            workspaceIndex: 4
        )

        let properties = snapshot.properties

        #expect(properties["pane_count"] as? Int == 2)
        #expect(properties["terminal_pane_count"] as? Int == 1)
        #expect(properties["browser_pane_count"] as? Int == 1)
        #expect(properties["file_viewer_pane_count"] as? Int == 0)
        #expect(properties["other_pane_count"] as? Int == 0)
        #expect(properties["split_orientation"] as? String == "horizontal")
        #expect(properties["active_pane_type"] as? String == "browser")
        #expect(properties["layout_descriptor"] as? String == "1T1B-H")
        #expect(properties["workspace_index"] as? Int == 4)
        #expect(properties.keys.allSatisfy { !$0.contains("path") && !$0.contains("title") && !$0.contains("url") })

        let sanitized = PostHogAnalytics.sanitizedProperties(
            properties.merging(["file_path": "/Users/example/private"]) { current, _ in current },
            infoDictionary: [:]
        )
        #expect(sanitized["file_viewer_pane_count"] as? Int == 0)
        #expect(sanitized["file_path"] == nil)
    }

    private static let allowedActivePaneTypes: Set<String> = [
        "terminal",
        "browser",
        "file_viewer",
        "other",
    ]
}
