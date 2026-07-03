import Foundation
import Testing
@testable import CmuxAuthRuntime

@Suite
struct AuthCallbackRouterTests {
    @Test
    func parsesMosaicNativeCallbackTokensAndPreservesFirstDuplicateValue() throws {
        let router = AuthCallbackRouter(extraAllowedScheme: "mosaic-dev-test")
        let url = try #require(URL(string: "mosaic-dev-test://auth-callback?mosaic_refresh=refresh-real&mosaic_access=access-real&mosaic_refresh=refresh-attacker"))

        let payload = try #require(router.callbackPayload(from: url))

        #expect(payload.refreshToken == "refresh-real")
        #expect(payload.accessToken == "access-real")
    }

    @Test
    func rejectsLegacyStackTokenNamesAndUnknownSchemes() throws {
        let router = AuthCallbackRouter(extraAllowedScheme: "mosaic-dev-test")

        let legacyURL = try #require(URL(string: "mosaic-dev-test://auth-callback?stack_refresh=refresh&stack_access=access"))
        #expect(router.callbackPayload(from: legacyURL) == nil)

        let unknownSchemeURL = try #require(URL(string: "other-app://auth-callback?mosaic_refresh=refresh&mosaic_access=access"))
        #expect(router.isAuthCallbackURL(unknownSchemeURL) == false)
        #expect(router.callbackPayload(from: unknownSchemeURL) == nil)
    }

    @Test
    func rejectsMissingOrBlankNativeTokens() throws {
        let router = AuthCallbackRouter(extraAllowedScheme: "mosaic-dev-test")
        let missingAccess = try #require(URL(string: "mosaic-dev-test://auth-callback?mosaic_refresh=refresh"))
        let blankRefresh = try #require(URL(string: "mosaic-dev-test://auth-callback?mosaic_refresh=%20%20&mosaic_access=access"))

        #expect(router.callbackPayload(from: missingAccess) == nil)
        #expect(router.callbackPayload(from: blankRefresh) == nil)
    }
}
