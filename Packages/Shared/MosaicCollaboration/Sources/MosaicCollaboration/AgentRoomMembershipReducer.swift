public import Foundation

/// Local, per-surface Claude-room membership that drives the terminal header
/// "Claude room" pill. Keyed by surface UUID because only locally-owned
/// terminal surfaces (whose ids are UUIDs) render a header.
public struct AgentRoomMembershipState: Equatable, Sendable {
    /// Room id each surface is currently a member of.
    public var roomIDsBySurfaceID: [UUID: String]
    /// Room member id assigned to each surface.
    public var memberIDsBySurfaceID: [UUID: String]

    /// Creates a membership state.
    public init(
        roomIDsBySurfaceID: [UUID: String] = [:],
        memberIDsBySurfaceID: [UUID: String] = [:]
    ) {
        self.roomIDsBySurfaceID = roomIDsBySurfaceID
        self.memberIDsBySurfaceID = memberIDsBySurfaceID
    }

    /// Whether the given surface currently shows a room pill.
    public func isConnected(surfaceID: UUID) -> Bool {
        roomIDsBySurfaceID[surfaceID] != nil
    }
}

/// Reconciles local per-surface room membership against the authoritative room
/// snapshot returned by the room store.
///
/// This is the single source of truth for which surfaces show the "Claude
/// room" pill. Every entrypoint (link-button click, wire drag, header drop,
/// CLI) mutates the room store and then reconciles through here, so all
/// locally-owned members of a room show the pill and any surface that left the
/// room drops it — regardless of which entrypoint ran or in what order.
public enum AgentRoomMembershipReducer {
    /// Returns membership reconciled against `room`.
    ///
    /// - Every room member with a UUID surface id is mapped to `room.id` and
    ///   its member id (so newly connected surfaces gain the pill).
    /// - Any surface previously in `room.id` that is no longer a member is
    ///   dropped (so a disconnected surface loses the pill).
    /// - Surfaces belonging to *other* rooms are left untouched.
    /// - Members whose surface id is not a UUID (remote surfaces) are ignored;
    ///   only locally-owned surfaces render a header pill.
    public static func reconciled(
        _ state: AgentRoomMembershipState,
        with room: ClaudeRoomSnapshot
    ) -> AgentRoomMembershipState {
        var roomIDsBySurfaceID = state.roomIDsBySurfaceID
        var memberIDsBySurfaceID = state.memberIDsBySurfaceID

        var memberIDByLocalSurfaceID: [UUID: String] = [:]
        for member in room.members {
            guard let surfaceUUID = UUID(uuidString: member.surfaceID) else { continue }
            memberIDByLocalSurfaceID[surfaceUUID] = member.id
        }

        for (surfaceUUID, memberID) in memberIDByLocalSurfaceID {
            roomIDsBySurfaceID[surfaceUUID] = room.id
            memberIDsBySurfaceID[surfaceUUID] = memberID
        }

        for (surfaceUUID, roomID) in roomIDsBySurfaceID
        where roomID == room.id && memberIDByLocalSurfaceID[surfaceUUID] == nil {
            roomIDsBySurfaceID.removeValue(forKey: surfaceUUID)
            memberIDsBySurfaceID.removeValue(forKey: surfaceUUID)
        }

        return AgentRoomMembershipState(
            roomIDsBySurfaceID: roomIDsBySurfaceID,
            memberIDsBySurfaceID: memberIDsBySurfaceID
        )
    }
}
