/// Builds active handoff prompts for targeted agent room events.
public struct AgentRoomActiveDispatchPromptBuilder: Sendable {
    /// Maximum number of event text characters to include in a dispatched prompt.
    public let maxTextCharacters: Int

    /// Creates an active dispatch prompt builder.
    ///
    /// - Parameter maxTextCharacters: Maximum number of event text characters to include.
    public init(maxTextCharacters: Int = 1_200) {
        self.maxTextCharacters = maxTextCharacters
    }

    /// Returns whether this event kind should actively prompt targeted agents.
    public func shouldDispatch(_ event: ClaudeRoomEvent) -> Bool {
        guard !event.targetSurfaceIDs.isEmpty || !event.targetMemberIDs.isEmpty else {
            return false
        }
        switch event.kind {
        case .handoff, .question, .blocker:
            return true
        case .summary, .task, .decision, .finding, .fileChanged, .testResult, .reviewFinding, .status, .message:
            return false
        }
    }

    /// Builds the terminal input text for an active dispatch event.
    public func prompt(for event: ClaudeRoomEvent) -> String? {
        guard shouldDispatch(event) else { return nil }
        let label: String
        switch event.kind {
        case .handoff:
            label = "Shared room handoff"
        case .question:
            label = "Shared room question"
        case .blocker:
            label = "Shared room blocker"
        case .summary, .task, .decision, .finding, .fileChanged, .testResult, .reviewFinding, .status, .message:
            return nil
        }
        let source = event.fromSurfaceID.map { " from surface \($0)" } ?? ""
        return """
        \(label)\(source):
        \(truncated(event.text))

        Please respond or continue from this shared-room update.
        """
    }

    private func truncated(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxTextCharacters else { return trimmed }
        return String(trimmed.prefix(maxTextCharacters)) + "..."
    }
}
