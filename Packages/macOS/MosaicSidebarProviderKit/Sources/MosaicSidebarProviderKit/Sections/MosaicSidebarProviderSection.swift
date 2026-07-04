import Foundation

/// Rendered section with tree metadata and concrete rows.
public struct MosaicSidebarProviderSection: Identifiable, Codable, Equatable, Sendable {
    /// Stable section id.
    public var id: String
    /// Tree/list section metadata.
    public var treeSection: MosaicSidebarProviderTreeSection
    /// Rows rendered in this section.
    public var rows: [MosaicSidebarProviderRow]

    /// Creates a provider section.
    public init(
        id: String,
        treeSection: MosaicSidebarProviderTreeSection,
        rows: [MosaicSidebarProviderRow]
    ) {
        self.id = id
        self.treeSection = treeSection
        self.rows = rows
    }
}
