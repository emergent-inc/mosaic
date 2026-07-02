import Foundation

/// Sends scrubbed macOS product analytics events to the native analytics proxy.
actor MacAnalyticsProxyClient {
    private let endpoint: URL
    private let session: URLSession
    private let isEnabled: @Sendable () -> Bool

    init(
        endpoint: URL = MacAnalyticsProxyClient.defaultEndpoint(),
        session: URLSession = .shared,
        isEnabled: @escaping @Sendable () -> Bool = {
            guard TelemetrySettings.enabledForCurrentLaunch else { return false }
            #if DEBUG
            return ProcessInfo.processInfo.environment["CMUX_POSTHOG_ENABLE"] == "1"
            #else
            return true
            #endif
        }
    ) {
        self.endpoint = endpoint
        self.session = session
        self.isEnabled = isEnabled
    }

    func send(event: String, properties: [String: String]) async {
        guard isEnabled() else { return }
        let payload: [String: Any] = [
            "batch": [
                [
                    "event": event,
                    "properties": properties,
                ],
            ],
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 2
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            _ = try await session.data(for: request)
        } catch {
            return
        }
    }

    private static func defaultEndpoint() -> URL {
        if let override = ProcessInfo.processInfo.environment["CMUX_ANALYTICS_API_URL"],
           let url = URL(string: override.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return url
        }
        return URL(string: "https://cmux.com/api/analytics/events")!
    }
}
