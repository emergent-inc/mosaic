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

    static func isRunningUnderXCTest(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        if environment["XCTestConfigurationFilePath"] != nil { return true }
        if environment["XCTestBundlePath"] != nil { return true }
        if environment["XCTestSessionIdentifier"] != nil { return true }
        if environment["XCInjectBundle"] != nil { return true }
        if environment["XCInjectBundleInto"] != nil { return true }
        if environment["DYLD_INSERT_LIBRARIES"]?.contains("libXCTest") == true { return true }
        if environment.keys.contains(where: { $0.hasPrefix("CMUX_UI_TEST_") }) { return true }
        return false
    }

    static func shouldPresentAutomatically(
        isRunningUnderXCTest: Bool,
        isAuthenticated: Bool = false,
        isRestoringSession: Bool = false,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
    ) -> Bool {
        if isRunningUnderXCTest && environment[uiTestAutoShowEnvironmentKey] != "1" {
            return false
        }
        guard !isRestoringSession, !isAuthenticated else {
            return false
        }
        return !TutorialVideoSettings.hasSeenTutorial(defaults: defaults)
    }
}
