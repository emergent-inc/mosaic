/// A focused context slice compiled for one room participant.
public struct AgentRoomContextPack: Codable, Sendable, Equatable {
    /// Room the context pack was compiled from.
    public let roomID: String
    /// Member that will receive the pack, when known.
    public let memberID: String?
    /// Surface that will receive the pack, when known.
    public let surfaceID: String?
    /// Recent room ledger events relevant to this recipient.
    public let events: [ClaudeRoomEvent]
    /// Transcript turns selected by explicit query or recent history.
    public let transcriptTurns: [AgentRoomTranscriptTurn]
    /// Highest room event sequence included in this pack.
    public let latestEventSequence: Int
    /// Highest transcript sequence included in this pack.
    public let latestTranscriptSequence: Int

    /// Creates a context pack.
    public init(
        roomID: String,
        memberID: String? = nil,
        surfaceID: String? = nil,
        events: [ClaudeRoomEvent],
        transcriptTurns: [AgentRoomTranscriptTurn],
        latestEventSequence: Int,
        latestTranscriptSequence: Int
    ) {
        self.roomID = roomID
        self.memberID = memberID
        self.surfaceID = surfaceID
        self.events = events
        self.transcriptTurns = transcriptTurns
        self.latestEventSequence = latestEventSequence
        self.latestTranscriptSequence = latestTranscriptSequence
    }

    /// Human-readable text suitable for agent-specific prompt injection.
    public var promptText: String {
        var sections: [String] = []
        if !events.isEmpty {
            sections.append(
                (["Room ledger updates:"] + events.map {
                    "- [\($0.sequence)] \($0.kind.rawValue): \($0.text)"
                }).joined(separator: "\n")
            )
        }
        if !transcriptTurns.isEmpty {
            sections.append(
                (["Queryable transcript excerpts:"] + transcriptTurns.map {
                    "- [\($0.sequence)] \($0.agentKind)/\($0.role.rawValue): \($0.text)"
                }).joined(separator: "\n")
            )
        }
        return sections.joined(separator: "\n\n")
    }
}
