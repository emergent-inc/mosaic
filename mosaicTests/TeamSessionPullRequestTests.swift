import Foundation
import Testing

#if canImport(Mosaic_DEV)
@testable import Mosaic_DEV
#elseif canImport(Mosaic)
@testable import Mosaic
#endif

@Suite("MosaicSessionPullURLRequest")
struct MosaicSessionPullURLRequestTests {
    private let schemes: Set<String> = ["mosaic"]

    private func parse(_ string: String) -> MosaicSessionPullURLRequest? {
        guard let url = URL(string: string) else { return nil }
        return MosaicSessionPullURLRequest.parse(url, supportedSchemes: schemes)
    }

    @Test
    func parsesSessionPullDeepLinks() {
        let plain = parse("mosaic://session/pull?id=0e9f3a52-aaaa-bbbb-cccc-ddddeeeeffff")
        let withTeam = parse("mosaic://session/pull?id=abc-123&team=org_2xyz")

        #expect(plain?.sessionId == "0e9f3a52-aaaa-bbbb-cccc-ddddeeeeffff")
        #expect(plain?.teamId == nil)
        #expect(withTeam?.sessionId == "abc-123")
        #expect(withTeam?.teamId == "org_2xyz")
    }

    @Test
    func rejectsOtherRoutesSchemesAndInvalidIds() {
        #expect(parse("mosaic://session/pull") == nil)
        #expect(parse("mosaic://session/pull?id=") == nil)
        #expect(parse("mosaic://session/pull?id=has%20space") == nil)
        #expect(parse("mosaic://session/pull?id=..%2F..%2Fetc") == nil)
        #expect(parse("mosaic://session/other?id=abc") == nil)
        #expect(parse("mosaic://workspace/pull?id=abc") == nil)
        #expect(parse("https://session/pull?id=abc") == nil)
    }

    @Test
    func roundTripsThroughTheURLBuilder() throws {
        let url = try #require(MosaicSessionPullURLRequest.url(
            sessionId: "abc-123",
            teamId: "org_2xyz",
            scheme: "mosaic"
        ))

        let parsed = MosaicSessionPullURLRequest.parse(url, supportedSchemes: schemes)

        #expect(parsed?.sessionId == "abc-123")
        #expect(parsed?.teamId == "org_2xyz")
    }
}

@Suite("TeamSessionPullCoordinator remote normalization")
struct TeamSessionPullRemoteNormalizationTests {
    @Test
    func equivalentRemoteFormsCompareEqual() {
        let forms = [
            "git@github.com:acme/app.git",
            "ssh://git@github.com/acme/app",
            "https://github.com/acme/app.git",
            "https://github.com/acme/app/",
            "GIT@GITHUB.COM:Acme/App.git",
        ]

        let normalized = Set(forms.map(TeamSessionPullCoordinator.normalizedGitRemote))

        #expect(normalized == ["github.com/acme/app"])
    }

    @Test
    func differentRepositoriesStayDistinct() {
        #expect(
            TeamSessionPullCoordinator.normalizedGitRemote("git@github.com:acme/app.git")
                != TeamSessionPullCoordinator.normalizedGitRemote("git@github.com:acme/other.git")
        )
    }
}
