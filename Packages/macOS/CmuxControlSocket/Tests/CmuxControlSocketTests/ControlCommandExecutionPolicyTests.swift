import Testing
@testable import CmuxControlSocket

@Suite("ControlCommandExecutionPolicy")
struct ControlCommandExecutionPolicyTests {
    @Test func vmPrefixedMethodsRunOnTheSocketWorker() {
        #expect(ControlCommandExecutionPolicy(forMethod: "vm.create") == .socketWorker(mainThreadCallable: false))
        #expect(ControlCommandExecutionPolicy(forMethod: "vm.anything.else").runsOnSocketWorker)
    }

    @Test func remotesPrefixedMethodsRunOnTheSocketWorker() {
        // `cmux remotes` verbs make blocking authenticated web API calls, so
        // they must run on the worker; otherwise the dispatcher never reaches
        // their handler and returns method_not_found.
        #expect(ControlCommandExecutionPolicy(forMethod: "remotes.list") == .socketWorker(mainThreadCallable: false))
        #expect(ControlCommandExecutionPolicy(forMethod: "remotes.add") == .socketWorker(mainThreadCallable: false))
        #expect(ControlCommandExecutionPolicy(forMethod: "remotes.remove") == .socketWorker(mainThreadCallable: false))
    }

    @Test func fixedWorkerSetRunsOnTheSocketWorker() {
        for method in [
            "system.ping", "system.capabilities", "auth.status", "auth.sign_in_url",
            "feed.push", "browser.download.wait", "system.top", "system.memory",
            "workspace.remote.pty_bridge", "workspace.env", "sidebar.custom.reload",
            "sidebar.custom.open",
            "debug.sidebar.simulate_drag", "mobile.attach_ticket.create",
            "mobile.terminal.set_font",
            "agent.room.consume",
            // JavaScript-evaluating browser methods block on page JS and must
            // not hold the main actor (see socketWorkerMethods rationale).
            "browser.eval", "browser.wait", "browser.snapshot", "browser.click",
            "browser.fill", "browser.navigate", "browser.get.text",
            "browser.find.text", "browser.highlight",
            // Adjacent WebKit/page-state methods wait on JS, cookie, or
            // capture callbacks and follow the same worker-lane contract.
            "browser.screenshot", "browser.frame.select", "browser.dialog.accept",
            "browser.dialog.dismiss", "browser.cookies.get", "browser.cookies.set",
            "browser.cookies.clear", "browser.storage.get", "browser.storage.set",
            "browser.storage.clear", "browser.console.list", "browser.console.clear",
            "browser.errors.list", "browser.state.save", "browser.state.load",
            "browser.addinitscript", "browser.addscript", "browser.addstyle",
        ] {
            #expect(ControlCommandExecutionPolicy(forMethod: method).runsOnSocketWorker, "\(method)")
        }
    }

    @Test func agentRoomConsumeRunsOnTheSocketWorker() {
        // Regression: agent.room.consume awaits the ClaudeRoomStore actor, so it
        // must run async on the worker lane where socketWorkerV2Response handles
        // it. Its sibling verbs are served by the main-actor processCommand
        // switch, which has no consume case -- classifying consume as .mainActor
        // routed it there and every hook call returned method_not_found, silently
        // breaking invisible pull-delivery between wired agents.
        let policy = ControlCommandExecutionPolicy(forMethod: "agent.room.consume")
        #expect(policy == .socketWorker(mainThreadCallable: false))
        #expect(policy.runsOnSocketWorker)
        // agent.room.recap (SessionStart recap + cursor reset) awaits the same
        // actor and reads transcript files, so it shares the worker lane.
        #expect(ControlCommandExecutionPolicy(forMethod: "agent.room.recap") == .socketWorker(mainThreadCallable: false))
        // The other agent.room.* verbs intentionally stay on the main actor
        // (processCommand serves them); guard the asymmetry so a future edit
        // does not silently move consume off the worker lane again.
        #expect(ControlCommandExecutionPolicy(forMethod: "agent.room.digest") == .mainActor)
        #expect(ControlCommandExecutionPolicy(forMethod: "agent.room.post") == .mainActor)
    }

    @Test func everythingElseRunsOnTheMainActor() {
        for method in [
            "surface.list", "workspace.create", "window.list", "browser.url.get",
            "browser.open_split", "browser.get.title", "browser.frame.main",
            "mobile.terminal.create", "feed.jump", "vmx.create", "",
        ] {
            let policy = ControlCommandExecutionPolicy(forMethod: method)
            #expect(policy == .mainActor, "\(method)")
            #expect(!policy.runsOnSocketWorker, "\(method)")
        }
    }

    @Test func onlyPureProbesAreMainThreadCallable() {
        #expect(ControlCommandExecutionPolicy(forMethod: "system.ping") == .socketWorker(mainThreadCallable: true))
        #expect(ControlCommandExecutionPolicy(forMethod: "system.capabilities") == .socketWorker(mainThreadCallable: true))
        #expect(ControlCommandExecutionPolicy(forMethod: "system.top") == .socketWorker(mainThreadCallable: false))
        #expect(ControlCommandExecutionPolicy(forMethod: "vm.create") == .socketWorker(mainThreadCallable: false))
    }
}
