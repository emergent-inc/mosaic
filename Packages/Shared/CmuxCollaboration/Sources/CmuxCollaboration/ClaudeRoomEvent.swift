public import Foundation

/// One semantic message in a shared Claude room.
public struct ClaudeRoomEvent: Identifiable, Codable, Sendable, Equatable {
    /// Stable event identifier.
    public let id: String
    /// Monotonic sequence within the room.
    public let sequence: Int
    /// Room that owns the event.
    public let roomID: String
    /// Event type.
    public let kind: ClaudeRoomEventKind
    /// Sender member identifier, when known.
    public let fromMemberID: String?
    /// Sender surface identifier, when known.
    public let fromSurfaceID: String?
    /// Target member identifiers. Empty means room-visible, not direct.
    public let targetMemberIDs: [String]
    /// Target surface identifiers. Empty means room-visible, not direct.
    public let targetSurfaceIDs: [String]
    /// Compact text intended for room history and optional injection.
    public let text: String
    /// Event creation time.
    public let createdAt: Date

    /// Creates a room event.
    public init(
        id: String = UUID().uuidString,
        sequence: Int,
        roomID: String,
        kind: ClaudeRoomEventKind,
        fromMemberID: String? = nil,
        fromSurfaceID: String? = nil,
        targetMemberIDs: [String] = [],
        targetSurfaceIDs: [String] = [],
        text: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sequence = sequence
        self.roomID = roomID
        self.kind = kind
        self.fromMemberID = fromMemberID
        self.fromSurfaceID = fromSurfaceID
        self.targetMemberIDs = targetMemberIDs
        self.targetSurfaceIDs = targetSurfaceIDs
        self.text = text
        self.createdAt = createdAt
    }
}
