import Foundation
import CryptoKit

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

    func trackSemantic(
        _ event: MacAnalyticsEvent,
        featureArea: ProductAnalyticsFeatureArea,
        entrypoint: ProductAnalyticsEntrypoint,
        result: CollaborationAnalyticsResult,
        surface: String? = nil,
        properties: [String: Any] = [:],
        flush: Bool = false
    ) {
        var eventProperties = ProductAnalyticsPrivacy.sanitizedProperties(properties)
        eventProperties["feature_area"] = featureArea.rawValue
        eventProperties["entrypoint"] = entrypoint.rawValue
        eventProperties["result"] = result.rawValue
        if let surface {
            eventProperties["surface"] = surface
        }
        track(ProductAnalyticsEvent(name: event, properties: eventProperties, flush: flush))
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
        var eventProperties = ProductAnalyticsPrivacy.sanitizedProperties(properties)
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
        var eventProperties = ProductAnalyticsPrivacy.sanitizedProperties(properties)
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
    case sessionLeft
    case sessionDurationRecorded
    case inviteCodeCreated
    case participantJoined
    case participantLeft
    case connectionFailed
    case layoutSnapshotRecorded
    case layoutChanged

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
        case .sessionLeft: return .collaborationSessionLeft
        case .sessionDurationRecorded: return .collaborationSessionDurationRecorded
        case .inviteCodeCreated: return .collaborationInviteCodeCreated
        case .participantJoined: return .collaborationParticipantJoined
        case .participantLeft: return .collaborationParticipantLeft
        case .connectionFailed: return .collaborationConnectionFailed
        case .layoutSnapshotRecorded: return .collaborationLayoutSnapshotRecorded
        case .layoutChanged: return .collaborationLayoutChanged
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
    case system = "system"
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

enum ProductAnalyticsFeatureArea: String {
    case workspace
    case browser
    case terminal
    case collaboration
    case windowing
    case settings
    case feedback
    case web
}

enum ProductAnalyticsEntrypoint: String {
    case appLifecycle = "app_lifecycle"
    case automation
    case button
    case cli
    case commandPalette = "command_palette"
    case contextMenu = "context_menu"
    case menu
    case restore
    case shortcut
    case socket
    case startup
    case system
    case tabBar = "tab_bar"
    case unknown
}

struct ProductAnalyticsPrivacy {
    private init() {}

    private static let blockedKeyFragments: Set<String> = [
        "body",
        "command",
        "content",
        "email",
        "file",
        "path",
        "prompt",
        "secret",
        "subtitle",
        "text",
        "title",
        "token",
        "url",
    ]

    static func sanitizedProperties(_ input: [String: Any], maxProperties: Int = 96) -> [String: Any] {
        var output: [String: Any] = [:]
        var count = 0
        for key in input.keys.sorted() {
            guard count < maxProperties else { break }
            guard isSafeKey(key), let value = sanitizedValue(input[key]) else { continue }
            output[key] = value
            count += 1
        }
        return output
    }

    static func hashIdentifier(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func isSafeKey(_ key: String) -> Bool {
        guard !key.isEmpty, key.count <= 72 else { return false }
        let lowercased = key.lowercased()
        guard !blockedKeyFragments.contains(where: { lowercased.contains($0) }) else {
            return false
        }
        return key.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) ||
                scalar == "_" ||
                scalar == "-" ||
                scalar == "." ||
                scalar == "$"
        }
    }

    private static func sanitizedValue(_ value: Any?) -> Any? {
        switch value {
        case let value as String:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return trimmed.count <= 512 ? trimmed : String(trimmed.prefix(512))
        case let value as Bool:
            return value
        case let value as Int:
            return value
        case let value as Int64:
            return value
        case let value as Double where value.isFinite:
            return value
        case let value as Float where value.isFinite:
            return Double(value)
        default:
            return nil
        }
    }
}
