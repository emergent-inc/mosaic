/// A single incoming-session picker row: an opaque session token plus the
/// human-facing base title and an optional disambiguating detail (for example a
/// relative time). Titles are computed by ``CollaborationInboxPicker`` so that
/// invites sharing the same owner/org do not collapse into one visible entry.
public struct CollaborationInboxPickerInput: Equatable, Sendable {
    /// The signed session descriptor the invitee replays to join.
    public let session: String
    /// The primary human-facing title, for example "Shared by Alex in Acme".
    public let baseTitle: String
    /// An optional detail used only when the base title is not unique, for
    /// example a relative time like "5 minutes ago".
    public let detail: String?

    public init(session: String, baseTitle: String, detail: String? = nil) {
        self.session = session
        self.baseTitle = baseTitle
        self.detail = detail
    }
}

/// A resolved picker row with a display title guaranteed to distinguish invites
/// that would otherwise share the same base title.
public struct CollaborationInboxPickerRow: Equatable, Sendable {
    /// The signed session descriptor to attach to the menu item.
    public let session: String
    /// The display title for the menu item.
    public let title: String

    public init(session: String, title: String) {
        self.session = session
        self.title = title
    }
}

/// Builds incoming-session picker rows.
///
/// AppKit's `NSPopUpButton.addItem(withTitle:)` removes any existing item with a
/// duplicate title, so two invites from the same owner+org would collapse into a
/// single visible row even though the badge counts both. Callers append menu
/// items directly, and this helper appends a disambiguating detail (and, if
/// needed, an ordinal) so every invite stays visible and distinguishable.
public enum CollaborationInboxPicker {
    /// The separator between a base title and its disambiguating detail.
    static let detailSeparator = " \u{2014} "

    /// Resolves display titles for the given invites, preserving input order.
    /// - Parameter invites: The invites to render, in display order.
    /// - Returns: One row per invite with a distinguishing title.
    public static func rows(from invites: [CollaborationInboxPickerInput]) -> [CollaborationInboxPickerRow] {
        var baseTitleCounts: [String: Int] = [:]
        for invite in invites {
            baseTitleCounts[invite.baseTitle, default: 0] += 1
        }

        var usedTitles: Set<String> = []
        var rows: [CollaborationInboxPickerRow] = []
        rows.reserveCapacity(invites.count)

        for invite in invites {
            var title = invite.baseTitle
            // Only reach for the detail when the base title is ambiguous, so the
            // common (single invite per teammate) case stays clean.
            if (baseTitleCounts[invite.baseTitle] ?? 0) > 1,
               let detail = invite.detail, !detail.isEmpty {
                title = invite.baseTitle + detailSeparator + detail
            }
            // Guarantee visual distinctness even if the detail collides (for
            // example two invites created in the same second): the menu item's
            // represented session token remains authoritative, but a unique title
            // keeps the list readable.
            if usedTitles.contains(title) {
                var ordinal = 2
                var candidate = title + " (\(ordinal))"
                while usedTitles.contains(candidate) {
                    ordinal += 1
                    candidate = title + " (\(ordinal))"
                }
                title = candidate
            }
            usedTitles.insert(title)
            rows.append(CollaborationInboxPickerRow(session: invite.session, title: title))
        }

        return rows
    }
}
