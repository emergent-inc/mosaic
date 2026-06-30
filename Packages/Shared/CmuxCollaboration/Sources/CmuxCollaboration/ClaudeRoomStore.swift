public import Foundation

/// In-memory room store used by the demo room runtime.
public actor ClaudeRoomStore {
    private var rooms: [String: ClaudeRoomSnapshot] = [:]
    private let maxEventsPerRoom: Int

    /// Creates a room store.
    public init(maxEventsPerRoom: Int = 200) {
        self.maxEventsPerRoom = maxEventsPerRoom
    }

    /// Creates and stores a new room.
    public func createRoom(
        id: String = UUID().uuidString,
        title: String? = nil,
        deliveryPolicy: ClaudeRoomDeliveryPolicy = .manual
    ) -> ClaudeRoomSnapshot {
        let room = ClaudeRoomSnapshot(id: id, title: title, deliveryPolicy: deliveryPolicy)
        rooms[id] = room
        return room
    }

    /// Returns a room snapshot.
    public func room(id: String) -> ClaudeRoomSnapshot? {
        rooms[id]
    }

    /// Returns every room snapshot.
    public func allRooms() -> [ClaudeRoomSnapshot] {
        rooms.values.sorted { $0.id < $1.id }
    }

    /// Upserts a member into a room, creating the room when needed.
    public func connect(member: ClaudeRoomMember, to roomID: String) -> ClaudeRoomSnapshot {
        var room = rooms[roomID] ?? ClaudeRoomSnapshot(id: roomID)
        if let index = room.members.firstIndex(where: { $0.id == member.id || $0.surfaceID == member.surfaceID }) {
            room.members[index] = member
        } else {
            room.members.append(member)
        }
        rooms[roomID] = room
        return room
    }

    /// Removes a member or surface from a room.
    public func disconnect(roomID: String, memberID: String?, surfaceID: String?) -> ClaudeRoomSnapshot? {
        guard var room = rooms[roomID] else { return nil }
        room.members.removeAll { member in
            if let memberID, member.id == memberID { return true }
            if let surfaceID, member.surfaceID == surfaceID { return true }
            return false
        }
        rooms[roomID] = room
        return room
    }

    /// Appends an event and assigns the next room sequence.
    public func appendEvent(
        roomID: String,
        kind: ClaudeRoomEventKind,
        fromMemberID: String? = nil,
        fromSurfaceID: String? = nil,
        targetMemberIDs: [String] = [],
        targetSurfaceIDs: [String] = [],
        text: String,
        createdAt: Date = Date()
    ) -> (room: ClaudeRoomSnapshot, event: ClaudeRoomEvent) {
        var room = rooms[roomID] ?? ClaudeRoomSnapshot(id: roomID)
        let nextSequence = room.lastSequence + 1
        let event = ClaudeRoomEvent(
            sequence: nextSequence,
            roomID: roomID,
            kind: kind,
            fromMemberID: fromMemberID,
            fromSurfaceID: fromSurfaceID,
            targetMemberIDs: targetMemberIDs,
            targetSurfaceIDs: targetSurfaceIDs,
            text: text,
            createdAt: createdAt
        )
        room.lastSequence = nextSequence
        room.events.append(event)
        if room.events.count > maxEventsPerRoom {
            room.events.removeFirst(room.events.count - maxEventsPerRoom)
        }
        rooms[roomID] = room
        return (room, event)
    }

    /// Applies a remote room snapshot.
    public func apply(snapshot: ClaudeRoomSnapshot) {
        rooms[snapshot.id] = snapshot
    }

    /// Applies a remote event if it is newer than the room's current sequence.
    public func apply(event: ClaudeRoomEvent) -> ClaudeRoomSnapshot {
        var room = rooms[event.roomID] ?? ClaudeRoomSnapshot(id: event.roomID)
        guard !room.events.contains(where: { $0.id == event.id }) else { return room }
        room.lastSequence = max(room.lastSequence, event.sequence)
        room.events.append(event)
        room.events.sort { $0.sequence < $1.sequence }
        if room.events.count > maxEventsPerRoom {
            room.events.removeFirst(room.events.count - maxEventsPerRoom)
        }
        rooms[event.roomID] = room
        return room
    }

    /// Records the latest acknowledged room sequence for a member.
    public func acknowledge(roomID: String, memberID: String, sequence: Int) -> ClaudeRoomSnapshot? {
        guard var room = rooms[roomID],
              let index = room.members.firstIndex(where: { $0.id == memberID }) else {
            return rooms[roomID]
        }
        room.members[index].acknowledgedEventSequence = max(
            room.members[index].acknowledgedEventSequence ?? 0,
            sequence
        )
        rooms[roomID] = room
        return room
    }
}
