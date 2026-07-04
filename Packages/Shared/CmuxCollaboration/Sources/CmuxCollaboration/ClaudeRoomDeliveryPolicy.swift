/// Controls when a room event should be injected into connected Claude sessions.
public enum ClaudeRoomDeliveryPolicy: String, Codable, Sendable, Equatable {
    /// Keep events in the room until the user explicitly sends one.
    case manual
    /// Broadcast: relay member messages live into every peer terminal as they
    /// are posted. Wired rooms use this so a message typed into one agent flows
    /// to the others without any manual command.
    case semiLive = "semi_live"
}
