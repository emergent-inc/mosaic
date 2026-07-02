import Foundation

enum MosaicBranding {
    static let docsBaseURL = URL(string: "https://mosaic.com/docs")!
    static let githubRepositoryURL = URL(string: "https://github.com/manaflow-ai/mosaic")!
    static let githubIssuesURL = URL(string: "https://github.com/manaflow-ai/mosaic/issues")!

    static func docsURL(_ path: String = "") -> URL {
        guard !path.isEmpty else { return docsBaseURL }
        return docsBaseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
}

enum CmuxHelpResource {
    case gettingStarted
    case concepts
    case configuration
    case customCommands
    case dock
    case keyboardShortcuts
    case apiReference
    case browserAutomation
    case notifications
    case ssh
    case skills
    case claudeCodeTeams
    case ohMyOpenCode
    case ohMyCodex
    case ohMyClaudeCode
    case changelog
    case githubIssues
    case discord

    var title: String {
        switch self {
        case .gettingStarted:
            return String(localized: "menu.help.gettingStarted", defaultValue: "Getting Started")
        case .concepts:
            return String(localized: "menu.help.concepts", defaultValue: "Concepts")
        case .configuration:
            return String(localized: "menu.help.configuration", defaultValue: "Configuration")
        case .customCommands:
            return String(localized: "menu.help.customCommands", defaultValue: "Custom Commands")
        case .dock:
            return String(localized: "menu.help.dock", defaultValue: "Dock")
        case .keyboardShortcuts:
            return String(localized: "settings.section.keyboardShortcuts", defaultValue: "Keyboard Shortcuts")
        case .apiReference:
            return String(localized: "menu.help.apiReference", defaultValue: "API Reference")
        case .browserAutomation:
            return String(localized: "menu.help.browserAutomation", defaultValue: "Browser Automation")
        case .notifications:
            return String(localized: "menu.help.notifications", defaultValue: "Notifications")
        case .ssh:
            return String(localized: "menu.help.ssh", defaultValue: "SSH")
        case .skills:
            return String(localized: "menu.help.skills", defaultValue: "Skills")
        case .claudeCodeTeams:
            return String(localized: "menu.help.claudeCodeTeams", defaultValue: "Claude Code Teams")
        case .ohMyOpenCode:
            return String(localized: "menu.help.ohMyOpenCode", defaultValue: "oh-my-opencode")
        case .ohMyCodex:
            return String(localized: "menu.help.ohMyCodex", defaultValue: "oh-my-codex")
        case .ohMyClaudeCode:
            return String(localized: "menu.help.ohMyClaudeCode", defaultValue: "oh-my-claudecode")
        case .changelog:
            return String(localized: "menu.help.changelog", defaultValue: "Changelog")
        case .githubIssues:
            return String(localized: "sidebar.help.githubIssues", defaultValue: "GitHub Issues")
        case .discord:
            return String(localized: "sidebar.help.discord", defaultValue: "Discord")
        }
    }

    var url: URL {
        switch self {
        case .gettingStarted:
            return MosaicBranding.docsURL("getting-started")
        case .concepts:
            return MosaicBranding.docsURL("concepts")
        case .configuration:
            return MosaicBranding.docsURL("configuration")
        case .customCommands:
            return MosaicBranding.docsURL("custom-commands")
        case .dock:
            return MosaicBranding.docsURL("dock")
        case .keyboardShortcuts:
            return MosaicBranding.docsURL("keyboard-shortcuts")
        case .apiReference:
            return MosaicBranding.docsURL("api")
        case .browserAutomation:
            return MosaicBranding.docsURL("browser-automation")
        case .notifications:
            return MosaicBranding.docsURL("notifications")
        case .ssh:
            return MosaicBranding.docsURL("ssh")
        case .skills:
            return MosaicBranding.docsURL("skills")
        case .claudeCodeTeams:
            return MosaicBranding.docsURL("agent-integrations/claude-code-teams")
        case .ohMyOpenCode:
            return MosaicBranding.docsURL("agent-integrations/oh-my-opencode")
        case .ohMyCodex:
            return MosaicBranding.docsURL("agent-integrations/oh-my-codex")
        case .ohMyClaudeCode:
            return MosaicBranding.docsURL("agent-integrations/oh-my-claudecode")
        case .changelog:
            return MosaicBranding.docsURL("changelog")
        case .githubIssues:
            return MosaicBranding.githubIssuesURL
        case .discord:
            return URL(string: "https://discord.gg/zmWHDeZffZ")!
        }
    }
}
