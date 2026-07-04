/// Builds bounded text digests for a room.
public struct ClaudeRoomDigestBuilder: Sendable {
    /// Maximum number of events included in a digest.
    public let maxEvents: Int
    /// Maximum character count for each event line.
    public let maxEventCharacters: Int

    /// Creates a digest builder.
    public init(maxEvents: Int = 8, maxEventCharacters: Int = 800) {
        self.maxEvents = maxEvents
        self.maxEventCharacters = maxEventCharacters
    }

    /// Builds a human-readable digest from recent room events.
    public func digest(for room: ClaudeRoomSnapshot, since sequence: Int? = nil) -> String {
        let lowerBound = sequence ?? 0
        let candidates = room.events
            .filter { $0.sequence > lowerBound }
            .suffix(maxEvents)
        guard !candidates.isEmpty else { return "" }
        return candidates.map { event in
            let prefix = "[\(event.sequence)] \(event.kind.rawValue): "
            return prefix + truncated(event.text, limit: maxEventCharacters)
        }.joined(separator: "\n")
    }

    private func truncated(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "..."
    }
}
