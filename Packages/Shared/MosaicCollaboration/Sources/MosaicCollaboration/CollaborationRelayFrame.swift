public import Foundation

/// Client-side relay frame representation used by tests and transports.
public enum CollaborationRelayFrame: Codable, Equatable, Sendable {
    /// A CRDT update for a document.
    case documentUpdate(documentID: String, updateID: String, operations: [TextOperation])
    /// A full CRDT snapshot for a document.
    case documentSnapshot(documentID: String, requestID: String?, operations: [TextOperation], textHash: String)
    /// A request for any peer to send a full CRDT snapshot.
    case documentSnapshotRequest(documentID: String, requestID: String)
    /// Ephemeral peer presence.
    case presence(PresenceState)
    /// A peer disconnected or timed out.
    case peerLeft(peerID: String)
    /// A terminal surface was shared by a peer.
    case terminalOpen(terminalID: String, descriptor: SharedTerminalDescriptor)
    /// Raw PTY output bytes for a shared terminal.
    case terminalOutput(terminalID: String, sequence: UInt64, data: Data)
    /// Raw input bytes for a shared terminal's authoritative PTY.
    case terminalInput(terminalID: String, inputID: String, data: Data)
    /// A terminal share was closed.
    case terminalClose(terminalID: String)
    /// The host's terminal grid size (columns and rows). Peers lock their
    /// mirror grid to this exact size (letterboxing when their pane is larger)
    /// so byte layout, wrapping, and scrollback height are identical to the
    /// host, which keeps collaborator pointer/selection overlays anchored to
    /// the same grid cell across differing window sizes.
    case terminalDimensions(terminalID: String, columns: Int, rows: Int)
    /// A semantic event in a connected-Claude room.
    case agentRoomEvent(ClaudeRoomEvent)
    /// A full connected-Claude room snapshot.
    case agentRoomSnapshot(ClaudeRoomSnapshot)
    /// A request for the current connected-Claude room snapshot.
    case agentRoomSnapshotRequest(roomID: String, requestID: String)
    /// A participant acknowledged room events through a sequence.
    case agentRoomCursorAck(roomID: String, memberID: String, sequence: Int)
}
