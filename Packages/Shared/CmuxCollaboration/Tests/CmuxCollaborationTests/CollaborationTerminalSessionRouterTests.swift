import CmuxCollaboration
import Testing

struct CollaborationTerminalSessionRouterTests {
    @Test
    func terminalsCanRouteToDifferentSessionsConcurrently() {
        var router = CollaborationTerminalSessionRouter()

        router.record(terminalID: "AAAA:terminal:workspace-a:surface-a", sessionCode: "AAAA")
        router.record(terminalID: "BBBB:terminal:workspace-b:surface-b", sessionCode: "BBBB")

        #expect(router.sessionCode(forTerminalID: "AAAA:terminal:workspace-a:surface-a") == "AAAA")
        #expect(router.sessionCode(forTerminalID: "BBBB:terminal:workspace-b:surface-b") == "BBBB")
    }

    @Test
    func terminalCanMoveToAnotherSession() {
        var router = CollaborationTerminalSessionRouter()

        router.record(terminalID: "AAAA:terminal:workspace-a:surface-a", sessionCode: "AAAA")
        router.record(terminalID: "AAAA:terminal:workspace-a:surface-a", sessionCode: "BBBB")

        #expect(router.sessionCode(forTerminalID: "AAAA:terminal:workspace-a:surface-a") == "BBBB")
    }

    @Test
    func removingOneTerminalKeepsOtherSessionRoutes() {
        var router = CollaborationTerminalSessionRouter()
        router.record(terminalID: "AAAA:terminal:workspace-a:surface-a", sessionCode: "AAAA")
        router.record(terminalID: "BBBB:terminal:workspace-b:surface-b", sessionCode: "BBBB")

        router.remove(terminalID: "AAAA:terminal:workspace-a:surface-a")

        #expect(router.sessionCode(forTerminalID: "AAAA:terminal:workspace-a:surface-a") == nil)
        #expect(router.sessionCode(forTerminalID: "BBBB:terminal:workspace-b:surface-b") == "BBBB")
    }

    @Test
    func removeAllClearsEverySessionRoute() {
        var router = CollaborationTerminalSessionRouter()
        router.record(terminalID: "AAAA:terminal:workspace-a:surface-a", sessionCode: "AAAA")
        router.record(terminalID: "BBBB:terminal:workspace-b:surface-b", sessionCode: "BBBB")

        router.removeAll()

        #expect(router.sessionCode(forTerminalID: "AAAA:terminal:workspace-a:surface-a") == nil)
        #expect(router.sessionCode(forTerminalID: "BBBB:terminal:workspace-b:surface-b") == nil)
    }

    @Test
    func preloadedRoutesAreQueryableAndEquatable() {
        let first = CollaborationTerminalSessionRouter(
            sessionCodesByTerminalID: [
                "AAAA:terminal:workspace-a:surface-a": "AAAA",
                "BBBB:terminal:workspace-b:surface-b": "BBBB",
            ]
        )
        let second = CollaborationTerminalSessionRouter(
            sessionCodesByTerminalID: [
                "AAAA:terminal:workspace-a:surface-a": "AAAA",
                "BBBB:terminal:workspace-b:surface-b": "BBBB",
            ]
        )

        #expect(first == second)
        #expect(first.sessionCode(forTerminalID: "AAAA:terminal:workspace-a:surface-a") == "AAAA")
        #expect(first.sessionCode(forTerminalID: "missing") == nil)
    }

    @Test(arguments: [
        (isShared: false, action: CollaborationTerminalShareAction.presentSessionChooser),
        (isShared: true, action: CollaborationTerminalShareAction.leaveSharedTerminal),
    ])
    func terminalButtonActionDependsOnlyOnWhetherTheTerminalIsAlreadyShared(
        isShared: Bool,
        action: CollaborationTerminalShareAction
    ) {
        #expect(CollaborationTerminalShareAction.action(isShared: isShared) == action)
    }
}
