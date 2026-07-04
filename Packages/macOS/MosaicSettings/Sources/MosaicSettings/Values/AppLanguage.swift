import Foundation

/// User-selected language for the mosaic UI. Raw values match the
/// `AppleLanguages` BCP-47 identifiers mosaic uses on disk.
public enum AppLanguage: String, CaseIterable, Sendable, SettingCodable {
    case system, en
}
