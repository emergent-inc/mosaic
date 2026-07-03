import Foundation

/// User-selected language for the cmux UI. Raw values match the
/// `AppleLanguages` BCP-47 identifiers cmux uses on disk.
public enum AppLanguage: String, CaseIterable, Sendable, SettingCodable {
    case system, en
}
