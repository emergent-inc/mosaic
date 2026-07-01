public import Foundation

/// One Claude-capable terminal surface connected to a shared room.
public struct ClaudeRoomMember: Identifiable, Codable, Sendable, Equatable {
    /// Stable membership identifier, unique within the room.
    public let id: String
    /// cmux surface identifier on the owning app instance.
    public let surfaceID: String
    /// Optional Claude session identifier from hooks.
    public var agentSessionID: String?
    /// Collaboration peer that owns the surface.
    public var peerID: String
    /// Optional display label for UI and CLI output.
    public var displayName: String?
    /// Last transcript sequence consumed for this member.
    public var transcriptCursor: Int?
    /// Last room event acknowledged by this member.
    public var acknowledgedEventSequence: Int?

    /// Creates a room member.
    public init(
        id: String = UUID().uuidString,
        surfaceID: String,
        agentSessionID: String? = nil,
        peerID: String,
        displayName: String? = nil,
        transcriptCursor: Int? = nil,
        acknowledgedEventSequence: Int? = nil
    ) {
        self.id = id
        self.surfaceID = surfaceID
        self.agentSessionID = agentSessionID
        self.peerID = peerID
        self.displayName = displayName
        self.transcriptCursor = transcriptCursor
        self.acknowledgedEventSequence = acknowledgedEventSequence
    }
}
