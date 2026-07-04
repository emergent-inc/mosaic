import Foundation

/// Row rendered inside a provider section.
public struct MosaicSidebarProviderRow: Identifiable, Codable, Equatable, Sendable {
    /// Stable row id.
    public var id: UUID
    /// Primary row title.
    public var title: String
    /// Workspace represented by the row.
    public var workspaceId: UUID
    /// Optional trailing accessory.
    public var accessory: MosaicSidebarProviderRowAccessory?
    /// Optional subtitle.
    public var subtitle: MosaicSidebarProviderText?
    /// Optional trailing text.
    public var trailingText: MosaicSidebarProviderText?
    /// Optional leading icon.
    public var leadingIcon: MosaicSidebarProviderIcon?

    /// Creates a provider row.
    public init(
        id: UUID,
        title: String,
        workspaceId: UUID,
        accessory: MosaicSidebarProviderRowAccessory?,
        subtitle: MosaicSidebarProviderText? = nil,
        trailingText: MosaicSidebarProviderText? = nil,
        leadingIcon: MosaicSidebarProviderIcon? = nil
    ) {
        self.id = id
        self.title = title
        self.workspaceId = workspaceId
        self.accessory = accessory
        self.subtitle = subtitle
        self.trailingText = trailingText
        self.leadingIcon = leadingIcon
    }
}
