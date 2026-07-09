/// Builds active handoff prompts for targeted agent room events.
public struct AgentRoomActiveDispatchPromptBuilder: Sendable {
    /// Maximum number of event text characters to include in a dispatched prompt.
    public let maxTextCharacters: Int

    /// Creates an active dispatch prompt builder.
    ///
    /// The default cap is sized for real working content (schemas, diffs,
    /// multi-paragraph answers): the old 1,200-character cap truncated exactly
    /// the payloads peers were wired together to share.
    ///
    /// - Parameter maxTextCharacters: Maximum number of event text characters to include.
    public init(maxTextCharacters: Int = 4_000) {
        self.maxTextCharacters = maxTextCharacters
    }

    /// Machine-protocol header prefixes that mark a terminal prompt as one this
    /// builder injected into a peer. Used by the publish hook to skip
    /// re-publishing a relayed prompt, which would otherwise loop forever.
    ///
    /// These are intentionally fixed, non-localized markers: they are an
    /// agent-to-agent protocol, not user-facing UI. The CLI publish hook keeps
    /// a mirror of this list (see `isMosaicRoomRelayPrompt` in `CLI/mosaic.swift`).
    public static let relayPromptHeaderPrefixes: [String] = [
        "Shared room message",
        "Shared room handoff",
        "Shared room question",
        "Shared room blocker",
    ]

    /// Returns whether the given text is a prompt this builder relayed into a
    /// peer terminal, so callers can avoid echoing it back into the room.
    public static func isRelayPrompt(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return relayPromptHeaderPrefixes.contains { trimmed.hasPrefix($0) }
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

    /// Returns whether this event should be delivered live into peer terminals
    /// given the room's delivery policy.
    ///
    /// Targeted `handoff`/`question`/`blocker` events always dispatch. In a
    /// broadcast (`semiLive`) room, plain member messages also relay to peers so
    /// a message typed into one agent reaches the others with no manual command.
    public func shouldBroadcast(_ event: ClaudeRoomEvent, policy: ClaudeRoomDeliveryPolicy) -> Bool {
        if shouldDispatch(event) { return true }
        guard policy == .semiLive else { return false }
        switch event.kind {
        case .message:
            return true
        case .handoff, .question, .blocker, .summary, .task, .decision, .finding, .fileChanged, .testResult, .reviewFinding, .status:
            return false
        }
    }

    /// Builds the terminal input text for an active dispatch event.
    ///
    /// - Parameter recipientSurfaceID: The surface receiving this prompt. When
    ///   provided, the reply instruction pins `--from-surface` to it so the
    ///   recipient's answering post is attributed to its own pane instead of
    ///   whatever panel the user happens to have focused (a focused-panel
    ///   fallback that can make the answer self-addressed and undeliverable).
    public func prompt(for event: ClaudeRoomEvent, recipientSurfaceID: String? = nil) -> String? {
        guard shouldDispatch(event), let label = Self.label(for: event.kind) else { return nil }
        return prompt(label: label, event: event, recipientSurfaceID: recipientSurfaceID)
    }

    /// Builds the terminal input text for a broadcastable event (targeted
    /// interrupts, or plain messages in a live room).
    public func broadcastPrompt(
        for event: ClaudeRoomEvent,
        policy: ClaudeRoomDeliveryPolicy,
        recipientSurfaceID: String? = nil
    ) -> String? {
        guard shouldBroadcast(event, policy: policy), let label = Self.label(for: event.kind) else { return nil }
        return prompt(label: label, event: event, recipientSurfaceID: recipientSurfaceID)
    }

    private static func label(for kind: ClaudeRoomEventKind) -> String? {
        switch kind {
        case .handoff:
            return "Shared room handoff"
        case .question:
            return "Shared room question"
        case .blocker:
            return "Shared room blocker"
        case .message:
            return "Shared room message"
        case .summary, .task, .decision, .finding, .fileChanged, .testResult, .reviewFinding, .status:
            return nil
        }
    }

    private func prompt(label: String, event: ClaudeRoomEvent, recipientSurfaceID: String?) -> String {
        let source = event.fromSurfaceID.map { " from surface \($0)" } ?? ""
        return """
        \(label)\(source):
        \(truncated(event.text))

        \(followUpInstruction(for: event, recipientSurfaceID: recipientSurfaceID))
        """
    }

    /// Tells the woken agent how to close the loop. A question must be
    /// answered with a targeted post back to the asker — that post actively
    /// wakes the asker the same way this prompt woke the answerer, so two
    /// wired agents can complete a question/answer round trip with no human
    /// in the middle. This is machine-protocol text, not user-facing UI.
    private func followUpInstruction(for event: ClaudeRoomEvent, recipientSurfaceID: String?) -> String {
        guard event.kind == .question, let asker = event.fromSurfaceID else {
            return "Please respond or continue from this shared-room update."
        }
        let fromOption = recipientSurfaceID.map { " --from-surface \($0)" } ?? ""
        return """
        Answer by posting back to the asking surface (this actively wakes it):
        mosaic agent-room post --kind handoff\(fromOption) --target-surfaces \(asker) -- "<your answer>"
        """
    }

    private func truncated(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxTextCharacters else { return trimmed }
        return String(trimmed.prefix(maxTextCharacters)) + "..."
    }
}
