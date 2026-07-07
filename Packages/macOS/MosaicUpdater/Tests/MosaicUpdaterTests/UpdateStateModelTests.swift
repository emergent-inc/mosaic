import Foundation
import Testing
@preconcurrency import Sparkle
@testable import MosaicUpdater

@MainActor
@Suite struct UpdateStateModelTests {
    /// A model backed by an isolated, empty `UserDefaults` suite so auto-present persistence tests
    /// don't read or write the shared standard defaults.
    private func makeModelWithIsolatedDefaults() -> (UpdateStateModel, UserDefaults) {
        let defaults = UserDefaults(suiteName: "MosaicUpdaterTests.\(UUID().uuidString)")!
        return (UpdateStateModel(defaults: defaults), defaults)
    }

    /// Builds a minimal appcast item whose `displayVersionString` is `version`.
    private func appcastItem(version: String) -> SUAppcastItem {
        SUAppcastItem(dictionary: [
            "title": "mosaic \(version)",
            "pubDate": "Wed, 25 Mar 2026 12:00:00 +0000",
            "enclosure": [
                "url": "https://example.com/mosaic.dmg",
                "length": "1024",
                "sparkle:version": version,
                "sparkle:shortVersionString": version,
            ],
        ]) ?? SUAppcastItem.empty()
    }
    @Test func setStateEmitsOnStateChangesStream() async {
        let model = UpdateStateModel()
        var iterator = model.stateChanges().makeAsyncIterator()

        model.setState(.checking(.init(cancel: {})))
        let signal: Void? = await iterator.next()

        #expect(signal != nil)
        #expect(model.state == .checking(.init(cancel: {})))
    }

    @Test func setOverrideStateAlsoEmits() async {
        let model = UpdateStateModel()
        var iterator = model.stateChanges().makeAsyncIterator()

        model.setOverrideState(.notFound(.init(acknowledgement: {})))
        let signal: Void? = await iterator.next()

        #expect(signal != nil)
        #expect(model.overrideState == .notFound(.init(acknowledgement: {})))
    }

    @Test func effectiveStatePrefersOverride() {
        let model = UpdateStateModel()
        model.setState(.idle)
        model.setOverrideState(.checking(.init(cancel: {})))
        #expect(model.effectiveState == .checking(.init(cancel: {})))
        #expect(model.showsPill)
    }

    @Test func idleWithNoDetectedUpdateHidesPill() {
        let model = UpdateStateModel()
        #expect(model.state == .idle)
        #expect(!model.showsPill)
        #expect(model.iconName == nil)
        #expect(model.text.isEmpty)
    }

    @Test func notFoundProducesTitleAndIcon() {
        let model = UpdateStateModel()
        model.setState(.notFound(.init(acknowledgement: {})))
        #expect(model.iconName == "info.circle")
        #expect(!model.text.isEmpty)
    }

    @Test func networkErrorTitleIsUserFacing() {
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let title = UpdateStateModel.userFacingErrorTitle(for: offline)
        #expect(title == "No Internet Connection")
    }

    @Test func errorDetailsIncludesLogPath() {
        let err = NSError(domain: "mosaic.update", code: 7, userInfo: [NSLocalizedDescriptionKey: "boom"])
        let details = UpdateStateModel.errorDetails(for: err, technicalDetails: "ctx", feedURLString: "https://feed", logPath: "/tmp/x.log")
        #expect(details.contains("Log: /tmp/x.log"))
        #expect(details.contains("Feed: https://feed"))
        #expect(details.contains("Debug: ctx"))
    }

    @Test func normalizedVersionTrimsAndRejectsEmpty() {
        #expect(UpdateStateModel.normalizedDetectedUpdateVersion(from: "  1.2.3 ") == "1.2.3")
        #expect(UpdateStateModel.normalizedDetectedUpdateVersion(from: "   ") == nil)
    }

    // MARK: - Installer / launchd-agent failure (SUInstallationError 4005, SUAgentInvalidationError 4010)
    //
    // Domain literal "SUSparkleErrorDomain" matches the value of Sparkle's `SUSparkleErrorDomain`
    // constant, so tests don't need to import Sparkle. Title/message assertions check English
    // substrings because `String(localized:)` falls back to its `defaultValue` under the test bundle.

