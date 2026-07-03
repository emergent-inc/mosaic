import AppKit
import Foundation
import PostHog

// `@unchecked Sendable` is safe here because mutable analytics state is confined
// to `workQueue`; `activeCheckTimer` is only touched through the main queue.
final class PostHogAnalytics: @unchecked Sendable {
    static let shared = PostHogAnalytics()

    // The PostHog project API key is intentionally embedded in the app (it's a public key).
    private let apiKey = "phc_rRRqoNMdWb5ikbnHwC7EXWKBmYY7VvKJVCLaDqTm97ep"

    // PostHog Cloud US default (matches other cmux properties).
    private let host = "https://us.i.posthog.com"

    private let dailyActiveEvent = "cmux_daily_active"
    private let hourlyActiveEvent = "cmux_hourly_active"
    private let maxCapturedProperties = 64
    private let maxPropertyKeyLength = 64
    private let maxPropertyStringLength = 160
    private let blockedPropertyKeyFragments: Set<String> = [
        "body",
        "command",
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

    private let lastActiveDayUTCKey = "posthog.lastActiveDayUTC"
    private let lastActiveHourUTCKey = "posthog.lastActiveHourUTC"

    private let workQueue: DispatchQueue
    private let workQueueSpecificKey = DispatchSpecificKey<Void>()
    private let utcHourFormatter: DateFormatter
    private let utcDayFormatter: DateFormatter
    private let userDefaults: UserDefaults
    private let now: @Sendable () -> Date
    private let capturePostHog: @Sendable (String, [String: Any]) -> Void
    private let flushPostHog: @Sendable () -> Void
    private let bugAlertClient: MacBugAlertClient?

    private var didStart: Bool
    private var activeCheckTimer: Timer?

    private init(
        workQueue: DispatchQueue = DispatchQueue(label: "com.cmux.posthog.analytics", qos: .utility),
        didStart: Bool = false,
        userDefaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() },
        capturePostHog: @escaping @Sendable (String, [String: Any]) -> Void = { event, properties in
            PostHogSDK.shared.capture(event, properties: properties)
        },
        flushPostHog: @escaping @Sendable () -> Void = { PostHogSDK.shared.flush() },
        bugAlertClient: MacBugAlertClient? = MacBugAlertClient()
    ) {
        self.workQueue = workQueue
        self.didStart = didStart
        self.userDefaults = userDefaults
        self.now = now
        self.capturePostHog = capturePostHog
        self.flushPostHog = flushPostHog
        self.bugAlertClient = bugAlertClient
        utcHourFormatter = Self.makeUTCFormatter("yyyy-MM-dd'T'HH")
        utcDayFormatter = Self.makeUTCFormatter("yyyy-MM-dd")
        workQueue.setSpecific(key: workQueueSpecificKey, value: ())
    }

#if DEBUG
    static func makeForTesting(
        workQueue: DispatchQueue,
        didStart: Bool,
        userDefaults: UserDefaults,
        now: @escaping @Sendable () -> Date,
        capturePostHog: @escaping @Sendable (String, [String: Any]) -> Void,
        flushPostHog: @escaping @Sendable () -> Void,
        bugAlertClient: MacBugAlertClient? = nil
    ) -> PostHogAnalytics {
        PostHogAnalytics(
            workQueue: workQueue,
            didStart: didStart,
            userDefaults: userDefaults,
            now: now,
            capturePostHog: capturePostHog,
            flushPostHog: flushPostHog,
            bugAlertClient: bugAlertClient
        )
    }
#endif

    private var isEnabled: Bool {
        guard TelemetrySettings.enabledForCurrentLaunch else { return false }
#if DEBUG
        // Avoid polluting production analytics while iterating locally.
        return ProcessInfo.processInfo.environment["CMUX_POSTHOG_ENABLE"] == "1"
#else
        return !apiKey.isEmpty && apiKey != "REPLACE_WITH_POSTHOG_PUBLIC_KEY"
#endif
    }

    func startIfNeeded() {
        dispatchAsyncOnWorkQueue { [weak self] in
            self?.startIfNeededOnWorkQueue()
        }
    }

    func trackActive(reason: String) {
        dispatchAsyncOnWorkQueue { [weak self] in
            guard let self else { return }

            let didCaptureDaily = self.trackDailyActiveOnWorkQueue(reason: reason, flush: false)
            let didCaptureHourly = self.trackHourlyActiveOnWorkQueue(reason: reason, flush: false)
            if didCaptureDaily || didCaptureHourly {
                // On app focus we can capture both events; flush once to reduce extra work.
                self.flushPostHog()
            }
        }
    }

    func trackDailyActive(reason: String) {
        dispatchAsyncOnWorkQueue { [weak self] in
            self?.trackDailyActiveOnWorkQueue(reason: reason, flush: true)
        }
    }

    func trackHourlyActive(reason: String) {
        dispatchAsyncOnWorkQueue { [weak self] in
            self?.trackHourlyActiveOnWorkQueue(reason: reason, flush: true)
        }
    }

