/// The speaker role for one indexed agent transcript turn.
public enum AgentRoomTranscriptRole: String, Codable, Sendable, Equatable {
    /// A human/user-authored turn.
    case user
    /// An agent-authored turn.
    case assistant
    /// A tool invocation or tool result turn.
    case tool
    /// A system/runtime turn.
    case system
}
