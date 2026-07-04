/// Pure room-selection rules shared by the app runtime and regression tests.
///
/// The important invariant: a surface-scoped operation may only use that
/// surface's mapped room. Historical "latest room" state is allowed only for
/// explicit CLI/debug operations that omit a surface entirely; otherwise fresh
/// panes can inherit stale persisted room ledgers.
public enum AgentRoomSelection {
    public static func roomIDForSurfaceOperation(
        requestedRoomID: String?,
        surfaceWasExplicit: Bool,
        mappedSurfaceRoomID: String?,
        latestRoomID: String?
    ) -> String? {
        if let requestedRoomID { return requestedRoomID }
        if let mappedSurfaceRoomID { return mappedSurfaceRoomID }
        return surfaceWasExplicit ? nil : latestRoomID
    }

    public static func roomIDForSurfaceConnection(
        requestedRoomID: String?,
        surfaceWasExplicit: Bool,
        mappedSurfaceRoomID: String?,
        latestRoomID: String?,
        newRoomID: String
    ) -> String {
        roomIDForSurfaceOperation(
            requestedRoomID: requestedRoomID,
            surfaceWasExplicit: surfaceWasExplicit,
            mappedSurfaceRoomID: mappedSurfaceRoomID,
            latestRoomID: latestRoomID
        ) ?? newRoomID
    }

    public static func roomIDForWire(
        sourceRoomID: String?,
        targetRoomID: String?,
        newRoomID: String
    ) -> String {
        sourceRoomID ?? targetRoomID ?? newRoomID
    }
}
