import Foundation
import Testing
@testable import MosaicTerminalCore

/// mosaic pins the entire app to a fixed dark appearance; terminal color
/// scheme resolution must never follow the macOS interface style or any
/// leftover persisted appearance mode.
@Suite struct TerminalColorSchemePreferenceResolutionTests {
    @Test func fixedPreferenceIsDark() {
        #expect(TerminalColorSchemePreference.fixed == .dark)
    }

    @Test func currentIsAlwaysDark() {
        #expect(TerminalColorSchemePreference.current() == .dark)
    }
}

@Suite struct GhosttySplitThemePreferenceTests {
    @Test func currentColorSchemePreferenceIsPinnedDark() {
        #expect(GhosttyConfig.currentColorSchemePreference() == .dark)
    }

    @Test func splitThemeResolvesDarkSideForPinnedPreference() {
        let resolvedTheme = GhosttyConfig.resolveThemeName(
            from: "light:Catppuccin Latte,dark:Apple System Colors",
            preferredColorScheme: GhosttyConfig.currentColorSchemePreference()
        )
        #expect(resolvedTheme == "Apple System Colors")
    }

    /// Split `light:.../dark:...` directives still resolve per explicit
    /// preference (used by tests and preview tooling), even though production
    /// config always passes the pinned dark preference.
    @Test func splitThemeStillResolvesExplicitLightPreference() {
        let resolvedTheme = GhosttyConfig.resolveThemeName(
            from: "light:Monokai Pro Light,dark:Monokai Pro Machine",
            preferredColorScheme: .light
        )
        #expect(resolvedTheme == "Monokai Pro Light")
    }
}
