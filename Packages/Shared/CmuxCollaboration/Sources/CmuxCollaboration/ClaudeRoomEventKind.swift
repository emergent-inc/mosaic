/// Semantic event type for a Claude room.
public enum ClaudeRoomEventKind: String, Codable, Sendable, Equatable {
    /// A compact summary of a completed turn.
    case summary
    /// A direct task or handoff intended for another Claude.
    case task
    /// A question one Claude wants another participant to answer.
    case question
    /// A status update that should stay lightweight.
    case status
    /// Free-form demo message.
    case message
}
