import Foundation

/// Converts transcript-derived turn text into bounded room summaries.
public struct ClaudeRoomTurnSummaryBuilder: Sendable {
    /// Maximum summary characters.
    public let maxCharacters: Int

    /// Creates a turn summary builder.
    public init(maxCharacters: Int = 1_200) {
        self.maxCharacters = maxCharacters
    }

    /// Builds summary text from a transcript turn.
    public func summary(
        surfaceID: String,
        startSequence: Int?,
        endSequence: Int?,
        text: String
    ) -> String {
        var prefix = "surface \(surfaceID)"
        if let startSequence, let endSequence {
            prefix += " transcript \(startSequence)-\(endSequence)"
        } else if let endSequence {
            prefix += " transcript <=\(endSequence)"
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharacters else {
            return "\(prefix): \(trimmed)"
        }
        return "\(prefix): \(String(trimmed.prefix(maxCharacters)))..."
    }
}
