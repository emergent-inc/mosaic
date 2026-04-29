import SwiftUI

extension ContentView {
    func appendMoveTabToNewWorkspaceCommandContribution(
        to contributions: inout [CommandPaletteCommandContribution],
        panelSubtitle: @escaping (CommandPaletteContextSnapshot) -> String
    ) {
        contributions.append(
            CommandPaletteCommandContribution(
                commandId: "palette.moveTabToNewWorkspace",
                title: { _ in String(localized: "command.moveTabToNewWorkspace.title", defaultValue: "Move Tab to New Workspace") },
                subtitle: panelSubtitle,
                keywords: ["move", "tab", "workspace", "detach", "sidebar", "surface"],
                when: { $0.bool(CommandPaletteContextKeys.hasFocusedPanel) },
                enablement: { $0.bool(CommandPaletteContextKeys.panelCanMoveToNewWorkspace) }
            )
        )
    }

    func moveFocusedPanelToNewWorkspace() -> Bool {
        guard let panelContext = focusedPanelContext else { return false }
        return AppDelegate.shared?.moveSurfaceToNewWorkspace(
            panelId: panelContext.panelId,
            focus: true,
            focusWindow: false
        ) != nil
    }
}

struct SidebarBonsplitTabNewWorkspaceDropDelegate: DropDelegate {
    let tabManager: TabManager
    @Binding var selectedTabIds: Set<UUID>
    @Binding var lastSidebarSelectionIndex: Int?
    @Binding var dropIndicator: SidebarDropIndicator?

    func validateDrop(info: DropInfo) -> Bool {
        guard info.hasItemsConforming(to: [BonsplitTabDragPayload.typeIdentifier]),
              let transfer = BonsplitTabDragPayload.currentTransfer(),
              let app = AppDelegate.shared else {
            return false
        }
        return app.canMoveBonsplitTabToNewWorkspace(tabId: transfer.tab.id)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else {
            dropIndicator = nil
            return nil
        }
        dropIndicator = SidebarDropIndicator(tabId: nil, edge: .bottom)
        return DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        dropIndicator = validateDrop(info: info) ? SidebarDropIndicator(tabId: nil, edge: .bottom) : nil
    }

    func dropExited(info: DropInfo) {
        dropIndicator = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { dropIndicator = nil }
        guard validateDrop(info: info),
              let transfer = BonsplitTabDragPayload.currentTransfer(),
              let app = AppDelegate.shared,
              let result = app.moveBonsplitTabToNewWorkspace(
                tabId: transfer.tab.id,
                destinationManager: tabManager,
                focus: true,
                focusWindow: true,
                placementOverride: .end
              ) else {
            return false
        }

        selectedTabIds = [result.destinationWorkspaceId]
        syncSidebarSelection(preferredSelectedTabId: result.destinationWorkspaceId)
        return true
    }

    private func syncSidebarSelection(preferredSelectedTabId: UUID? = nil) {
        let selectedId = preferredSelectedTabId ?? tabManager.selectedTabId
        if let selectedId {
            lastSidebarSelectionIndex = tabManager.tabs.firstIndex { $0.id == selectedId }
        } else {
            lastSidebarSelectionIndex = nil
        }
    }
}
