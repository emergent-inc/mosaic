import Foundation

// The property bag is immediately handed to PostHogAnalytics, which performs
// scalar-only sanitization on its own serial queue before any network egress.
struct ProductAnalyticsEvent: @unchecked Sendable {
    let name: MacAnalyticsEvent
    let properties: [String: Any]
    let flush: Bool
}

struct ProductAnalytics: @unchecked Sendable {
    static let shared = ProductAnalytics()

    private let recordEvent: @Sendable (ProductAnalyticsEvent) -> Void

    init(recordEvent: @escaping @Sendable (ProductAnalyticsEvent) -> Void = { event in
        PostHogAnalytics.shared.capture(event.name, properties: event.properties, flush: event.flush)
    }) {
        self.recordEvent = recordEvent
    }

    func track(_ event: ProductAnalyticsEvent) {
        recordEvent(event)
    }

    func trackAction(
        actionID: String,
        surface: String,
        entrypoint: String,
        source: String? = nil,
        result: String? = nil,
        properties: [String: Any] = [:]
    ) {
        PostHogAnalytics.shared.trackAction(
            actionID: actionID,
            surface: surface,
            entrypoint: entrypoint,
            source: source,
            result: result,
            properties: properties
        )
    }

    func trackCollaboration(
        _ event: CollaborationAnalyticsEvent,
        shareKind: CollaborationAnalyticsShareKind? = nil,
        entrypoint: CollaborationAnalyticsEntrypoint,
        result: CollaborationAnalyticsResult,
        properties: [String: Any] = [:],
        flush: Bool = false
    ) {
        var eventProperties = properties
        eventProperties["entrypoint"] = entrypoint.rawValue
        eventProperties["result"] = result.rawValue
        if let shareKind {
            eventProperties["share_kind"] = shareKind.rawValue
        }
        track(ProductAnalyticsEvent(name: event.macEvent, properties: eventProperties, flush: flush))
    }

    func trackFeedback(
        actionID: FeedbackAnalyticsActionID,
        entrypoint: CollaborationAnalyticsEntrypoint,
        result: CollaborationAnalyticsResult,
        properties: [String: Any] = [:]
    ) {
        trackAction(
            actionID: actionID.rawValue,
            surface: "feedback_composer",
            entrypoint: entrypoint.rawValue,
            result: result.rawValue,
            properties: properties
        )
    }

    func trackLinking(
        _ event: LinkingAnalyticsEvent,
        linkKind: LinkingAnalyticsKind,
        entrypoint: LinkingAnalyticsEntrypoint,
        result: CollaborationAnalyticsResult,
        properties: [String: Any] = [:],
        flush: Bool = false
    ) {
        var eventProperties = properties
        eventProperties["link_kind"] = linkKind.rawValue
        eventProperties["entrypoint"] = entrypoint.rawValue
        eventProperties["result"] = result.rawValue
        track(ProductAnalyticsEvent(name: event.macEvent, properties: eventProperties, flush: flush))
    }
}

enum CollaborationAnalyticsEvent {
    case shareInitiated
    case sessionCreated
    case sessionJoined
    case terminalShared
    case documentShared
    case inviteCodeCopied
    case recipientsUpdated
    case shareStopped

    var macEvent: MacAnalyticsEvent {
        switch self {
        case .shareInitiated: return .collaborationShareInitiated
        case .sessionCreated: return .collaborationSessionCreated
        case .sessionJoined: return .collaborationSessionJoined
        case .terminalShared: return .collaborationTerminalShared
        case .documentShared: return .collaborationDocumentShared
        case .inviteCodeCopied: return .collaborationInviteCodeCopied
        case .recipientsUpdated: return .collaborationRecipientsUpdated
        case .shareStopped: return .collaborationShareStopped
        }
    }
}

enum CollaborationAnalyticsShareKind: String {
    case terminal
    case document
}

enum CollaborationAnalyticsEntrypoint: String {
    case terminalHeaderButton = "terminal_header_button"
    case documentHeaderButton = "document_header_button"
    case recipientPopover = "recipient_popover"
    case socketShareSelected = "socket_share_selected"
    case socketSession = "socket_session"
    case startDialogCreate = "start_dialog_create"
    case startDialogJoin = "start_dialog_join"
    case createdSessionDialog = "created_session_dialog"
    case helpMenu = "help_menu"
    case socket = "socket"
}

enum CollaborationAnalyticsResult: String {
    case started
    case completed
    case cancelled
    case failed
}

enum FeedbackAnalyticsActionID: String {
    case open = "feedback.open"
    case submit = "feedback.submit"
}

enum LinkingAnalyticsEvent {
    case started
    case completed
    case failed

    var macEvent: MacAnalyticsEvent {
        switch self {
        case .started: return .linkingStarted
        case .completed: return .linkingCompleted
        case .failed: return .linkingFailed
        }
    }
}

enum LinkingAnalyticsKind: String {
    case ssh
    case prompt
    case rules
}

enum LinkingAnalyticsEntrypoint: String {
    case externalURL = "external_url"
}
