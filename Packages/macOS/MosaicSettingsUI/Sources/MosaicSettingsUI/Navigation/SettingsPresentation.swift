import Foundation

/// Controls which settings sections are visible in the settings window.
///
/// Hosts that ship a slim product surface can expose only account settings
/// while the full section catalog remains available for future expansion.
public struct SettingsPresentation: Sendable, Equatable {
    public let visibleSections: [SettingsSectionID]

    public init(visibleSections: [SettingsSectionID]) {
        self.visibleSections = visibleSections
    }

    /// Account sign-in only — no sidebar, no search, no fork settings surface.
    public static let accountOnly = SettingsPresentation(visibleSections: [.account])

    /// Full mosaic settings catalog.
    public static let full = SettingsPresentation(visibleSections: SettingsSectionID.allCases)

    public var showsSidebar: Bool {
        visibleSections.count > 1
    }

    public var windowTitle: String {
        if showsSidebar {
            return String(localized: "settings.title", defaultValue: "Settings")
        }
        return String(localized: "settings.section.account", defaultValue: "Account")
    }

    public var minimumWidth: CGFloat {
        showsSidebar ? 820 : 420
    }

    public var minimumHeight: CGFloat {
        showsSidebar ? 540 : 180
    }

    public func contains(_ section: SettingsSectionID) -> Bool {
        visibleSections.contains(section)
    }
}
