import AppKit
import SwiftUI

/// mosaic renders with one fixed dark appearance so the UI looks identical on
/// every machine regardless of the macOS light/dark setting. Pinning
/// `NSApplication.shared.appearance` makes every semantic AppKit/SwiftUI color,
/// popover, alert, and `effectiveAppearance` check resolve dark.
enum AppearanceSettings {
    /// Applies the fixed application-wide appearance. Called once at launch;
    /// nothing may reset `NSApplication.shared.appearance` afterwards.
    static func applyFixedAppearance() {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    }
}

private struct FixedColorSchemeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .environment(\.colorScheme, .dark)
            .preferredColorScheme(.dark)
    }
}

extension View {
    /// Pins a SwiftUI window tree to mosaic's fixed dark appearance so the
    /// rendered UI never follows the macOS light/dark setting.
    func mosaicFixedColorScheme() -> some View {
        modifier(FixedColorSchemeModifier())
    }
}
