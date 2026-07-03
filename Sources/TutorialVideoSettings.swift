import Foundation

enum TutorialVideoSettings {
    static let seenKey = "cmuxTutorialVideoSeen.v1"

    static func hasSeenTutorial(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: seenKey)
    }

    static func markSeen(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: seenKey)
    }
}

enum TutorialVideoFirstRunPresentation {
    static let uiTestAutoShowEnvironmentKey = "CMUX_UI_TEST_TUTORIAL_VIDEO_AUTO_SHOW"

    static func shouldPresentAutomatically(
        isRunningUnderXCTest: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
    ) -> Bool {
        if isRunningUnderXCTest && environment[uiTestAutoShowEnvironmentKey] != "1" {
            return false
        }
        return !TutorialVideoSettings.hasSeenTutorial(defaults: defaults)
    }

    static func claimAutomaticPresentationIfNeeded(
        isRunningUnderXCTest: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard shouldPresentAutomatically(
            isRunningUnderXCTest: isRunningUnderXCTest,
            environment: environment,
            defaults: defaults
        ) else {
            return false
        }
        TutorialVideoSettings.markSeen(defaults: defaults)
        return true
    }
}
