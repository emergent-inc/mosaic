import AppKit
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV

@Suite(.serialized)
struct PostHogAnalyticsPropertiesTests {
    @Test
    func dailyActivePropertiesIncludeVersionAndBuild() {
        let properties = PostHogAnalytics.dailyActiveProperties(
            dayUTC: "2026-02-21",
            reason: "didBecomeActive",
            infoDictionary: [
                "CFBundleShortVersionString": "0.31.0",
                "CFBundleVersion": "230",
            ]
        )

        #expect(properties["day_utc"] as? String == "2026-02-21")
        #expect(properties["reason"] as? String == "didBecomeActive")
        #expect(properties["app_version"] as? String == "0.31.0")
        #expect(properties["app_build"] as? String == "230")
    }

    @Test
    func superPropertiesIncludePlatformVersionAndBuild() {
        let properties = PostHogAnalytics.superProperties(
            infoDictionary: [
                "CFBundleShortVersionString": "0.31.0",
                "CFBundleVersion": "230",
            ]
        )

        #expect(properties["platform"] as? String == "cmuxterm")
        #expect(properties["app_version"] as? String == "0.31.0")
        #expect(properties["app_build"] as? String == "230")
    }

    @Test
    func hourlyActivePropertiesIncludeVersionAndBuild() {
        let properties = PostHogAnalytics.hourlyActiveProperties(
            hourUTC: "2026-02-21T14",
            reason: "didBecomeActive",
            infoDictionary: [
                "CFBundleShortVersionString": "0.31.0",
                "CFBundleVersion": "230",
            ]
        )

        #expect(properties["hour_utc"] as? String == "2026-02-21T14")
        #expect(properties["reason"] as? String == "didBecomeActive")
        #expect(properties["app_version"] as? String == "0.31.0")
        #expect(properties["app_build"] as? String == "230")
    }

    @Test
    func hourlyPropertiesOmitVersionFieldsWhenUnavailable() {
        let properties = PostHogAnalytics.hourlyActiveProperties(
            hourUTC: "2026-02-21T14",
            reason: "activeTimer",
            infoDictionary: [:]
        )

        #expect(properties["hour_utc"] as? String == "2026-02-21T14")
        #expect(properties["reason"] as? String == "activeTimer")
        #expect(properties["app_version"] == nil)
        #expect(properties["app_build"] == nil)
    }

    @Test
    func propertiesOmitVersionFieldsWhenUnavailable() {
        let superProperties = PostHogAnalytics.superProperties(infoDictionary: [:])
        #expect(superProperties["platform"] as? String == "cmuxterm")
        #expect(superProperties["app_version"] == nil)
        #expect(superProperties["app_build"] == nil)

        let dailyProperties = PostHogAnalytics.dailyActiveProperties(
            dayUTC: "2026-02-21",
            reason: "activeTimer",
            infoDictionary: [:]
        )
        #expect(dailyProperties["day_utc"] as? String == "2026-02-21")
        #expect(dailyProperties["reason"] as? String == "activeTimer")
        #expect(dailyProperties["app_version"] == nil)
        #expect(dailyProperties["app_build"] == nil)
    }

    @Test
    func flushPolicyIncludesDailyAndHourlyActiveEvents() {
        #expect(PostHogAnalytics.shouldFlushAfterCapture(event: "cmux_daily_active"))
        #expect(PostHogAnalytics.shouldFlushAfterCapture(event: "cmux_hourly_active"))
        #expect(PostHogAnalytics.shouldFlushAfterCapture(event: "mac_error_captured"))
        #expect(!PostHogAnalytics.shouldFlushAfterCapture(event: "cmux_other_event"))
    }

    @Test
    func sanitizedPropertiesDropUnsafeKeysAndUnsupportedValues() {
        let properties = PostHogAnalytics.sanitizedProperties(
            [
                "action_id": "palette.newWorkspace",
                "body": "terminal output should never ship",
                "path": "/Users/someone/private",
                "count": 3,
                "enabled": true,
                "nested": ["not": "allowed"],
                "too long key with spaces": "bad",
            ],
            infoDictionary: [
                "CFBundleShortVersionString": "0.31.0",
                "CFBundleVersion": "230",
            ]
        )

        #expect(properties["action_id"] as? String == "palette.newWorkspace")
        #expect(properties["count"] as? Int == 3)
        #expect(properties["enabled"] as? Bool == true)
        #expect(properties["body"] == nil)
        #expect(properties["path"] == nil)
        #expect(properties["nested"] == nil)
        #expect(properties["too long key with spaces"] == nil)
        #expect(properties["platform"] as? String == "cmuxterm")
        #expect(properties["app_version"] as? String == "0.31.0")
        #expect(properties["app_build"] as? String == "230")
    }

