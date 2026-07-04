/// Builds focused context packs from room ledger events and transcript turns.
public struct AgentRoomContextCompiler: Sendable {
    /// Maximum number of ledger events included by default.
    public let maxEvents: Int
    /// Maximum number of transcript turns included by default.
    public let maxTranscriptTurns: Int

    /// Creates a context compiler.
    ///
    /// - Parameters:
    ///   - maxEvents: Maximum number of ledger events included by default.
    ///   - maxTranscriptTurns: Maximum number of transcript turns included by default.
    public init(maxEvents: Int = 8, maxTranscriptTurns: Int = 6) {
        self.maxEvents = maxEvents
        self.maxTranscriptTurns = maxTranscriptTurns
    }

    /// Compiles a focused context pack for a room participant.
    ///
    /// Room-visible events and directly targeted events are included. Transcript
    /// turns are supplied by the caller after query/recent-history selection.
    public func contextPack(
        room: ClaudeRoomSnapshot,
        transcriptTurns: [AgentRoomTranscriptTurn],
        memberID: String? = nil,
        surfaceID: String? = nil,
        sinceEventSequence: Int? = nil,
        maxEvents eventLimit: Int? = nil,
        maxTranscriptTurns transcriptLimit: Int? = nil
    ) -> AgentRoomContextPack {
        let lowerBound = sinceEventSequence ?? 0
        let events = room.events
            .filter { $0.sequence > lowerBound }
            .filter { isVisible($0, memberID: memberID, surfaceID: surfaceID) }
            .suffix(eventLimit ?? maxEvents)
        let turns = transcriptTurns
            .filter { $0.roomID == room.id }
            .suffix(transcriptLimit ?? maxTranscriptTurns)
        return AgentRoomContextPack(
            roomID: room.id,
            memberID: memberID,
            surfaceID: surfaceID,
            events: Array(events),
            transcriptTurns: Array(turns),
            latestEventSequence: events.last?.sequence ?? lowerBound,
            latestTranscriptSequence: turns.last?.sequence ?? 0
        )
    }

    private func isVisible(_ event: ClaudeRoomEvent, memberID: String?, surfaceID: String?) -> Bool {
        let hasMemberTargets = !event.targetMemberIDs.isEmpty
        let hasSurfaceTargets = !event.targetSurfaceIDs.isEmpty
        guard hasMemberTargets || hasSurfaceTargets else { return true }
        if let memberID, event.targetMemberIDs.contains(memberID) { return true }
        if let surfaceID, event.targetSurfaceIDs.contains(surfaceID) { return true }
        return false
    }
}
