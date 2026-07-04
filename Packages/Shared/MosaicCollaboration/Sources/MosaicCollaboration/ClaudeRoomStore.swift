public import Foundation

/// Room store used by the agent room runtime. Optionally persists rooms,
/// members (including acknowledgment cursors), events, and indexed transcript
/// turns to disk so shared context survives an app relaunch.
public actor ClaudeRoomStore {
    /// On-disk shape. Versioned so a future migration can detect old files.
    private struct PersistedState: Codable {
        var version: Int = 1
        var rooms: [String: ClaudeRoomSnapshot] = [:]
        var transcriptTurnsByRoomID: [String: [AgentRoomTranscriptTurn]] = [:]
    }

    private var rooms: [String: ClaudeRoomSnapshot] = [:]
    private var transcriptTurnsByRoomID: [String: [AgentRoomTranscriptTurn]] = [:]
    private let maxEventsPerRoom: Int
    private let maxTranscriptTurnsPerRoom: Int
    private let persistenceURL: URL?

    /// Creates a room store.
    ///
    /// - Parameters:
    ///   - maxEventsPerRoom: Ledger event cap per room.
    ///   - maxTranscriptTurnsPerRoom: Indexed transcript turn cap per room.
    ///   - persistenceURL: When non-nil, state is loaded from this file at init
    ///     and re-written after every mutation, so rooms/cursors/events survive
    ///     an app restart (previously an in-memory-only store silently erased
    ///     all shared context on relaunch).
    public init(
        maxEventsPerRoom: Int = 200,
        maxTranscriptTurnsPerRoom: Int = 2_000,
        persistenceURL: URL? = nil
    ) {
        self.maxEventsPerRoom = maxEventsPerRoom
        self.maxTranscriptTurnsPerRoom = maxTranscriptTurnsPerRoom
        self.persistenceURL = persistenceURL
        if let persistenceURL,
           let data = try? Data(contentsOf: persistenceURL),
           let state = try? JSONDecoder().decode(PersistedState.self, from: data) {
            self.rooms = state.rooms
            self.transcriptTurnsByRoomID = state.transcriptTurnsByRoomID
        }
    }

    /// Writes the current state to `persistenceURL` (atomic; no-op when the
    /// store was created without persistence). Room mutations are low-frequency
    /// (turn boundaries, wiring), so an immediate full write is fine.
    private func persist() {
        guard let persistenceURL else { return }
        let state = PersistedState(
            rooms: rooms,
            transcriptTurnsByRoomID: transcriptTurnsByRoomID
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(
            at: persistenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: persistenceURL, options: .atomic)
    }

    /// Creates and stores a new room.
    public func createRoom(
        id: String = UUID().uuidString,
        title: String? = nil,
        deliveryPolicy: ClaudeRoomDeliveryPolicy = .manual
    ) -> ClaudeRoomSnapshot {
        let room = ClaudeRoomSnapshot(id: id, title: title, deliveryPolicy: deliveryPolicy)
        rooms[id] = room
        persist()
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

    /// Removes one room and its indexed transcript turns.
    @discardableResult
    public func removeRoom(id: String) -> ClaudeRoomSnapshot? {
        let removed = rooms.removeValue(forKey: id)
        transcriptTurnsByRoomID.removeValue(forKey: id)
        if removed != nil {
            persist()
        }
        return removed
    }

    /// Removes every room and indexed transcript turn.
    public func clearAllRooms() {
        guard !rooms.isEmpty || !transcriptTurnsByRoomID.isEmpty else { return }
        rooms.removeAll()
        transcriptTurnsByRoomID.removeAll()
        persist()
    }

    /// Upserts a member into a room, creating the room when needed.
    public func connect(member: ClaudeRoomMember, to roomID: String) -> ClaudeRoomSnapshot {
        var room = rooms[roomID] ?? ClaudeRoomSnapshot(id: roomID)
        if let index = room.members.firstIndex(where: { $0.id == member.id || $0.surfaceID == member.surfaceID }) {
            // Re-connecting an existing surface must not reset its acknowledgment
            // cursor: a re-wire (or an app relaunch re-adopting persisted rooms)
            // would otherwise replay the entire ledger backlog at the member.
            var updated = member
            if updated.acknowledgedEventSequence == nil {
                updated.acknowledgedEventSequence = room.members[index].acknowledgedEventSequence
            }
            room.members[index] = updated
        } else {
            room.members.append(member)
        }
        rooms[roomID] = room
        persist()
        return room
    }

    /// Updates a room's delivery policy, creating the room when needed.
    @discardableResult
    public func setDeliveryPolicy(roomID: String, policy: ClaudeRoomDeliveryPolicy) -> ClaudeRoomSnapshot {
        var room = rooms[roomID] ?? ClaudeRoomSnapshot(id: roomID)
        room.deliveryPolicy = policy
        rooms[roomID] = room
        persist()
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
        persist()
        return room
    }

    /// Appends an event and assigns the next room sequence.
    ///
    /// When `sourceID` is non-nil and a room event already carries the same
    /// `sourceID`, no new event is appended and the existing one is returned.
    /// This makes wire-time ledger backfill idempotent across repeated joins.
    public func appendEvent(
        roomID: String,
        kind: ClaudeRoomEventKind,
        fromMemberID: String? = nil,
        fromSurfaceID: String? = nil,
        targetMemberIDs: [String] = [],
        targetSurfaceIDs: [String] = [],
        text: String,
        sourceID: String? = nil,
        createdAt: Date = Date()
    ) -> (room: ClaudeRoomSnapshot, event: ClaudeRoomEvent) {
        var room = rooms[roomID] ?? ClaudeRoomSnapshot(id: roomID)
        if let sourceID,
           let existing = room.events.first(where: { $0.sourceID == sourceID }) {
            return (room, existing)
        }
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
            sourceID: sourceID,
            createdAt: createdAt
        )
        room.lastSequence = nextSequence
        room.events.append(event)
        if room.events.count > maxEventsPerRoom {
            room.events.removeFirst(room.events.count - maxEventsPerRoom)
        }
        rooms[roomID] = room
        persist()
        return (room, event)
    }

    /// Applies a remote room snapshot.
    public func apply(snapshot: ClaudeRoomSnapshot) {
        rooms[snapshot.id] = snapshot
        persist()
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
        persist()
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
        persist()
        return room
    }

    /// Returns unacknowledged events visible to a member/surface and advances the
    /// member's acknowledgment cursor to the room's latest sequence.
    ///
    /// This is the pull-based delivery primitive: a peer's own Claude hook (Stop or
    /// UserPromptSubmit) calls this once per turn boundary to drain anything shared
    /// since it last acted. Because the cursor advances to `lastSequence`, each event
    /// is delivered to a given member at most once, which is what prevents relay loops.
    ///
    /// Filtering:
    /// - Excludes events with `sequence <= acknowledgedEventSequence`.
    /// - Excludes events this member/surface itself sent.
    /// - Excludes events explicitly targeted at *other* members/surfaces (an event with
    ///   empty targets is room-visible; one with targets is delivered only if this
    ///   member or surface is among them).
    public func consumePendingEvents(
        roomID: String,
        memberID: String? = nil,
        surfaceID: String? = nil
    ) -> [ClaudeRoomEvent] {
        guard var room = rooms[roomID] else { return [] }
        let memberIndex = room.members.firstIndex { member in
            if let memberID, member.id == memberID { return true }
            if let surfaceID, member.surfaceID == surfaceID { return true }
            return false
        }
        let resolvedMemberID = memberIndex.map { room.members[$0].id } ?? memberID
        let resolvedSurfaceID = memberIndex.map { room.members[$0].surfaceID } ?? surfaceID
        let acknowledged = memberIndex.flatMap { room.members[$0].acknowledgedEventSequence } ?? 0
        let pending = room.events.filter { event in
            guard event.sequence > acknowledged else { return false }
            if let resolvedSurfaceID, event.fromSurfaceID == resolvedSurfaceID { return false }
            if let resolvedMemberID, event.fromMemberID == resolvedMemberID { return false }
            if !event.targetSurfaceIDs.isEmpty || !event.targetMemberIDs.isEmpty {
                let matchesSurface = resolvedSurfaceID.map { event.targetSurfaceIDs.contains($0) } ?? false
                let matchesMember = resolvedMemberID.map { event.targetMemberIDs.contains($0) } ?? false
                guard matchesSurface || matchesMember else { return false }
            }
            return true
        }
        if let memberIndex {
            room.members[memberIndex].acknowledgedEventSequence = max(acknowledged, room.lastSequence)
            rooms[roomID] = room
            persist()
        }
        return pending
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
        persist()
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
