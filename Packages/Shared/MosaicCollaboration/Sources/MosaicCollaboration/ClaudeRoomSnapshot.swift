/// Current state of one Claude room.
public struct ClaudeRoomSnapshot: Identifiable, Codable, Sendable, Equatable {
    /// Room identifier.
    public let id: String
    /// Human-readable room title.
    public var title: String?
    /// Delivery policy used by demo clients.
    public var deliveryPolicy: ClaudeRoomDeliveryPolicy
    /// Connected members.
    public var members: [ClaudeRoomMember]
    /// Recent semantic events.
    public var events: [ClaudeRoomEvent]
    /// Last assigned event sequence.
    public var lastSequence: Int

    /// Creates a room snapshot.
    public init(
        id: String,
        title: String? = nil,
        deliveryPolicy: ClaudeRoomDeliveryPolicy = .manual,
        members: [ClaudeRoomMember] = [],
        events: [ClaudeRoomEvent] = [],
        lastSequence: Int = 0
    ) {
        self.id = id
        self.title = title
        self.deliveryPolicy = deliveryPolicy
        self.members = members
        self.events = events
        self.lastSequence = lastSequence
    }
}
