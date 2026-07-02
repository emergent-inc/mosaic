public import Foundation

/// One queryable turn from an agent transcript.
public struct AgentRoomTranscriptTurn: Identifiable, Codable, Sendable, Equatable {
    /// Stable transcript turn identifier.
    public let id: String
    /// Room that owns this indexed turn.
    public let roomID: String
    /// Monotonic sequence within the room transcript index.
    public let sequence: Int
    /// Agent/runtime source, such as `claude` or `codex`.
    public let agentKind: String
    /// Sender member identifier, when known.
    public let memberID: String?
    /// Sender surface identifier, when known.
    public let surfaceID: String?
    /// Speaker role for this turn.
    public let role: AgentRoomTranscriptRole
    /// Transcript text available for query and context packs.
    public let text: String
    /// Optional original transcript sequence from the agent runtime.
    public let sourceSequence: Int?
    /// Optional original transcript identifier from the agent runtime.
    public let sourceID: String?
    /// Turn creation time.
    public let createdAt: Date

    /// Creates an indexed transcript turn.
    ///
    /// - Parameters:
    ///   - id: Stable transcript turn identifier.
    ///   - roomID: Room that owns this indexed turn.
    ///   - sequence: Monotonic sequence within the room transcript index.
    ///   - agentKind: Agent/runtime source, such as `claude` or `codex`.
    ///   - memberID: Sender member identifier, when known.
    ///   - surfaceID: Sender surface identifier, when known.
    ///   - role: Speaker role for this turn.
    ///   - text: Transcript text available for query and context packs.
    ///   - sourceSequence: Optional original transcript sequence from the agent runtime.
    ///   - sourceID: Optional original transcript identifier from the agent runtime.
    ///   - createdAt: Turn creation time.
    public init(
        id: String = UUID().uuidString,
        roomID: String,
        sequence: Int,
        agentKind: String,
        memberID: String? = nil,
        surfaceID: String? = nil,
        role: AgentRoomTranscriptRole,
        text: String,
        sourceSequence: Int? = nil,
        sourceID: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.roomID = roomID
        self.sequence = sequence
        self.agentKind = agentKind
        self.memberID = memberID
        self.surfaceID = surfaceID
        self.role = role
        self.text = text
        self.sourceSequence = sourceSequence
        self.sourceID = sourceID
        self.createdAt = createdAt
    }
}
