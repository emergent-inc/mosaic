/// The light/dark preference that drives terminal theme selection.
///
/// This is the terminal-domain home of what was `GhosttyConfig.ColorSchemePreference`.
/// It is the value libghostty theme resolution keys off of. mosaic pins the
/// entire app to a fixed dark appearance, so terminal theme resolution is
/// pinned to `.dark` as well — the UI must render identically regardless of
/// the macOS light/dark setting. The `light` case remains only for split
/// `light:.../dark:...` theme-directive parsing and tests.
public enum TerminalColorSchemePreference: Hashable, Sendable {
    case light
    case dark

    /// The fixed preference mosaic renders with everywhere.
    public static let fixed: TerminalColorSchemePreference = .dark

    /// The terminal color-scheme preference used at config-load time. Always
    /// ``fixed`` — mosaic no longer follows the system interface style or a
    /// user appearance mode.
    public static func current() -> TerminalColorSchemePreference {
        fixed
    }
}
