import CmuxCollaboration
import Foundation
import Testing

struct CollaborationTerminalInviteCodeResolverTests {
    @Test
    func hostedSurfaceResolvesOwningSessionCode() {
        let surfaceID = UUID()
        let terminalID = "AAAA:terminal:workspace-a:surface-a"
        var router = CollaborationTerminalSessionRouter()
        router.record(terminalID: terminalID, sessionCode: "AAAA")

        let resolver = CollaborationTerminalInviteCodeResolver(
            hostedTerminalIDsBySurfaceID: [surfaceID: terminalID],
            terminalSessionRouter: router
        )

        #expect(resolver.inviteCode(forHostedSurfaceID: surfaceID) == "AAAA")
    }

    @Test
    func mirroredOrUnknownSurfaceDoesNotResolveInviteCode() {
        let hostedSurfaceID = UUID()
        let mirroredSurfaceID = UUID()
        let terminalID = "AAAA:terminal:workspace-a:surface-a"
        var router = CollaborationTerminalSessionRouter()
        router.record(terminalID: terminalID, sessionCode: "AAAA")

        let resolver = CollaborationTerminalInviteCodeResolver(
            hostedTerminalIDsBySurfaceID: [hostedSurfaceID: terminalID],
            terminalSessionRouter: router
        )

        #expect(resolver.inviteCode(forHostedSurfaceID: mirroredSurfaceID) == nil)
    }

    @Test
    func hostedSurfaceWithoutSessionRouteDoesNotResolveInviteCode() {
        let surfaceID = UUID()
        let resolver = CollaborationTerminalInviteCodeResolver(
            hostedTerminalIDsBySurfaceID: [surfaceID: "missing-terminal"],
            terminalSessionRouter: CollaborationTerminalSessionRouter()
        )

        #expect(resolver.inviteCode(forHostedSurfaceID: surfaceID) == nil)
    }
}
