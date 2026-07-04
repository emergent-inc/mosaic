import Foundation

/// Stable metadata MOSAIC uses to identify and present an in-process sidebar provider.
public struct MosaicSidebarProviderDescriptor: Identifiable, Codable, Equatable, Sendable {
    /// Provider id for the built-in workspace sidebar.
    public static let defaultWorkspacesID = "mosaic.sidebar.default"

    /// Stable provider identifier persisted in user selection state.
    public var id: String
    /// Localized provider title shown in sidebar provider menus.
    public var title: MosaicSidebarProviderLocalizedText
    /// Optional localized detail text shown under the provider title.
    public var subtitle: MosaicSidebarProviderLocalizedText?
    /// SF Symbols name used for this provider in menus.
    public var systemImageName: String
    /// Whether the provider is supplied by MOSAIC rather than a package example.
    public var isHostProvided: Bool

    /// Creates sidebar provider metadata.
    public init(
        id: String,
        title: MosaicSidebarProviderLocalizedText,
        subtitle: MosaicSidebarProviderLocalizedText? = nil,
        systemImageName: String,
        isHostProvided: Bool
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImageName = systemImageName
        self.isHostProvided = isHostProvided
    }

    /// Descriptor for MOSAIC's built-in workspace sidebar.
    public static let defaultWorkspaces = MosaicSidebarProviderDescriptor(
        id: defaultWorkspacesID,
        title: MosaicSidebarProviderLocalizedText(key: "sidebar.provider.default.title", defaultValue: "Default Workspaces"),
        subtitle: MosaicSidebarProviderLocalizedText(key: "sidebar.provider.default.subtitle", defaultValue: "mosaic"),
        systemImageName: "list.bullet",
        isHostProvided: true
    )
}
