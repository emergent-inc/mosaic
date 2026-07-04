import MosaicAuthCore
import Foundation
@testable import MosaicAuthRuntime

@MainActor
struct HostBrowserSignInFlowHarness {
    let flow: HostBrowserSignInFlow
    let coordinator: AuthCoordinator
    let client: FlowFakeAuthClient
    let tokenStore: FlowInMemoryTokenStore
    let factory: FakeBrowserAuthSessionFactory

    init(
        user: MosaicAuthUser? = nil,
        browserAttemptTimeout: TimeInterval = 5 * 60,
        slowSignInThreshold: TimeInterval = 30,
        clock: (any Clock<Duration>)? = nil
    ) {
        let store = FakeKeyValueStore()
        // The fake client reads and clears the SAME token store the flow seeds,
        // like production. Split stores hide seed/capture/clear races.
        let tokenStore = FlowInMemoryTokenStore()
        let client = FlowFakeAuthClient(user: user, store: tokenStore)
        let coordinator = AuthCoordinator(
            client: client,
            sessionCache: MosaicAuthSessionCache(keyValueStore: store, key: "has_tokens"),
            userCache: MosaicAuthIdentityStore(keyValueStore: store, key: "cached_user"),
            teamSelection: MosaicAuthTeamSelectionStore(keyValueStore: store, key: "selected_team"),
            anchor: FakeAnchor(),
            config: .test,
            launch: .plain()
        )
        let factory = FakeBrowserAuthSessionFactory()
        self.flow = HostBrowserSignInFlow(
            coordinator: coordinator,
            tokenStore: tokenStore,
            sessionFactory: factory,
            callbackRouter: AuthCallbackRouter(),
            makeSignInURL: { URL(string: "https://example.test/handler/sign-in?mosaic_auth_state=\($0)")! },
            callbackScheme: { "mosaic-dev" },
            clock: clock ?? ContinuousClock(),
            browserAttemptTimeout: browserAttemptTimeout,
            slowSignInThreshold: slowSignInThreshold
        )
        self.coordinator = coordinator
        self.client = client
        self.tokenStore = tokenStore
        self.factory = factory
    }

    func callbackURL(state: String) -> URL {
        URL(string: "mosaic-dev://auth-callback?mosaic_refresh=refresh-1&mosaic_access=access-1&mosaic_auth_state=\(state)")!
    }

    func fallbackCallbackURL() -> URL {
        URL(string: "mosaic-dev://auth-callback?mosaic_refresh=refresh-1&mosaic_access=access-1")!
    }

    func callbackState(_ session: FakeBrowserAuthSession) -> String {
        URLComponents(url: session.signInURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "mosaic_auth_state" })?
            .value ?? ""
    }

    func waitForSession(count: Int = 1, timeout: Duration = .seconds(2)) async {
        // The attempt task runs on the same main actor; yielding lets it reach
        // the browser-session continuation deterministically.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while factory.sessions.count < count {
            if clock.now >= deadline {
                preconditionFailure(
                    "Timed out waiting for \(count) host-browser session(s); got \(factory.sessions.count)"
                )
            }
            await Task.yield()
        }
    }

    func waitForCondition(timeout: Duration = .seconds(2), until condition: @MainActor () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline {
                preconditionFailure("Timed out waiting for host-browser condition")
            }
            await Task.yield()
        }
    }

    func waitForPendingUserRequest(timeout: Duration = .seconds(2)) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while await client.pendingUserRequests == 0 {
            if clock.now >= deadline {
                preconditionFailure("Timed out waiting for a pending user request")
            }
            await Task.yield()
        }
    }
}
