/// Controls when a room event should be injected into connected Claude sessions.
public enum ClaudeRoomDeliveryPolicy: String, Codable, Sendable, Equatable {
    /// Keep events in the room until the user explicitly sends one.
    case manual
    /// Demo mode: send compact event text to connected targets immediately.
    case semiLive = "semi_live"
}
