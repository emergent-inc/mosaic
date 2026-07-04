import MosaicAgentLaunch
import Testing

@Suite("Claude Teams prompt boundary rejects")
struct ClaudeTeamsPromptBoundaryRejectTests {
    @Test("Drops non-restorable-looking prompt text after tmux prompt boundary")
    func dropsNonRestorableLookingPromptTextAfterTmuxPromptBoundary() {
        #expect(
            AgentLaunchSanitizer.sanitizedLaunchArguments(
                [
                    "/Applications/mosaic.app/Contents/Resources/bin/mosaic",
                    "claude-teams",
                    "--tmux",
                    "fix",
                    "--no-session-persistence",
                ],
                launcher: "claudeTeams",
                fallbackKind: "claude"
            ) == [
                "/Applications/mosaic.app/Contents/Resources/bin/mosaic",
                "claude-teams",
            ]
        )
        #expect(
            AgentLaunchSanitizer.sanitizedLaunchArguments(
                [
                    "/Applications/mosaic.app/Contents/Resources/bin/mosaic",
                    "claude-teams",
                    "--tmux",
                    "fix",
                    "--print=true",
                ],
                launcher: "claudeTeams",
                fallbackKind: "claude"
            ) == [
                "/Applications/mosaic.app/Contents/Resources/bin/mosaic",
                "claude-teams",
            ]
        )
    }
}
