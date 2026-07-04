import MosaicAgentLaunch
import Testing

@Suite("Claude Teams prompt boundary isolation")
struct ClaudeTeamsPromptBoundaryRecoveryTests {
    @Test("Drops post-boundary flags for remote-control launches")
    func dropsPostBoundaryFlagsForRemoteControlLaunches() {
        #expect(
            AgentLaunchSanitizer.sanitizedLaunchArguments(
                [
                    "/Applications/mosaic.app/Contents/Resources/bin/mosaic",
                    "claude-teams",
                    "--remote-control-session-name-prefix",
                    "mosaic-team",
                    "--tmux",
                    "please",
                    "--permission-mode",
                    "bypassPermissions",
                ],
                launcher: "claudeTeams",
                fallbackKind: "claude"
            ) == [
                "/Applications/mosaic.app/Contents/Resources/bin/mosaic",
                "claude-teams",
                "--remote-control-session-name-prefix",
                "mosaic-team",
            ]
        )
    }

    @Test("Recovers safe post-boundary flags at end of argv")
    func recoversSafePostBoundaryFlagsAtEndOfArgv() {
        #expect(
            AgentLaunchSanitizer.sanitizedLaunchArguments(
                [
                    "/Applications/mosaic.app/Contents/Resources/bin/mosaic",
                    "claude-teams",
                    "--remote-control-session-name-prefix",
                    "mosaic-team",
                    "--tmux",
                    "side effect should be dropped",
                    "--model",
                    "sonnet",
                    "--permission-mode",
                    "auto",
                ],
                launcher: "claudeTeams",
                fallbackKind: "claude"
            ) == [
                "/Applications/mosaic.app/Contents/Resources/bin/mosaic",
                "claude-teams",
                "--remote-control-session-name-prefix",
                "mosaic-team",
                "--model",
                "sonnet",
                "--permission-mode",
                "auto",
            ]
        )
    }
}