    /// Regression: a 4005 installation error wrapping an agent-connection timeout (the wedged
    /// launchd-session case) adds restart guidance on top of the existing "move into Applications"
    /// guidance, rather than replacing it. Both must be present.
    @Test func installerAgentFailureKeepsRelocateGuidanceAndAddsRestart() {
        let underlying = NSError(
            domain: "SUSparkleErrorDomain",
            code: 10,
            userInfo: [NSLocalizedDescriptionKey: "Timeout: agent connection was never initiated"]
        )
        let err = NSError(
            domain: "SUSparkleErrorDomain",
            code: 4005,
            userInfo: [
                NSLocalizedDescriptionKey: "An error occurred while running the updater.",
                NSUnderlyingErrorKey: underlying,
            ]
        )
        let message = UpdateStateModel.userFacingErrorMessage(for: err)
        #expect(message.localizedCaseInsensitiveContains("Applications"))
        #expect(message.localizedCaseInsensitiveContains("restart"))
    }

    @Test func installerAgentFailureHasOwnTitleAndOffersManualDownload() {
        let underlying = NSError(domain: "SUSparkleErrorDomain", code: 10)
        let err = NSError(
            domain: "SUSparkleErrorDomain",
            code: 4005,
            userInfo: [NSUnderlyingErrorKey: underlying]
        )
        #expect(UpdateStateModel.userFacingErrorTitle(for: err).contains("Start Updater"))
        #expect(UpdateStateModel.manualDownloadURL(for: err)?.absoluteString == "https://download.mosaic.inc/mosaic-macos.dmg")
    }

    @Test func agentInvalidationErrorIsTreatedAsAgentFailure() {
        let err = NSError(domain: "SUSparkleErrorDomain", code: 4010)
        #expect(UpdateStateModel.userFacingErrorTitle(for: err).contains("Start Updater"))
        #expect(UpdateStateModel.manualDownloadURL(for: err) != nil)
    }

    @Test func genericInstallFailureKeepsPermissionTitleAndOffersDownload() {
        let err = NSError(domain: "SUSparkleErrorDomain", code: 4005)
        let title = UpdateStateModel.userFacingErrorTitle(for: err)
        #expect(!title.contains("Start Updater"))
        #expect(title.contains("Permission"))
        let message = UpdateStateModel.userFacingErrorMessage(for: err)
        #expect(message.localizedCaseInsensitiveContains("Applications"))
        #expect(UpdateStateModel.manualDownloadURL(for: err) != nil)
    }

    /// A 4005 wrapping a non-agent installer cause (auth failure, relaunch failure) must NOT be
    /// classified as a restart-fixable agent failure, since restarting won't help. It should fall
    /// through to the generic install-failed copy (which still offers a manual download).
    @Test(arguments: [4001, 4004])
    func installFailureWrappingNonAgentCauseIsNotAgentFailure(underlyingCode: Int) {
        let underlying = NSError(domain: "SUSparkleErrorDomain", code: underlyingCode, userInfo: [
            NSLocalizedDescriptionKey: "Authorization or relaunch failed.",
        ])
        let err = NSError(domain: "SUSparkleErrorDomain", code: 4005, userInfo: [
            NSLocalizedDescriptionKey: "An error occurred while running the updater.",
            NSUnderlyingErrorKey: underlying,
        ])
        let title = UpdateStateModel.userFacingErrorTitle(for: err)
        #expect(!title.contains("Start Updater"))
        #expect(title.contains("Permission"))
        #expect(UpdateStateModel.manualDownloadURL(for: err) != nil)
    }

    /// The agent-connection text signal classifies the failure even when no underlying error is
    /// present (some Sparkle traces only carry the message on the top-level 4005).
    @Test func installFailureWithAgentTextIsAgentFailure() {
        let err = NSError(domain: "SUSparkleErrorDomain", code: 4005, userInfo: [
            NSLocalizedDescriptionKey: "An error occurred while running the updater.",
            NSLocalizedFailureReasonErrorKey: "The remote port connection was invalidated from the updater.",
        ])
        #expect(UpdateStateModel.userFacingErrorTitle(for: err).contains("Start Updater"))
    }

    @Test func downloadErrorOffersManualDownload() {
        let err = NSError(domain: "SUSparkleErrorDomain", code: 2001)
        #expect(UpdateStateModel.manualDownloadURL(for: err) != nil)
    }

