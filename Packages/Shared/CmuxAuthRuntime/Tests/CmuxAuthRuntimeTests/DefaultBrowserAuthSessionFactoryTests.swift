#if os(macOS)
import Foundation
import Testing
@testable import CmuxAuthRuntime

@MainActor
@Suite struct DefaultBrowserAuthSessionFactoryTests {
    @Test func startOpensSignInURLWithLoopbackReturnTo() async throws {
        let signInURL = URL(string: "https://example.test/handler/native-sign-in?after_auth_return_to=https%3A%2F%2Fexample.test%2Fhandler%2Fafter-sign-in%3Fnative_app_return_to%3Dmosaic-dev-test%253A%252F%252Fauth-callback%253Fmosaic_auth_state%253Dstate-1")!
        var openedURL: URL?
        let factory = DefaultBrowserAuthSessionFactory { url in
            openedURL = url
            return true
        } activateApp: {
            Issue.record("The app should activate after callback, not when the browser opens")
        }

        let session = factory.makeSession(
            signInURL: signInURL,
            callbackScheme: "mosaic-dev-test"
        ) { _ in
            Issue.record("Default-browser sessions complete through external app callbacks")
        }

        #expect(session.start())
        for _ in 0..<100 where openedURL == nil {
            await Task.yield()
        }

        let opened = try #require(openedURL)
        let afterAuthReturnTo = try #require(URLComponents(url: opened, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "after_auth_return_to" })?
            .value)
        let afterSignInURL = try #require(URL(string: afterAuthReturnTo))
        let nativeReturnTo = try #require(URLComponents(url: afterSignInURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "native_app_return_to" })?
            .value)
        let loopbackURL = try #require(URLComponents(string: nativeReturnTo))
        #expect(loopbackURL.scheme == "http")
        #expect(loopbackURL.host == "127.0.0.1")
        #expect(loopbackURL.path == "/auth-callback")
        #expect(loopbackURL.queryItems?.first(where: { $0.name == "mosaic_auth_state" })?.value == "state-1")
    }
}
#endif
