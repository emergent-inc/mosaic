import MosaicAuthCore
import Testing
@testable import MosaicAuthRuntime

@Suite struct AuthConfigTests {
    @Test func productionUsesStackWhitelistedMosaicDomain() {
        let config = AuthConfig(environment: .production)

        #expect(config.magicLinkCallbackURL == "https://dashboard.mosaic.inc/auth/callback")
        #expect(config.apiBaseURL == "https://dashboard.mosaic.inc")
    }
}
