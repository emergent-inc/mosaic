import Foundation

/// Text value rendered by a sidebar provider row.
public enum MosaicSidebarProviderText: Codable, Equatable, Sendable {
    /// Plain, already-localized text.
    case plain(String)
    /// String catalog backed text.
    case localized(MosaicSidebarProviderLocalizedText)
    /// Relative date text rendered against the current render context.
    case relativeDate(Date, style: MosaicSidebarProviderRelativeDateStyle)

    /// Date carried by relative-date text, if any.
    public var relativeDate: Date? {
        switch self {
        case .plain, .localized:
            return nil
        case .relativeDate(let date, _):
            return date
        }
    }
}
