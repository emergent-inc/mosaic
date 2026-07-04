import Foundation
import Testing

#if canImport(Mosaic_DEV)
@testable import Mosaic_DEV
#elseif canImport(Mosaic)
@testable import Mosaic
#endif

@Suite(.serialized)
struct TutorialVideoSettingsTests {
    @Test func seenFlagDefaultsToFalseInIsolatedDefaults() throws {
        try withIsolatedTutorialDefaults { defaults in
            #expect(!TutorialVideoSettings.hasSeenTutorial(defaults: defaults))
        }
    }

    @Test func markSeenPersistsSeenFlagOnlyInProvidedDefaults() throws {
        try withIsolatedTutorialDefaults { defaults in
            TutorialVideoSettings.markSeen(defaults: defaults)

            #expect(TutorialVideoSettings.hasSeenTutorial(defaults: defaults))
            #expect(defaults.bool(forKey: TutorialVideoSettings.seenKey))
        }
    }

    @Test func automaticPresentationShowsForFirstNonTestLaunchWhenSignedOutWithoutClaimingFlag() throws {
        try withIsolatedTutorialDefaults { defaults in
            #expect(TutorialVideoFirstRunPresentation.shouldPresentAutomatically(
                isRunningUnderXCTest: false,
                isAuthenticated: false,
                isRestoringSession: false,
                environment: [:],
                defaults: defaults
            ))

            #expect(!TutorialVideoSettings.hasSeenTutorial(defaults: defaults))
        }
    }

    @Test func automaticPresentationDoesNotRepeatAfterSeenFlagIsMarked() throws {
        try withIsolatedTutorialDefaults { defaults in
            TutorialVideoSettings.markSeen(defaults: defaults)

            #expect(!TutorialVideoFirstRunPresentation.shouldPresentAutomatically(
                isRunningUnderXCTest: false,
                isAuthenticated: false,
                isRestoringSession: false,
                environment: [:],
                defaults: defaults
            ))
        }
    }

    @Test func automaticPresentationSkipsSignedInUsers() throws {
        try withIsolatedTutorialDefaults { defaults in
            #expect(!TutorialVideoFirstRunPresentation.shouldPresentAutomatically(
                isRunningUnderXCTest: false,
                isAuthenticated: true,
                isRestoringSession: false,
                environment: [:],
                defaults: defaults
            ))
            #expect(!TutorialVideoSettings.hasSeenTutorial(defaults: defaults))
        }
    }

    @Test func automaticPresentationWaitsForSessionRestoreToSettle() throws {
        try withIsolatedTutorialDefaults { defaults in
            #expect(!TutorialVideoFirstRunPresentation.shouldPresentAutomatically(
                isRunningUnderXCTest: false,
                isAuthenticated: false,
                isRestoringSession: true,
                environment: [:],
                defaults: defaults
            ))
            #expect(!TutorialVideoSettings.hasSeenTutorial(defaults: defaults))
        }
    }

    @Test func automaticPresentationSkipsDefaultUITestLaunches() throws {
        try withIsolatedTutorialDefaults { defaults in
            #expect(!TutorialVideoFirstRunPresentation.shouldPresentAutomatically(
                isRunningUnderXCTest: true,
                isAuthenticated: false,
                isRestoringSession: false,
                environment: [:],
                defaults: defaults
            ))
            #expect(!TutorialVideoSettings.hasSeenTutorial(defaults: defaults))
        }
    }

    @Test func automaticPresentationCanBeEnabledForUITests() throws {
        try withIsolatedTutorialDefaults { defaults in
            let environment = [TutorialVideoFirstRunPresentation.uiTestAutoShowEnvironmentKey: "1"]

            #expect(TutorialVideoFirstRunPresentation.shouldPresentAutomatically(
                isRunningUnderXCTest: true,
                isAuthenticated: false,
                isRestoringSession: false,
                environment: environment,
                defaults: defaults
            ))
            #expect(!TutorialVideoSettings.hasSeenTutorial(defaults: defaults))
        }
    }

    @Test func automaticPresentationRequiresExactUITestOptInValue() throws {
        try withIsolatedTutorialDefaults { defaults in
            #expect(!TutorialVideoFirstRunPresentation.shouldPresentAutomatically(
                isRunningUnderXCTest: true,
                isAuthenticated: false,
                isRestoringSession: false,
                environment: [TutorialVideoFirstRunPresentation.uiTestAutoShowEnvironmentKey: "true"],
                defaults: defaults
            ))
        }
    }
}

struct TutorialVideoResourceTests {
    @Test func resourcePathConstantsKeepVideoSwappableByReplacingAsset() {
        #expect(TutorialVideoResource.subdirectory == "Tutorial")
        #expect(TutorialVideoResource.fileName == "demo")
        #expect(TutorialVideoResource.fileExtension == "mov")
    }

    @Test func resourceLookupPrefersTutorialSubdirectoryAsset() throws {
        let tutorialURL = try #require(URL(string: "file:///tmp/Tutorial/demo.mov"))
        let rootURL = try #require(URL(string: "file:///tmp/demo.mov"))
        var lookups: [(String, String?, String?)] = []

        let resolved = TutorialVideoResource.videoURL { resource, extensionName, subdirectory in
            lookups.append((resource, extensionName, subdirectory))
            return subdirectory == TutorialVideoResource.subdirectory ? tutorialURL : rootURL
        }

        #expect(resolved == tutorialURL)
        #expect(lookups.count == 1)
        #expect(lookups.first?.0 == "demo")
        #expect(lookups.first?.1 == "mov")
        #expect(lookups.first?.2 == "Tutorial")
    }

    @Test func resourceLookupFallsBackToRootAssetForFlattenedBundles() throws {
        let rootURL = try #require(URL(string: "file:///tmp/demo.mov"))
        var lookups: [(String, String?, String?)] = []

        let resolved = TutorialVideoResource.videoURL { resource, extensionName, subdirectory in
            lookups.append((resource, extensionName, subdirectory))
            return subdirectory == nil ? rootURL : nil
        }

        #expect(resolved == rootURL)
        #expect(lookups.count == 2)
        #expect(lookups[0].2 == "Tutorial")
        #expect(lookups[1].2 == nil)
    }

    @Test func resourceLookupReturnsNilWhenNoBundledAssetExists() {
        let resolved = TutorialVideoResource.videoURL { _, _, _ in nil }

        #expect(resolved == nil)
    }
}

private func withIsolatedTutorialDefaults(
    _ body: (UserDefaults) throws -> Void
) throws {
    let suiteName = "TutorialVideoTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }
    try body(defaults)
}
