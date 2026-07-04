import Foundation

/// Metadata and permission request declared by a MOSAIC extension.
public struct MosaicExtensionManifest: Codable, Equatable, Identifiable, Sendable {
    /// Stable reverse-DNS style identifier for the extension.
    public var id: String

    /// Human-readable extension name shown by MOSAIC permission and management UI.
    public var displayName: String

    /// Minimum MOSAIC extension API version required by this extension.
    @_spi(MosaicHostTransport) public var minimumAPIVersion: MosaicExtensionAPIVersion

    /// Sidebar data scopes the extension asks MOSAIC to include in snapshots.
    public var readScopes: [MosaicExtensionScope]

    /// Host action scopes the extension asks MOSAIC to allow.
    public var actionScopes: [MosaicExtensionActionScope]

    /// Creates a sidebar extension manifest.
    public init(
        id: String,
        displayName: String,
        readScopes: [MosaicExtensionScope] = [],
        actionScopes: [MosaicExtensionActionScope] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.minimumAPIVersion = .sidebarV2
        self.readScopes = readScopes
        self.actionScopes = actionScopes
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case minimumAPIVersion
        case readScopes
        case actionScopes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        minimumAPIVersion = try container.decodeIfPresent(MosaicExtensionAPIVersion.self, forKey: .minimumAPIVersion) ?? .sidebarV2
        readScopes = try container.decode([MosaicExtensionScope].self, forKey: .readScopes)
        actionScopes = try container.decodeIfPresent(
            [MosaicExtensionActionScope].self,
            forKey: .actionScopes
        ) ?? []
    }
}
