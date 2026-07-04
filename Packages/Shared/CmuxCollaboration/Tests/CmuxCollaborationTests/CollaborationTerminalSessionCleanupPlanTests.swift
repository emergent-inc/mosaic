import CmuxCollaboration
import Testing

struct CollaborationTerminalSessionCleanupPlanTests {
    @Test
    func includesEveryRouterTerminalForTheEndedSession() {
        var router = CollaborationTerminalSessionRouter()
        router.record(terminalID: "AAAA:terminal:workspace-a:surface-a", sessionCode: "AAAA")
        router.record(terminalID: "AAAA:terminal:workspace-a:surface-b", sessionCode: "AAAA")
        router.record(terminalID: "BBBB:terminal:workspace-b:surface-a", sessionCode: "BBBB")

        let plan = CollaborationTerminalSessionCleanupPlan(
            sessionCode: "AAAA",
            terminalSessionRouter: router,
            hostedTerminalIDs: [],
            mirroredTerminalIDs: []
        )

        #expect(plan.terminalIDs == [
            "AAAA:terminal:workspace-a:surface-a",
            "AAAA:terminal:workspace-a:surface-b",
        ])
    }

    @Test
    func includesMappedSessionPrefixedTerminalsWhenRouterEntryIsMissing() {
        var router = CollaborationTerminalSessionRouter()
        router.record(terminalID: "AAAA:terminal:workspace-a:surface-a", sessionCode: "AAAA")
        router.record(terminalID: "BBBB:terminal:workspace-b:surface-a", sessionCode: "BBBB")

        let plan = CollaborationTerminalSessionCleanupPlan(
            sessionCode: "AAAA",
            terminalSessionRouter: router,
            hostedTerminalIDs: [
                "AAAA:terminal:workspace-a:surface-a",
                "AAAA:terminal:workspace-a:surface-b",
            ],
            mirroredTerminalIDs: [
                "AAAA:terminal:workspace-c:surface-c",
                "BBBB:terminal:workspace-b:surface-a",
            ]
        )

        #expect(plan.terminalIDs == [
            "AAAA:terminal:workspace-a:surface-a",
            "AAAA:terminal:workspace-a:surface-b",
            "AAAA:terminal:workspace-c:surface-c",
        ])
    }

    @Test
    func emptySessionCodeProducesNoCleanupTargets() {
        var router = CollaborationTerminalSessionRouter()
        router.record(terminalID: "AAAA:terminal:workspace-a:surface-a", sessionCode: "AAAA")

        let plan = CollaborationTerminalSessionCleanupPlan(
            sessionCode: " ",
            terminalSessionRouter: router,
            hostedTerminalIDs: ["AAAA:terminal:workspace-a:surface-a"],
            mirroredTerminalIDs: []
        )

        #expect(plan.terminalIDs == [])
    }
}
