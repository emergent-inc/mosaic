public import Foundation

/// One Claude-capable terminal surface connected to a shared room.
/// How a room member participates in shared context.
public enum ClaudeRoomMemberRole: String, Codable, Sendable {
    /// A coding-agent session: publishes turns to the room, consumes peer
    /// context through its hooks, and can be woken by targeted events.
    case agent
    /// A plain terminal wired in as a read-only data source. It never
    /// publishes or consumes, is never woken (typing a prompt into a shell
    /// would execute it), and peers read its contents on demand.
    case dataSource
}

public struct ClaudeRoomMember: Identifiable, Codable, Sendable, Equatable {
    /// Stable membership identifier, unique within the room.
    public let id: String
    /// mosaic surface identifier on the owning app instance.
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
    /// How this member participates. Optional so rooms persisted before the
    /// role existed still decode; `nil` means `.agent` (see ``resolvedRole``).
    public var role: ClaudeRoomMemberRole?

    /// The effective role, defaulting legacy members to `.agent`.
    public var resolvedRole: ClaudeRoomMemberRole { role ?? .agent }

    /// Creates a room member.
    public init(
        id: String = UUID().uuidString,
        surfaceID: String,
        agentSessionID: String? = nil,
        peerID: String,
        displayName: String? = nil,
        transcriptCursor: Int? = nil,
        acknowledgedEventSequence: Int? = nil,
        role: ClaudeRoomMemberRole? = nil
    ) {
        self.id = id
        self.surfaceID = surfaceID
        self.agentSessionID = agentSessionID
        self.peerID = peerID
        self.displayName = displayName
        self.transcriptCursor = transcriptCursor
        self.acknowledgedEventSequence = acknowledgedEventSequence
        self.role = role
    }
}
