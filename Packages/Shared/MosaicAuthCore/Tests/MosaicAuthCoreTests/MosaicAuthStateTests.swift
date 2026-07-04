import MosaicAuthCore
import Foundation
import Testing

@Suite("MosaicAuthCore")
struct MosaicAuthStateTests {
    @Test("Config resolves development defaults and overrides")
    func configResolvesDevelopmentDefaultsAndOverrides() {
        let defaults = MosaicAuthConfig(
            environment: .development,
            developmentProjectId: "dev-project",
            productionProjectId: "prod-project",
            developmentPublishableClientKey: "dev-key",
            productionPublishableClientKey: "prod-key"
        )
        #expect(defaults == MosaicAuthConfig(projectId: "dev-project", publishableClientKey: "dev-key"))

        let overrides = MosaicAuthConfig(
            environment: .development,
            overrides: [
                "STACK_PROJECT_ID_DEV": "override-project",
                "STACK_PUBLISHABLE_CLIENT_KEY_DEV": "override-key",
            ],
            developmentProjectId: "dev-project",
            productionProjectId: "prod-project",
            developmentPublishableClientKey: "dev-key",
            productionPublishableClientKey: "prod-key"
        )
        #expect(overrides == MosaicAuthConfig(projectId: "override-project", publishableClientKey: "override-key"))
    }

    @Test("Config resolves production defaults and overrides")
    func configResolvesProductionDefaultsAndOverrides() {
        let defaults = MosaicAuthConfig(
            environment: .production,
            developmentProjectId: "dev-project",
            productionProjectId: "prod-project",
            developmentPublishableClientKey: "dev-key",
            productionPublishableClientKey: "prod-key"
        )
        #expect(defaults == MosaicAuthConfig(projectId: "prod-project", publishableClientKey: "prod-key"))

        let overrides = MosaicAuthConfig(
            environment: .production,
            overrides: [
                "STACK_PROJECT_ID_PROD": "override-project",
                "STACK_PUBLISHABLE_CLIENT_KEY_PROD": "override-key",
            ],
            developmentProjectId: "dev-project",
            productionProjectId: "prod-project",
            developmentPublishableClientKey: "dev-key",
            productionPublishableClientKey: "prod-key"
        )
        #expect(overrides == MosaicAuthConfig(projectId: "override-project", publishableClientKey: "override-key"))
    }