    @Test
    func bugAlertPropertiesAreSendableStringsOnly() {
        let properties = PostHogAnalytics.bugAlertProperties(from: [
            "action_id": "settings.clearHistory",
            "count": 2,
            "enabled": false,
            "path": "/private",
        ])

        #expect(properties["action_id"] == "settings.clearHistory")
        #expect(properties["count"] == "2")
        #expect(properties["enabled"] == "false")
        #expect(properties["path"] == nil)
    }

    @Test
    func productAnalyticsBuildsCollaborationFunnelEvents() throws {
        var captured: ProductAnalyticsEvent?
        let analytics = ProductAnalytics { event in
            captured = event
        }

        analytics.trackCollaboration(
            .terminalShared,
            shareKind: .terminal,
            entrypoint: .socketShareSelected,
            result: .completed,
            properties: [
                "peer_count": 2,
                "path": "/Users/private",
            ],
            flush: true
        )

        let event = try #require(captured)
        #expect(event.name.rawValue == "mac_collaboration_terminal_shared")
        #expect(event.flush)
        #expect(event.properties["share_kind"] as? String == "terminal")
        #expect(event.properties["entrypoint"] as? String == "socket_share_selected")
        #expect(event.properties["result"] as? String == "completed")
        #expect(event.properties["peer_count"] as? Int == 2)
        #expect(event.properties["path"] == nil)
    }

    @Test
    func productAnalyticsBuildsLinkingFunnelEvents() throws {
        var captured: ProductAnalyticsEvent?
        let analytics = ProductAnalytics { event in
            captured = event
        }

        analytics.trackLinking(
            .completed,
            linkKind: .ssh,
            entrypoint: .externalURL,
            result: .completed,
            properties: [
                "has_port": true,
                "no_focus": false,
            ],
            flush: true
        )

        let event = try #require(captured)
        #expect(event.name.rawValue == "mac_linking_completed")
        #expect(event.flush)
        #expect(event.properties["link_kind"] as? String == "ssh")
        #expect(event.properties["entrypoint"] as? String == "external_url")
        #expect(event.properties["result"] as? String == "completed")
        #expect(event.properties["has_port"] as? Bool == true)
    }

    @Test
    func productAnalyticsBuildsSemanticEventsWithPrivacyBoundary() throws {
        var captured: ProductAnalyticsEvent?
        let analytics = ProductAnalytics { event in
            captured = event
        }

        analytics.trackSemantic(
            .workspaceLayoutSnapshotRecorded,
            featureArea: .workspace,
            entrypoint: .system,
            result: .completed,
            properties: [
                "workspace_id_hash": ProductAnalyticsPrivacy.hashIdentifier("workspace-1"),
                "pane_count": 3,
                "terminal_pane_count": 2,
                "browser_pane_count": 1,
                "layout_fingerprint": ProductAnalyticsPrivacy.hashIdentifier("layout"),
                "layout_tree": #"{"panes":[{"pane_index":0,"kinds":["terminal"]}]}"#,
                "terminal_text": "do not capture",
                "browser_url": "https://example.com/private",
                "file_path": "/Users/private/project",
            ]
        )

        let event = try #require(captured)
        #expect(event.name.rawValue == "mac_workspace_layout_snapshot_recorded")
        #expect(event.properties["feature_area"] as? String == "workspace")
        #expect(event.properties["entrypoint"] as? String == "system")
        #expect(event.properties["result"] as? String == "completed")
        #expect(event.properties["pane_count"] as? Int == 3)
        #expect(event.properties["layout_tree"] as? String != nil)
        #expect(event.properties["terminal_text"] == nil)
        #expect(event.properties["browser_url"] == nil)
        #expect(event.properties["file_path"] == nil)
    }

    @Test
    func posthogSanitizerAllowsBoundedLayoutTree() {
        let layoutTree = String(repeating: "x", count: 1_000)
        let properties = PostHogAnalytics.sanitizedProperties(
            [
                "layout_tree": layoutTree,
                "layout_fingerprint": "shape",
                "terminal_text": "private terminal contents",
            ],
            infoDictionary: [:]
        )

        #expect((properties["layout_tree"] as? String)?.count == 1_000)
        #expect(properties["layout_fingerprint"] as? String == "shape")
        #expect(properties["terminal_text"] == nil)
    }

