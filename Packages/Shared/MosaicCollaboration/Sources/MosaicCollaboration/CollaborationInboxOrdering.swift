import Foundation

/// A single incoming-session entry to be ordered by recency: an opaque session
/// token plus the invite's ISO-8601 `createdAt` timestamp string.
public struct CollaborationInboxOrderingInput: Equatable, Sendable {
    /// The signed session descriptor the invitee replays to join.
    public let session: String
    /// The invite's creation timestamp as an ISO-8601 string, as delivered by
    /// the backend. May be unparseable, in which case it sorts last.
    public let createdAt: String

    public init(session: String, createdAt: String) {
        self.session = session
        self.createdAt = createdAt
    }
}

/// Orders incoming-session invites newest-first by their `createdAt` timestamp.
///
/// The backend does not guarantee a recency order, so the client sorts locally
/// to keep the picker's default selection and the auto-surfaced alert pinned to
/// the most recently shared session. The sort is stable: invites with equal
/// timestamps, and invites whose `createdAt` cannot be parsed, preserve their
/// original relative order. Unparseable timestamps sort after all parseable
/// ones.
public enum CollaborationInboxOrdering {
    /// Returns `inputs` ordered newest-first by parsed `createdAt`.
    /// - Parameter inputs: The invites to order, in their original order.
    /// - Returns: The invites sorted newest-first, stable for ties and
    ///   unparseable timestamps.
    public static func orderNewestFirst(
        _ inputs: [CollaborationInboxOrderingInput]
    ) -> [CollaborationInboxOrderingInput] {
        // `ISO8601DateFormatter` is not `Sendable`, so it cannot live in a static
        // property under strict concurrency. Invite lists are tiny, so building
        // the two formatters once per call is inexpensive.
        let plainFormatter = ISO8601DateFormatter()
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func parseDate(_ value: String) -> Date? {
            plainFormatter.date(from: value) ?? fractionalFormatter.date(from: value)
        }

        // Decorate with the original index so the sort can stay stable without
        // relying on `sort(by:)`'s (unspecified) stability guarantees.
        let decorated = inputs.enumerated().map { index, input in
            (index: index, date: parseDate(input.createdAt), input: input)
        }
        let sorted = decorated.sorted { lhs, rhs in
            switch (lhs.date, rhs.date) {
            case let (l?, r?):
                if l != r { return l > r }
                return lhs.index < rhs.index
            case (_?, nil):
                // Parseable timestamps come before unparseable ones.
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.index < rhs.index
            }
        }
        return sorted.map(\.input)
    }
}