    @Test("Launch config returns credentials only when enabled")
    func launchConfigReturnsCredentialsOnlyWhenEnabled() {
        let environment = [
            "MOSAIC_UITEST_STACK_EMAIL": "test@example.com",
            "MOSAIC_UITEST_STACK_PASSWORD": "pass123",
        ]

        #expect(
            MosaicAuthAutoLoginCredentials(
                environment: environment,
                clearAuth: false,
                mockDataEnabled: false
            ) == MosaicAuthAutoLoginCredentials(email: "test@example.com", password: "pass123")
        )
        #expect(
            MosaicAuthAutoLoginCredentials(
                environment: environment,
                clearAuth: true,
                mockDataEnabled: false
            ) == nil
        )
        #expect(
            MosaicAuthAutoLoginCredentials(
                environment: environment,
                clearAuth: false,
                mockDataEnabled: true
            ) == nil
        )
    }

    @Test("Launch config returns fixture user only when enabled")
    func launchConfigReturnsFixtureUserOnlyWhenEnabled() {
        let environment = [
            "MOSAIC_UITEST_AUTH_FIXTURE": "1",
            "MOSAIC_UITEST_AUTH_USER_ID": "fixture-user",
            "MOSAIC_UITEST_AUTH_EMAIL": "fixture@example.com",
            "MOSAIC_UITEST_AUTH_NAME": "Fixture User",
        ]

        #expect(
            MosaicAuthUser(
                uiTestFixtureEnvironment: environment,
                clearAuth: false,
                mockDataEnabled: false
            ) == MosaicAuthUser(
                id: "fixture-user",
                primaryEmail: "fixture@example.com",
                displayName: "Fixture User"
            )
        )
        #expect(
            MosaicAuthUser(
                uiTestFixtureEnvironment: environment,
                clearAuth: true,
                mockDataEnabled: false
            ) == nil
        )
        #expect(
            MosaicAuthUser(
                uiTestFixtureEnvironment: environment,
                clearAuth: false,
                mockDataEnabled: true
            ) == nil
        )
    }

    @Test("Primed state authenticates cached user while validating tokens")
    func primedStateAuthenticatesCachedUserWhileValidatingTokens() {
        let user = MosaicAuthUser(id: "user_123", primaryEmail: "user@example.com", displayName: "Test User")
        let state = MosaicAuthState.primed(
            clearAuthRequested: false,
            mockDataEnabled: false,
            fixtureUser: nil,
            autoLoginCredentials: nil,
            cachedUser: user,
            hasTokens: true,
            mockUser: MosaicAuthUser(id: "mock", primaryEmail: "mock@example.com", displayName: "Mock")
        )

        #expect(state.isAuthenticated)
        #expect(state.currentUser == user)
        #expect(!state.isRestoringSession)
    }

    @Test("Primed state restores when tokens exist without a cached user")
    func primedStateRestoresWhenTokensExistWithoutCachedUser() {
        let state = MosaicAuthState.primed(
            clearAuthRequested: false,
            mockDataEnabled: false,
            fixtureUser: nil,
            autoLoginCredentials: nil,
            cachedUser: nil,
            hasTokens: true,
            mockUser: MosaicAuthUser(id: "mock", primaryEmail: "mock@example.com", displayName: "Mock")
        )

        #expect(!state.isAuthenticated)
        #expect(state.currentUser == nil)
        #expect(state.isRestoringSession)
    }

    @Test("Primed state does not authenticate from auto-login credentials before sign-in")
    func primedStateDoesNotAuthenticateFromAutoLoginCredentialsBeforeSignIn() {
        let user = MosaicAuthUser(id: "user_123", primaryEmail: "user@example.com", displayName: "Test User")
        let state = MosaicAuthState.primed(
            clearAuthRequested: false,
            mockDataEnabled: false,
            fixtureUser: nil,
            autoLoginCredentials: MosaicAuthAutoLoginCredentials(email: "user@example.com", password: "password"),
            cachedUser: user,
            hasTokens: false,
            mockUser: MosaicAuthUser(id: "mock", primaryEmail: "mock@example.com", displayName: "Mock")
        )

        #expect(!state.isAuthenticated)
        #expect(state.currentUser == user)
        #expect(state.isRestoringSession)
    }

    @Test("Primed state ignores auto-login credentials when cached tokens exist")
    func primedStateIgnoresAutoLoginCredentialsWhenCachedTokensExist() {
        let user = MosaicAuthUser(id: "user_123", primaryEmail: "user@example.com", displayName: "Test User")
        let state = MosaicAuthState.primed(
            clearAuthRequested: false,
            mockDataEnabled: false,
            fixtureUser: nil,
            autoLoginCredentials: MosaicAuthAutoLoginCredentials(email: "user@example.com", password: "password"),
            cachedUser: user,
            hasTokens: true,
            mockUser: MosaicAuthUser(id: "mock", primaryEmail: "mock@example.com", displayName: "Mock")
        )

        #expect(state.isAuthenticated)
        #expect(state.currentUser == user)
        #expect(!state.isRestoringSession)
    }

    @Test("Primed state does not authenticate from cached user alone")
    func primedStateDoesNotAuthenticateFromCachedUserAlone() {
        let user = MosaicAuthUser(id: "user_123", primaryEmail: "user@example.com", displayName: "Test User")
        let state = MosaicAuthState.primed(
            clearAuthRequested: false,
            mockDataEnabled: false,
            fixtureUser: nil,
            autoLoginCredentials: nil,
            cachedUser: user,
            hasTokens: false,
            mockUser: MosaicAuthUser(id: "mock", primaryEmail: "mock@example.com", displayName: "Mock")
        )

        #expect(!state.isAuthenticated)
        #expect(state.currentUser == user)
        #expect(!state.isRestoringSession)
    }

    @Test("Primed state uses fixture user")
    func primedStateUsesFixtureUser() {
        let fixtureUser = MosaicAuthUser(id: "fixture", primaryEmail: "fixture@example.com", displayName: "Fixture")
        let state = MosaicAuthState.primed(
            clearAuthRequested: false,
            mockDataEnabled: false,
            fixtureUser: fixtureUser,
            autoLoginCredentials: nil,
            cachedUser: nil,
            hasTokens: false,
            mockUser: MosaicAuthUser(id: "mock", primaryEmail: "mock@example.com", displayName: "Mock")
        )

        #expect(state.isAuthenticated)
        #expect(state.currentUser == fixtureUser)
        #expect(!state.isRestoringSession)
    }

    @Test("Cleared state clears auth")
    func clearedStateClearsAuth() {
        #expect(MosaicAuthState.cleared() == MosaicAuthState(isAuthenticated: false, currentUser: nil, isRestoringSession: false))
    }

    @Test("Identity store and session cache round trip")
    func identityStoreAndSessionCacheRoundTrip() throws {
        let store = TestKeyValueStore()
        let identityStore = MosaicAuthIdentityStore(keyValueStore: store, key: "auth_cached_user")
        let sessionCache = MosaicAuthSessionCache(keyValueStore: store, key: "auth_has_tokens")
        let user = MosaicAuthUser(id: "user_123", primaryEmail: "user@example.com", displayName: "Test User")

        try identityStore.save(user)
        #expect(try identityStore.load() == user)

        sessionCache.setHasTokens(true)
        #expect(sessionCache.hasTokens)

        identityStore.clear()
        sessionCache.clear()

        #expect(try identityStore.load() == nil)
        #expect(!sessionCache.hasTokens)
    }
}

private final class TestKeyValueStore: MosaicAuthKeyValueStore {
    private var storage: [String: Any] = [:]

    func bool(forKey defaultName: String) -> Bool {
        storage[defaultName] as? Bool ?? false
    }

    func data(forKey defaultName: String) -> Data? {
        storage[defaultName] as? Data
    }

    func string(forKey defaultName: String) -> String? {
        storage[defaultName] as? String
    }

    func set(_ value: Any?, forKey defaultName: String) {
        storage[defaultName] = value
    }

    func removeObject(forKey defaultName: String) {
        storage.removeValue(forKey: defaultName)
    }
}
