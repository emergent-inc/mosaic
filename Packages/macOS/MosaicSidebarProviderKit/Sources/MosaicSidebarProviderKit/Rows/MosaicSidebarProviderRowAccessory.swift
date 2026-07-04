import Foundation

/// Accessory control displayed at the trailing edge of a provider row.
public struct MosaicSidebarProviderRowAccessory: Codable, Equatable, Sendable {
    /// Accessory behavior.
    public var kind: MosaicSidebarProviderRowAccessoryKind
    /// SF Symbols name for the accessory icon.
    public var systemImageName: String
    /// Default popover tab when the accessory opens workspace details.
    public var defaultTab: MosaicSidebarProviderWorkspacePopoverTab

    /// Creates a row accessory.
    public init(
        kind: MosaicSidebarProviderRowAccessoryKind,
        systemImageName: String,
        defaultTab: MosaicSidebarProviderWorkspacePopoverTab
    ) {
        self.kind = kind
        self.systemImageName = systemImageName
        self.defaultTab = defaultTab
    }

    /// Standard workspace inspector accessory.
    public static let inspector = MosaicSidebarProviderRowAccessory(
        kind: .workspaceInspector,
        systemImageName: "ellipsis.circle",
        defaultTab: .notes
    )
}