    func capture(
        _ event: MacAnalyticsEvent,
        properties: [String: Any] = [:],
        flush: Bool = false
    ) {
        dispatchAsyncOnWorkQueue { [weak self] in
            self?.captureOnWorkQueue(
                event: event.rawValue,
                properties: properties,
                flush: flush
            )
        }
    }

    func trackAction(
        actionID: String,
        surface: String,
        entrypoint: String,
        source: String? = nil,
        result: String? = nil,
        properties: [String: Any] = [:]
    ) {
        var eventProperties: [String: Any] = [
            "action_id": actionID,
            "surface": surface,
            "entrypoint": entrypoint,
        ]
        if let source { eventProperties["source"] = source }
        if let result { eventProperties["result"] = result }
        eventProperties.merge(properties) { current, _ in current }
        capture(.actionPerformed, properties: eventProperties)
        sentryBreadcrumb(
            "mac action performed",
            category: "analytics.action",
            data: Self.sentryContext(from: eventProperties)
        )
    }

    func trackError(
        errorKind: String,
        severity: MacAnalyticsSeverity,
        source: String,
        event: MacAnalyticsEvent = .errorCaptured,
        properties: [String: Any] = [:],
        flush: Bool = true
    ) {
        var eventProperties: [String: Any] = [
            "error_kind": errorKind,
            "severity": severity.rawValue,
            "source": source,
        ]
        eventProperties.merge(properties) { current, _ in current }
        capture(event, properties: eventProperties, flush: flush)
        let alertProperties = Self.bugAlertProperties(from: eventProperties)
        Task.detached(priority: .utility) { [bugAlertClient] in
            await bugAlertClient?.send(
                event: event,
                severity: severity,
                source: source,
                errorKind: errorKind,
                properties: alertProperties
            )
        }
    }

    private func startIfNeededOnWorkQueue() {
        guard !didStart else { return }
        guard isEnabled else { return }

        let config = PostHogConfig(apiKey: apiKey, host: host)
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
#if DEBUG
        config.debug = ProcessInfo.processInfo.environment["CMUX_POSTHOG_DEBUG"] == "1"
#endif

        PostHogSDK.shared.setup(config)

        // Tag every event so PostHog can distinguish desktop from web and
        // break events down by released app version/build.
        PostHogSDK.shared.register(Self.superProperties(infoDictionary: Bundle.main.infoDictionary ?? [:]))

        // The SDK automatically generates and persists an anonymous distinct ID.

        didStart = true

        scheduleActiveCheckTimer()
    }

