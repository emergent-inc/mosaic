import AppKit

/// Records coarse analytics for modal alert presentation without sending alert text.
@MainActor
struct CmuxModalAlertAnalytics {
    static func track(
        _ alert: NSAlert,
        presentation: CmuxModalAlertPresentation
    ) {
        let presentationValue: String
        switch presentation {
        case .sheet(_):
            presentationValue = "sheet"
        case .appModal(let hostWindowHadAttachedSheet):
            presentationValue = hostWindowHadAttachedSheet ? "app_modal_attached_sheet" : "app_modal_no_host"
        }
        let styleValue: String
        switch alert.alertStyle {
        case .warning:
            styleValue = "warning"
        case .informational:
            styleValue = "informational"
        case .critical:
            styleValue = "critical"
        @unknown default:
            styleValue = "unknown"
        }
        PostHogAnalytics.shared.capture(
            .modalAlertShown,
            properties: [
                "surface": "modal_alert",
                "entrypoint": "runCmuxModalAlert",
                "presentation": presentationValue,
                "alert_style": styleValue,
            ]
        )
        guard alert.alertStyle == .critical else { return }
        PostHogAnalytics.shared.trackError(
            errorKind: "modal_alert.critical",
            severity: .error,
            source: "runCmuxModalAlert",
            properties: [
                "presentation": presentationValue,
                "alert_style": styleValue,
            ]
        )
    }
}
