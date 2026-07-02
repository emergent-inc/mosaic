/// Semantic event type for an agent room ledger.
public enum ClaudeRoomEventKind: String, Codable, Sendable, Equatable {
    /// A compact summary of a completed turn.
    case summary
    /// A direct task intended for another room participant.
    case task
    /// A durable decision the room should preserve.
    case decision
    /// A discovered fact or observation.
    case finding
    /// A source file or artifact changed.
    case fileChanged
    /// A validation result from tests, builds, or checks.
    case testResult
    /// A blocker that should interrupt dependent participants.
    case blocker
    /// A question one participant wants another participant to answer.
    case question
    /// A task handoff to another participant.
    case handoff
    /// A review finding that needs attention or acknowledgement.
    case reviewFinding
    /// A status update that should stay lightweight.
    case status
    /// Free-form demo message.
    case message
}