    @Test
    func nativeInteractionMetadataUsesSafeStableValues() {
        #expect(MacAnalyticsEvent.uiInteraction.rawValue == "cmux_ui_interaction")
        #expect(NativeInteractionAnalytics.interactionType(for: .leftMouseDown) == "click")
        #expect(NativeInteractionAnalytics.eventTypeName(.scrollWheel) == "scroll_wheel")
        #expect(NativeInteractionAnalytics.scrollDirection(12) == "positive")
        #expect(NativeInteractionAnalytics.scrollDirection(-1) == "negative")
        #expect(NativeInteractionAnalytics.scrollDirection(0) == "none")
        #expect(NativeInteractionAnalytics.sanitizedIdentifier("Sidebar Help/Menu Button!") == "SidebarHelpMenuButton")
    }

    @Test
    func macBugAlertClientSendsSafeSummaryPayloadWhenEnabled() async throws {
        AnalyticsURLProtocolStub.state.reset(statusCode: 200)
        let client = MacBugAlertClient(
            endpoint: try #require(URL(string: "https://cmux.test/api/bug-alerts")),
            session: Self.stubbedSession(),
            sharedSecret: "test-secret",
            isEnabled: { true }
        )

        await client.send(
            event: .errorNotificationShown,
            severity: .error,
            source: "TerminalNotificationStore",
            errorKind: "notification.error",
            properties: [
                "app_version": "0.31.0",
                "has_surface": "true",
            ]
        )

        let request = try #require(AnalyticsURLProtocolStub.state.nextRequest())
        #expect(request.request.url?.absoluteString == "https://cmux.test/api/bug-alerts")
        #expect(request.request.httpMethod == "POST")
        #expect(request.request.value(forHTTPHeaderField: "X-Cmux-Bug-Alerts-Secret") == "test-secret")
        let payload = try Self.jsonObject(from: request.body)
        #expect(payload["event"] as? String == "mac_error_notification_shown")
        #expect(payload["severity"] as? String == "error")
        #expect(payload["source"] as? String == "TerminalNotificationStore")
        #expect(payload["error_kind"] as? String == "notification.error")
        let properties = try #require(payload["properties"] as? [String: Any])
        #expect(properties["app_version"] as? String == "0.31.0")
        #expect(properties["has_surface"] as? String == "true")
    }

    @Test
    func genericCaptureScrubsAndSendsMacEventsDirectlyToPostHog() async throws {
        let suiteName = "cmux.posthog.analytics.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let capturedQueue = DispatchQueue(label: "com.cmux.tests.posthog.generic.capture")
        var capturedEvents: [(event: String, properties: [String: Any])] = []
        let eventCaptured = DispatchSemaphore(value: 0)
        let analytics = PostHogAnalytics.makeForTesting(
            workQueue: DispatchQueue(label: "com.cmux.tests.posthog.generic.analytics"),
            didStart: true,
            userDefaults: defaults,
            now: { Date() },
            capturePostHog: { event, properties in
                capturedQueue.sync {
                    capturedEvents.append((event: event, properties: properties))
                    eventCaptured.signal()
                }
            },
            flushPostHog: {}
        )

        analytics.capture(
            .buttonClicked,
            properties: [
                "action_id": "menu.open_settings",
                "surface": "main_menu",
                "path": "/Users/private",
                "body": "private text",
                "count": 4,
            ]
        )

        #expect(eventCaptured.wait(timeout: .now() + .seconds(1)) == .success)
        let captured = try #require(capturedQueue.sync { capturedEvents.first })
        #expect(captured.event == "mac_button_clicked")
        #expect(captured.properties["action_id"] as? String == "menu.open_settings")
        #expect(captured.properties["surface"] as? String == "main_menu")
        #expect(captured.properties["count"] as? Int == 4)
        #expect(captured.properties["path"] == nil)
        #expect(captured.properties["body"] == nil)
        #expect(captured.properties["platform"] as? String == "cmuxterm")
    }

