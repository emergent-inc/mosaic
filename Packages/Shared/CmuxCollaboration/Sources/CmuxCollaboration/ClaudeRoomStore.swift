public import Foundation

/// In-memory room store used by the agent room runtime.
public actor ClaudeRoomStore {
    private var rooms: [String: ClaudeRoomSnapshot] = [:]
    private var transcriptTurnsByRoomID: [String: [AgentRoomTranscriptTurn]] = [:]
    private let maxEventsPerRoom: Int
    private let maxTranscriptTurnsPerRoom: Int

    /// Creates a room store.
    public init(maxEventsPerRoom: Int = 200, maxTranscriptTurnsPerRoom: Int = 2_000) {
        self.maxEventsPerRoom = maxEventsPerRoom
        self.maxTranscriptTurnsPerRoom = maxTranscriptTurnsPerRoom
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

    /// Updates a room's delivery policy, creating the room when needed.
    @discardableResult
    public func setDeliveryPolicy(roomID: String, policy: ClaudeRoomDeliveryPolicy) -> ClaudeRoomSnapshot {
        var room = rooms[roomID] ?? ClaudeRoomSnapshot(id: roomID)
        room.deliveryPolicy = policy
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

    /// Appends a transcript turn to the room's queryable transcript index.
    public func appendTranscriptTurn(
        roomID: String,
        agentKind: String,
        memberID: String? = nil,
        surfaceID: String? = nil,
        role: AgentRoomTranscriptRole,
        text: String,
        sourceSequence: Int? = nil,
        sourceID: String? = nil,
        createdAt: Date = Date()
    ) -> AgentRoomTranscriptTurn {
        let existing = transcriptTurnsByRoomID[roomID] ?? []
        if let sourceID,
           let duplicate = existing.first(where: { $0.sourceID == sourceID }) {
            return duplicate
        }
        let nextSequence = (existing.last?.sequence ?? 0) + 1
        let turn = AgentRoomTranscriptTurn(
            roomID: roomID,
            sequence: nextSequence,
            agentKind: agentKind,
            memberID: memberID,
            surfaceID: surfaceID,
            role: role,
            text: text,
            sourceSequence: sourceSequence,
            sourceID: sourceID,
            createdAt: createdAt
        )
        transcriptTurnsByRoomID[roomID] = trimmedTranscriptTurns(existing + [turn])
        return turn
    }

    /// Returns recent transcript turns for a room, optionally scoped to a member or surface.
    public func transcriptTurns(
        roomID: String,
        memberID: String? = nil,
        surfaceID: String? = nil,
        sinceSequence: Int? = nil,
        limit: Int = 50
    ) -> [AgentRoomTranscriptTurn] {
        selectedTranscriptTurns(
            roomID: roomID,
            memberID: memberID,
            surfaceID: surfaceID,
            sinceSequence: sinceSequence,
            limit: limit
        )
    }

    /// Searches indexed transcript turns with a case-insensitive substring query.
    public func searchTranscripts(
        roomID: String,
        query: String,
        memberID: String? = nil,
        surfaceID: String? = nil,
        limit: Int = 20
    ) -> [AgentRoomTranscriptTurn] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return selectedTranscriptTurns(
                roomID: roomID,
                memberID: memberID,
                surfaceID: surfaceID,
                limit: limit
            )
        }
        return Array(selectedTranscriptTurns(
            roomID: roomID,
            memberID: memberID,
            surfaceID: surfaceID,
            limit: maxTranscriptTurnsPerRoom
        )
        .filter { $0.text.localizedCaseInsensitiveContains(trimmedQuery) }
        .suffix(limit))
    }

    /// Builds a focused context pack from room ledger deltas and transcript excerpts.
    public func contextPack(
        roomID: String,
        memberID: String? = nil,
        surfaceID: String? = nil,
        sinceEventSequence: Int? = nil,
        transcriptQuery: String? = nil,
        maxEvents: Int = 8,
        maxTranscriptTurns: Int = 6
    ) -> AgentRoomContextPack? {
        guard let room = rooms[roomID] else { return nil }
        let transcriptTurns: [AgentRoomTranscriptTurn]
        if let transcriptQuery,
           !transcriptQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Explicit transcript lookup is evidence retrieval from the room,
            // not recipient-scoped prompt history. Call `searchTranscripts`
            // directly when a caller wants member/surface filtering.
            transcriptTurns = searchTranscripts(
                roomID: roomID,
                query: transcriptQuery,
                limit: maxTranscriptTurns
            )
        } else {
            transcriptTurns = selectedTranscriptTurns(
                roomID: roomID,
                memberID: memberID,
                surfaceID: surfaceID,
                limit: maxTranscriptTurns
            )
        }
        return AgentRoomContextCompiler(
            maxEvents: maxEvents,
            maxTranscriptTurns: maxTranscriptTurns
        )
        .contextPack(
            room: room,
            transcriptTurns: transcriptTurns,
            memberID: memberID,
            surfaceID: surfaceID,
            sinceEventSequence: sinceEventSequence,
            maxEvents: maxEvents,
            maxTranscriptTurns: maxTranscriptTurns
        )
    }

    /// Builds a focused context pack from room ledger events and peer transcript excerpts.
    public func peerContextPack(
        roomID: String,
        recipientMemberID: String? = nil,
        recipientSurfaceID: String? = nil,
        sinceEventSequence: Int? = nil,
        maxEvents: Int = 8,
        maxTranscriptTurns: Int = 6
    ) -> AgentRoomContextPack? {
        guard let room = rooms[roomID] else { return nil }
        let transcriptTurns = Array((transcriptTurnsByRoomID[roomID] ?? [])
            .filter { turn in
                if let recipientMemberID, turn.memberID == recipientMemberID { return false }
                if let recipientSurfaceID, turn.surfaceID == recipientSurfaceID { return false }
                return true
            }
            .suffix(maxTranscriptTurns))
        return AgentRoomContextCompiler(
            maxEvents: maxEvents,
            maxTranscriptTurns: maxTranscriptTurns
        )
        .contextPack(
            room: room,
            transcriptTurns: transcriptTurns,
            memberID: recipientMemberID,
            surfaceID: recipientSurfaceID,
            sinceEventSequence: sinceEventSequence,
            maxEvents: maxEvents,
            maxTranscriptTurns: maxTranscriptTurns
        )
    }

    private func selectedTranscriptTurns(
        roomID: String,
        memberID: String? = nil,
        surfaceID: String? = nil,
        sinceSequence: Int? = nil,
        limit: Int
    ) -> [AgentRoomTranscriptTurn] {
        let lowerBound = sinceSequence ?? 0
        return Array((transcriptTurnsByRoomID[roomID] ?? [])
            .filter { $0.sequence > lowerBound }
            .filter { turn in
                if let memberID, turn.memberID != memberID { return false }
                if let surfaceID, turn.surfaceID != surfaceID { return false }
                return true
            }
            .suffix(limit))
    }

    private func trimmedTranscriptTurns(_ turns: [AgentRoomTranscriptTurn]) -> [AgentRoomTranscriptTurn] {
        guard turns.count > maxTranscriptTurnsPerRoom else { return turns }
        return Array(turns.suffix(maxTranscriptTurnsPerRoom))
    }
}
