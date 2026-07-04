import Foundation

public struct MosaicSidebarSnapshot: Codable, Equatable, Sendable {
    public var apiVersion: MosaicExtensionAPIVersion
    public var sequence: UInt64
    public var windowID: UUID?
    public var selectedWorkspaceID: UUID?
    public var grantedReadScopes: Set<MosaicExtensionScope>
    public var grantedActionScopes: Set<MosaicExtensionActionScope>
    public var workspaces: [MosaicSidebarWorkspace]

    public init(
        apiVersion: MosaicExtensionAPIVersion = .sidebarV2,
        sequence: UInt64,
        windowID: UUID? = nil,
        selectedWorkspaceID: UUID?,
        grantedReadScopes: Set<MosaicExtensionScope> = [],
        grantedActionScopes: Set<MosaicExtensionActionScope> = [],
        workspaces: [MosaicSidebarWorkspace]
    ) {
        self.apiVersion = apiVersion
        self.sequence = sequence
        self.windowID = windowID
        self.selectedWorkspaceID = selectedWorkspaceID
        self.grantedReadScopes = grantedReadScopes
        self.grantedActionScopes = grantedActionScopes
        self.workspaces = workspaces
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiVersion = try container.decode(MosaicExtensionAPIVersion.self, forKey: .apiVersion)
        sequence = try container.decode(UInt64.self, forKey: .sequence)
        windowID = try container.decodeIfPresent(UUID.self, forKey: .windowID)
        selectedWorkspaceID = try container.decodeIfPresent(UUID.self, forKey: .selectedWorkspaceID)
        grantedReadScopes = try container.decodeLossySetIfPresent(MosaicExtensionScope.self, forKey: .grantedReadScopes)
        grantedActionScopes = try container.decodeLossySetIfPresent(MosaicExtensionActionScope.self, forKey: .grantedActionScopes)
        workspaces = try container.decode([MosaicSidebarWorkspace].self, forKey: .workspaces)
    }

    @_spi(MosaicHostTransport)
    public func filtered(
        for scopes: some Sequence<MosaicExtensionScope>,
        actionScopes: some Sequence<MosaicExtensionActionScope> = []
    ) -> MosaicSidebarSnapshot {
        let scopeSet = Set(scopes)
        let actionScopeSet = Set(actionScopes)
        guard scopeSet.contains(.workspaceList) || scopeSet.contains(.workspaceMetadata) else {
            return MosaicSidebarSnapshot(
                apiVersion: apiVersion,
                sequence: sequence,
                selectedWorkspaceID: nil,
                grantedReadScopes: scopeSet,
                grantedActionScopes: actionScopeSet,
                workspaces: []
            )
        }
        return MosaicSidebarSnapshot(
            apiVersion: apiVersion,
            sequence: sequence,
            windowID: scopeSet.contains(.workspaceMetadata) ? windowID : nil,
            selectedWorkspaceID: scopeSet.contains(.workspaceMetadata) ? selectedWorkspaceID : nil,
            grantedReadScopes: scopeSet,
            grantedActionScopes: actionScopeSet,
            workspaces: workspaces.map { workspace in
                scopeSet.contains(.workspaceMetadata)
                    ? workspace.filtered(for: scopeSet)
                    : MosaicSidebarWorkspace(id: workspace.id, title: "")
            }
        )
    }
}

private extension KeyedDecodingContainer {
    func decodeLossySetIfPresent<Value>(
        _ type: Value.Type,
        forKey key: Key
    ) throws -> Set<Value> where Value: RawRepresentable, Value.RawValue == String, Value: Hashable {
        guard let rawValues = try decodeIfPresent([String].self, forKey: key) else { return [] }
        return Set(rawValues.compactMap(type.init(rawValue:)))
    }
}