    @Test(arguments: [1000, 1001, 1002, 3, 4, 3001, 3002])
    func feedSignatureAndNoUpdateErrorsDoNotOfferManualDownload(code: Int) {
        let err = NSError(domain: "SUSparkleErrorDomain", code: code)
        #expect(UpdateStateModel.manualDownloadURL(for: err) == nil)
    }

    @Test func diskImageErrorStillSaysMoveToApplications() {
        let err = NSError(domain: "SUSparkleErrorDomain", code: 1003)
        let message = UpdateStateModel.userFacingErrorMessage(for: err)
        #expect(message.localizedCaseInsensitiveContains("Applications"))
        #expect(UpdateStateModel.manualDownloadURL(for: err) == nil)
    }

    @Test func nonSparkleErrorHasNoManualDownload() {
        let err = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        #expect(UpdateStateModel.manualDownloadURL(for: err) == nil)
    }

    @Test func errorDetailsNamesInstallationError() {
        let err = NSError(
            domain: "SUSparkleErrorDomain",
            code: 4005,
            userInfo: [NSLocalizedDescriptionKey: "boom"]
        )
        let details = UpdateStateModel.errorDetails(
            for: err,
            technicalDetails: nil,
            feedURLString: nil,
            logPath: "/tmp/x.log"
        )
        #expect(details.contains("SUInstallationError"))
    }

    // MARK: - Auto-present detected background update (open the popover once per version)

    @Test func backgroundDetectionOfNewVersionRequestsAutoPresent() {
        let (model, _) = makeModelWithIsolatedDefaults()
        // Idle + a freshly detected version → request auto-present.
        model.recordDetectedUpdate(appcastItem(version: "1.2.3"))
        #expect(model.pendingAutoPresentVersion == "1.2.3")
        #expect(model.showsDetectedBackgroundUpdate)
        #expect(model.hasCachedDetectedUpdateDetails)
    }

    @Test func alreadyPromptedVersionDoesNotRequestAutoPresentAgain() {
        let (model, _) = makeModelWithIsolatedDefaults()

        model.recordDetectedUpdate(appcastItem(version: "1.2.3"))
        #expect(model.pendingAutoPresentVersion == "1.2.3")

        // The UI shows the popover and marks it — persisting the version.
        model.markAutoPresentShown()
        #expect(model.pendingAutoPresentVersion == nil)

        // Re-detecting the same version (e.g. a later background probe) must not re-open.
        model.recordDetectedUpdate(appcastItem(version: "1.2.3"))
        #expect(model.pendingAutoPresentVersion == nil)
    }

    @Test func newVersionAfterPromptRequestsAutoPresentAgain() {
        let (model, _) = makeModelWithIsolatedDefaults()

        model.recordDetectedUpdate(appcastItem(version: "1.2.3"))
        model.markAutoPresentShown()
        #expect(model.pendingAutoPresentVersion == nil)

        // A genuinely newer version re-surfaces the popover.
        model.recordDetectedUpdate(appcastItem(version: "1.2.4"))
        #expect(model.pendingAutoPresentVersion == "1.2.4")
    }

    @Test func persistedPromptedVersionSurvivesNewModelInstance() {
        let defaults = UserDefaults(suiteName: "MosaicUpdaterTests.\(UUID().uuidString)")!

        let first = UpdateStateModel(defaults: defaults)
        first.recordDetectedUpdate(appcastItem(version: "1.2.3"))
        first.markAutoPresentShown()

        // A relaunch (new model over the same defaults) must not re-prompt the same version.
        let second = UpdateStateModel(defaults: defaults)
        second.recordDetectedUpdate(appcastItem(version: "1.2.3"))
        #expect(second.pendingAutoPresentVersion == nil)
    }

    @Test func activeCheckStateDoesNotRequestAutoPresent() {
        let (model, _) = makeModelWithIsolatedDefaults()
        // A user-initiated check is in flight (not idle); finding an update here must not trigger
        // the passive auto-open path.
        model.setState(.checking(.init(cancel: {})))
        model.recordDetectedUpdate(appcastItem(version: "1.2.3"))
        #expect(model.pendingAutoPresentVersion == nil)
    }

    @Test func clearDetectedUpdateClearsPendingAutoPresent() {
        let (model, _) = makeModelWithIsolatedDefaults()
        model.recordDetectedUpdate(appcastItem(version: "1.2.3"))
        #expect(model.pendingAutoPresentVersion == "1.2.3")

        model.clearDetectedUpdate()
        #expect(model.pendingAutoPresentVersion == nil)
    }
}
