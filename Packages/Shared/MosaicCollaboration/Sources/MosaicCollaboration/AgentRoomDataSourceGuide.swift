/// Builds the text that tells wired agents about plain terminals connected to
/// a room as read-only data sources: the standing digest section and the
/// ledger notices posted when a data source is wired or unwired.
///
/// Like `AgentRoomActiveDispatchPromptBuilder`, this is agent-to-agent
/// protocol text, deliberately not localized (see its
/// `relayPromptHeaderPrefixes` note).
public enum AgentRoomDataSourceGuide {
    /// One wired data source as advertised to agents.
    public struct Entry: Equatable, Sendable {
        /// The data source's mosaic surface identifier.
        public let surfaceID: String
        /// Optional pane display title.
        public let displayName: String?

        /// Creates a data source entry.
        public init(surfaceID: String, displayName: String? = nil) {
            self.surfaceID = surfaceID
            self.displayName = displayName
        }

        /// The label agents see for this data source.
        public var label: String {
            let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let trimmed, !trimmed.isEmpty else { return "surface \(surfaceID)" }
            return trimmed
        }
    }

    /// The shell command an agent runs to read a data source terminal's
    /// recent output (visible screen plus scrollback tail).
    public static func readCommand(surfaceID: String) -> String {
        "mosaic read-screen --surface \(surfaceID) --scrollback --lines 200"
    }

    /// Data-source members of a room, excluding the recipient's own surface.
    public static func entries(
        in room: ClaudeRoomSnapshot,
        excludingSurfaceID: String? = nil
    ) -> [Entry] {
        room.members
            .filter { $0.resolvedRole == .dataSource && $0.surfaceID != excludingSurfaceID }
            .map { Entry(surfaceID: $0.surfaceID, displayName: $0.displayName) }
    }

    /// Standing digest section listing every wired data source with its read
    /// command, so agents learn about sources mid-session (not just from the
    /// one-time connect notice). Empty when the room has no data sources.
    public static func standingInstructions(for entries: [Entry]) -> String {
        guard !entries.isEmpty else { return "" }
        let lines = entries.map { entry in
            "- \(entry.label): \(readCommand(surfaceID: entry.surfaceID))"
        }
        return """
        Linked data-source terminals (read-only): the panes below contribute content to this shared agent context. They run no agent, cannot receive posts, and never answer questions. When their contents are relevant, read one on demand with the shell command shown (adjust --lines as needed):
        \(lines.joined(separator: "\n"))
        """
    }

    /// Ledger notice posted when a data source is wired into a room.
    public static func connectedEventText(entry: Entry) -> String {
        """
        A read-only data-source terminal was linked to this shared agent context: \(entry.label). It runs no agent; read its recent output on demand with:
        \(readCommand(surfaceID: entry.surfaceID))
        """
    }

    /// Ledger notice posted when a data source is unwired from a room.
    public static func disconnectedEventText(entry: Entry) -> String {
        "The data-source terminal \(entry.label) (surface \(entry.surfaceID)) was unlinked from this shared agent context and can no longer be read."
    }
}
