import Foundation

/// Stable product analytics event names emitted by the macOS app.
struct MacAnalyticsEvent: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let actionPerformed = MacAnalyticsEvent(rawValue: "mac_action_performed")
    static let buttonClicked = MacAnalyticsEvent(rawValue: "mac_button_clicked")
    static let commandPaletteCommandPerformed = MacAnalyticsEvent(rawValue: "mac_command_palette_command_performed")
    static let keyboardShortcutPerformed = MacAnalyticsEvent(rawValue: "mac_keyboard_shortcut_performed")
    static let menuActionPerformed = MacAnalyticsEvent(rawValue: "mac_menu_action_performed")
    static let contextMenuActionPerformed = MacAnalyticsEvent(rawValue: "mac_context_menu_action_performed")
    static let socketCommandPerformed = MacAnalyticsEvent(rawValue: "mac_socket_command_performed")
    static let notificationShown = MacAnalyticsEvent(rawValue: "mac_notification_shown")
    static let errorNotificationShown = MacAnalyticsEvent(rawValue: "mac_error_notification_shown")
    static let modalAlertShown = MacAnalyticsEvent(rawValue: "mac_modal_alert_shown")
    static let errorCaptured = MacAnalyticsEvent(rawValue: "mac_error_captured")
    static let collaborationShareInitiated = MacAnalyticsEvent(rawValue: "mac_collaboration_share_initiated")
    static let collaborationSessionCreated = MacAnalyticsEvent(rawValue: "mac_collaboration_session_created")
    static let collaborationSessionJoined = MacAnalyticsEvent(rawValue: "mac_collaboration_session_joined")
    static let collaborationTerminalShared = MacAnalyticsEvent(rawValue: "mac_collaboration_terminal_shared")
    static let collaborationDocumentShared = MacAnalyticsEvent(rawValue: "mac_collaboration_document_shared")
    static let collaborationInviteCodeCopied = MacAnalyticsEvent(rawValue: "mac_collaboration_invite_code_copied")
    static let collaborationRecipientsUpdated = MacAnalyticsEvent(rawValue: "mac_collaboration_recipients_updated")
    static let collaborationShareStopped = MacAnalyticsEvent(rawValue: "mac_collaboration_share_stopped")
    static let linkingStarted = MacAnalyticsEvent(rawValue: "mac_linking_started")
    static let linkingCompleted = MacAnalyticsEvent(rawValue: "mac_linking_completed")
    static let linkingFailed = MacAnalyticsEvent(rawValue: "mac_linking_failed")
}
