import CMUXAuthCore
import Testing
@testable import CmuxAuthRuntime

@Suite struct AuthConfigTests {
    @Test func productionUsesStackWhitelistedCmuxDomain() {
        let config = AuthConfig(environment: .production)

        #expect(config.magicLinkCallbackURL == "https://dashboard.mosaic.inc/auth/callback")
        #expect(config.apiBaseURL == "https://dashboard.mosaic.inc")
    }
}