    private func scheduleActiveCheckTimer() {
        // If the app stays in the foreground across midnight, `applicationDidBecomeActive`
        // won't fire again, so a periodic check avoids undercounting those users.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.activeCheckTimer?.invalidate()
            self.activeCheckTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
                guard let self else { return }
                guard NSApp.isActive else { return }
                self.trackActive(reason: "activeTimer")
            }
        }
    }

    @discardableResult
    private func trackDailyActiveOnWorkQueue(reason: String, flush: Bool) -> Bool {
        startIfNeededOnWorkQueue()
        guard didStart else { return false }

        let today = utcDayString(now())
        if userDefaults.string(forKey: lastActiveDayUTCKey) == today {
            return false
        }

        userDefaults.set(today, forKey: lastActiveDayUTCKey)

        let event = dailyActiveEvent

        capturePostHog(event, Self.dailyActiveProperties(
            dayUTC: today,
            reason: reason,
            infoDictionary: Bundle.main.infoDictionary ?? [:]
        ))

        if flush && Self.shouldFlushAfterCapture(event: event) {
            // For active metrics we care more about delivery than batching.
            flushPostHog()
        }

        return true
    }

    @discardableResult
    private func trackHourlyActiveOnWorkQueue(reason: String, flush: Bool) -> Bool {
        startIfNeededOnWorkQueue()
        guard didStart else { return false }

        let hour = utcHourString(now())
        if userDefaults.string(forKey: lastActiveHourUTCKey) == hour {
            return false
        }

        userDefaults.set(hour, forKey: lastActiveHourUTCKey)

        let event = hourlyActiveEvent

        capturePostHog(event, Self.hourlyActiveProperties(
            hourUTC: hour,
            reason: reason,
            infoDictionary: Bundle.main.infoDictionary ?? [:]
        ))

        if flush && Self.shouldFlushAfterCapture(event: event) {
            // Keep hourly freshness and avoid losing a deduped hour on abrupt exits.
            flushPostHog()
        }

        return true
    }

    private func captureOnWorkQueue(
        event: String,
        properties: [String: Any],
        flush: Bool
    ) {
        startIfNeededOnWorkQueue()
        guard didStart else { return }

        let sanitizedProperties = Self.sanitizedProperties(
            properties,
            infoDictionary: Bundle.main.infoDictionary ?? [:],
            maxProperties: maxCapturedProperties,
            maxKeyLength: maxPropertyKeyLength,
            maxStringLength: maxPropertyStringLength,
            blockedKeyFragments: blockedPropertyKeyFragments
        )
        capturePostHog(event, sanitizedProperties)

        if flush || Self.shouldFlushAfterCapture(event: event) {
            flushPostHog()
        }
    }

    private func dispatchAsyncOnWorkQueue(_ block: @escaping @Sendable () -> Void) {
        if DispatchQueue.getSpecific(key: workQueueSpecificKey) != nil {
            block()
            return
        }
        workQueue.async(execute: block)
    }

    private func utcHourString(_ date: Date) -> String {
        utcHourFormatter.string(from: date)
    }

    private func utcDayString(_ date: Date) -> String {
        utcDayFormatter.string(from: date)
    }

    private static func makeUTCFormatter(_ dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = dateFormat
        return formatter
    }

    nonisolated static func superProperties(infoDictionary: [String: Any]) -> [String: Any] {
        var properties: [String: Any] = ["platform": "cmuxterm"]
        properties.merge(versionProperties(infoDictionary: infoDictionary)) { _, new in new }
        return properties
    }
    nonisolated static func dailyActiveProperties(
        dayUTC: String,
        reason: String,
        infoDictionary: [String: Any]
    ) -> [String: Any] {
        var properties: [String: Any] = [
            "day_utc": dayUTC,
            "reason": reason,
        ]
        properties.merge(versionProperties(infoDictionary: infoDictionary)) { _, new in new }
        return properties
    }

    nonisolated static func hourlyActiveProperties(
        hourUTC: String,
        reason: String,
        infoDictionary: [String: Any]
    ) -> [String: Any] {
        var properties: [String: Any] = [
            "hour_utc": hourUTC,
            "reason": reason,
        ]
        properties.merge(versionProperties(infoDictionary: infoDictionary)) { _, new in new }
        return properties
    }

    nonisolated static func shouldFlushAfterCapture(event: String) -> Bool {
        switch event {
        case "cmux_daily_active", "cmux_hourly_active", "mac_error_captured", "mac_error_notification_shown":
            return true
        default:
            return false
        }
    }

    nonisolated static func sanitizedProperties(
        _ input: [String: Any],
        infoDictionary: [String: Any],
        maxProperties: Int = 64,
        maxKeyLength: Int = 64,
        maxStringLength: Int = 160,
        blockedKeyFragments: Set<String> = [
            "body",
            "command",
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
    ) -> [String: Any] {
        var output: [String: Any] = [:]
        var count = 0

        for key in input.keys.sorted() {
            guard count < maxProperties else { break }
            guard isSafePropertyKey(key, maxKeyLength: maxKeyLength, blockedKeyFragments: blockedKeyFragments) else {
                continue
            }
            guard let value = sanitizedPropertyValue(input[key], maxStringLength: maxStringLength) else {
                continue
            }
            output[key] = value
            count += 1
        }

        let versionProperties = versionProperties(infoDictionary: infoDictionary)
        for (key, value) in versionProperties where output[key] == nil {
            output[key] = value
        }
        output["platform"] = output["platform"] ?? "cmuxterm"
#if DEBUG
        output["debug_build"] = true
#else
        output["debug_build"] = false
#endif
        return output
    }

    nonisolated static func sentryContext(from properties: [String: Any]) -> [String: Any] {
        sanitizedProperties(properties, infoDictionary: [:], maxProperties: 24)
    }

    nonisolated static func bugAlertProperties(from properties: [String: Any]) -> [String: String] {
        let sanitized = sanitizedProperties(properties, infoDictionary: [:], maxProperties: 24)
        return stringProperties(from: sanitized)
    }

    nonisolated static func stringProperties(from properties: [String: Any]) -> [String: String] {
        var output: [String: String] = [:]
        for (key, value) in properties {
            switch value {
            case let value as String:
                output[key] = value
            case let value as Bool:
                output[key] = value ? "true" : "false"
            case let value as Int:
                output[key] = String(value)
            case let value as Int64:
                output[key] = String(value)
            case let value as Double:
                output[key] = String(value)
            default:
                continue
            }
        }
        return output
    }

    nonisolated private static func isSafePropertyKey(
        _ key: String,
        maxKeyLength: Int,
        blockedKeyFragments: Set<String>
    ) -> Bool {
        guard !key.isEmpty, key.count <= maxKeyLength else { return false }
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

    nonisolated private static func sanitizedPropertyValue(
        _ value: Any?,
        maxStringLength: Int
    ) -> Any? {
        switch value {
        case let value as String:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if trimmed.count <= maxStringLength {
                return trimmed
            }
            return String(trimmed.prefix(maxStringLength))
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

    nonisolated private static func versionProperties(infoDictionary: [String: Any]) -> [String: Any] {
        var properties: [String: Any] = [:]
        if let value = infoDictionary["CFBundleShortVersionString"] as? String, !value.isEmpty {
            properties["app_version"] = value
        }
        if let value = infoDictionary["CFBundleVersion"] as? String, !value.isEmpty {
            properties["app_build"] = value
        }
        return properties
    }
}