    @Test
    func activeEventCaptureFlushesBeforeShutdown() throws {
        let suiteName = "cmux.posthog.analytics.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let fixedDate = try #require(Calendar(identifier: .iso8601).date(from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 2,
            day: 21,
            hour: 14
        )))
        let capturedQueue = DispatchQueue(label: "com.cmux.tests.posthog.capture")
        var capturedEvents: [(event: String, properties: [String: Any])] = []
        let eventsCaptured = DispatchSemaphore(value: 0)
        let flushCalled = DispatchSemaphore(value: 0)
        let analytics = PostHogAnalytics.makeForTesting(
            workQueue: DispatchQueue(label: "com.cmux.tests.posthog.analytics"),
            didStart: true,
            userDefaults: defaults,
            now: { fixedDate },
            capturePostHog: { event, properties in
                capturedQueue.sync {
                    capturedEvents.append((event: event, properties: properties))
                    if capturedEvents.count == 2 {
                        eventsCaptured.signal()
                    }
                }
            },
            flushPostHog: {
                flushCalled.signal()
            }
        )

        analytics.trackActive(reason: "didBecomeActive")
        #expect(eventsCaptured.wait(timeout: .now() + .seconds(1)) == .success)
        #expect(flushCalled.wait(timeout: .now() + .seconds(1)) == .success)
        let events = capturedQueue.sync { capturedEvents }
        #expect(events.map(\.event) == ["cmux_daily_active", "cmux_hourly_active"])
        let dailyEvent = try #require(events.first)
        let hourlyEvent = try #require(events.dropFirst().first)
        #expect(dailyEvent.properties["day_utc"] as? String == "2026-02-21")
        #expect(dailyEvent.properties["reason"] as? String == "didBecomeActive")
        #expect(hourlyEvent.properties["hour_utc"] as? String == "2026-02-21T14")
        #expect(hourlyEvent.properties["reason"] as? String == "didBecomeActive")
    }

    @Test
    func activeFlushDoesNotBlockMainThreadWhenSDKFlushBlocks() throws {
        let suiteName = "cmux.posthog.analytics.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let fixedDate = try #require(Calendar(identifier: .iso8601).date(from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 2,
            day: 21,
            hour: 14
        )))
        let flushStarted = DispatchSemaphore(value: 0)
        let flushCanReturn = DispatchSemaphore(value: 0)
        let flushReturned = DispatchSemaphore(value: 0)
        let flushRanOnMainThread = DispatchSemaphore(value: 0)
        let flushRanOffMainThread = DispatchSemaphore(value: 0)
        let callerReturned = DispatchSemaphore(value: 0)
        let analytics = PostHogAnalytics.makeForTesting(
            workQueue: DispatchQueue(label: "com.cmux.tests.posthog.analytics"),
            didStart: true,
            userDefaults: defaults,
            now: { fixedDate },
            capturePostHog: { _, _ in },
            flushPostHog: {
                if Thread.isMainThread {
                    flushRanOnMainThread.signal()
                } else {
                    flushRanOffMainThread.signal()
                }
                flushStarted.signal()
                _ = flushCanReturn.wait(timeout: .now() + .seconds(5))
                flushReturned.signal()
            }
        )

        let trackActiveOnMainThread = {
            analytics.trackActive(reason: "didBecomeActive")
            callerReturned.signal()
        }

        if Thread.isMainThread {
            trackActiveOnMainThread()
        } else {
            DispatchQueue.main.async(execute: trackActiveOnMainThread)
        }

        #expect(callerReturned.wait(timeout: .now() + .seconds(1)) == .success)
        #expect(flushStarted.wait(timeout: .now() + .seconds(1)) == .success)
        #expect(flushRanOffMainThread.wait(timeout: .now() + .seconds(1)) == .success)
        #expect(flushRanOnMainThread.wait(timeout: .now() + .milliseconds(50)) == .timedOut)
        #expect(flushReturned.wait(timeout: .now() + .milliseconds(50)) == .timedOut)
        flushCanReturn.signal()
        #expect(flushReturned.wait(timeout: .now() + .seconds(1)) == .success)
    }

    private static func stubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnalyticsURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private final class AnalyticsURLProtocolStubState: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.cmux.tests.analytics.urlprotocol")
    private var statusCode = 200
    private var capturedRequests: [(request: URLRequest, body: Data)] = []
    private var semaphore = DispatchSemaphore(value: 0)

    func reset(statusCode: Int) {
        queue.sync {
            self.statusCode = statusCode
            capturedRequests.removeAll()
            semaphore = DispatchSemaphore(value: 0)
        }
    }

    func record(request: URLRequest, body: Data) {
        queue.sync {
            capturedRequests.append((request: request, body: body))
            semaphore.signal()
        }
    }

    func nextRequest(timeout: DispatchTime = .now() + .seconds(1)) -> (request: URLRequest, body: Data)? {
        guard semaphore.wait(timeout: timeout) == .success else { return nil }
        return queue.sync {
            guard !capturedRequests.isEmpty else { return nil }
            return capturedRequests.removeFirst()
        }
    }

    func currentStatusCode() -> Int {
        queue.sync { statusCode }
    }
}

private final class AnalyticsURLProtocolStub: URLProtocol {
    static let state = AnalyticsURLProtocolStubState()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let body = Self.bodyData(from: request)
        Self.state.record(request: request, body: body)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://cmux.test")!,
            statusCode: Self.state.currentStatusCode(),
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"ok":true}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func bodyData(from request: URLRequest) -> Data {
        if let httpBody = request.httpBody {
            return httpBody
        }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
#endif
