/// Pure layout math for the groupchat-style overlapping avatar stack shown on
/// sidebar session rows.
///
/// Given the number of connected participants and a cap on how many avatars a
/// row can comfortably fit, this computes how many avatars to draw and how many
/// remaining participants collapse into a trailing "+N" overflow bubble.
///
/// Rules:
/// - When everyone fits (`participantCount <= maxVisibleAvatars`), every
///   participant gets an avatar and there is no overflow bubble.
/// - When they do not fit, the last slot is reserved for the overflow bubble,
///   so `maxVisibleAvatars - 1` avatars are shown and the rest are counted in
///   the bubble.
public struct CollaborationAvatarStackLayout: Equatable, Sendable {
    /// Number of participant avatars to render.
    public let visibleAvatarCount: Int
    /// Number of participants collapsed into the "+N" overflow bubble; `0` when
    /// no bubble is shown.
    public let overflowCount: Int

    /// Whether a "+N" overflow bubble is rendered.
    public var showsOverflowBubble: Bool { overflowCount > 0 }

    /// Total number of drawn circles, including the overflow bubble.
    public var slotCount: Int { visibleAvatarCount + (showsOverflowBubble ? 1 : 0) }

    /// Computes the layout for a participant list.
    /// - Parameters:
    ///   - participantCount: Number of connected participants (must be `>= 0`).
    ///   - maxVisibleAvatars: Maximum circles a row may show, including the
    ///     overflow bubble. Values `< 1` are treated as `1`.
    public init(participantCount: Int, maxVisibleAvatars: Int) {
        let total = max(0, participantCount)
        let cap = max(1, maxVisibleAvatars)
        if total <= cap {
            self.visibleAvatarCount = total
            self.overflowCount = 0
        } else {
            let shown = cap - 1
            self.visibleAvatarCount = shown
            self.overflowCount = total - shown
        }
    }
}
