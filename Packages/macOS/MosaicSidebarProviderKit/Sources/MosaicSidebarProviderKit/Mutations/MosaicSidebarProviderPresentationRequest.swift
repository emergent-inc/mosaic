import Foundation

/// Presentation command a provider can request from the MOSAIC sidebar host.
public enum MosaicSidebarProviderPresentationRequest: Codable, Equatable, Sendable {
    /// Open the workspace popover on a preferred tab.
    case openWorkspacePopover(workspaceId: UUID, preferredTab: MosaicSidebarProviderWorkspacePopoverTab)
    /// Open a detached workspace window on a preferred tab.
    case openWorkspaceWindow(workspaceId: UUID, preferredTab: MosaicSidebarProviderWorkspacePopoverTab)
    /// Ask MOSAIC to open a URL.
    case openURL(String)
}
