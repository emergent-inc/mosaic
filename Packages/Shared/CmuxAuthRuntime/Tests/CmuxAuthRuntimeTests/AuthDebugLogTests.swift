import Foundation
import Testing
@testable import CmuxAuthRuntime

@Suite struct AuthDebugLogTests {
    @Test func debugLogPathsIncludeTaggedDebugLogWhenConfigured() {
        #if DEBUG && os(macOS)
        let paths = AuthDebugLog.debugLogPaths(environment: [
            "CMUX_DEBUG_LOG": "/tmp/cmux-debug-safari.log",
        ])

        #expect(paths == ["/tmp/cmux-auth-debug.log", "/tmp/cmux-debug-safari.log"])
        #endif
    }

    @Test func redactionCoversCallbackTokenQueryValues() {
        let redacted = AuthDebugLog.redacted(
            "auth.callback.complete url=mosaic-dev://auth-callback?mosaic_refresh=refresh-secret&mosaic_access=access-secret&mosaic_auth_state=state-secret"
        )

        #expect(redacted.contains("refresh-secret") == false)
        #expect(redacted.contains("access-secret") == false)
        #expect(redacted.contains("state-secret") == false)
        #expect(redacted.contains("mosaic_refresh=<redacted>"))
        #expect(redacted.contains("mosaic_access=<redacted>"))
        #expect(redacted.contains("mosaic_auth_state=<redacted>"))
    }

    @Test func redactionCoversEncodedNestedCallbackState() {
        let redacted = AuthDebugLog.redacted(
            "auth.browser.session.create signInURL=http://localhost:4577/handler/native-sign-in?after_auth_return_to=http%3A%2F%2Flocalhost%3A4577%2Fhandler%2Fafter-sign-in%3Fnative_app_return_to%3Dmosaic-dev-safauth%253A%252F%252Fauth-callback%253Fmosaic_auth_state%253Dstate-secret"
        )

        #expect(redacted.contains("state-secret") == false)
        #expect(redacted.contains("mosaic_auth_state%253D<redacted>"))
    }
}
