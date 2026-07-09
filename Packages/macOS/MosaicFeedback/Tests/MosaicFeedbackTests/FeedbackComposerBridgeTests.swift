import Foundation
import Testing

@testable import MosaicFeedback

@Suite("Feedback composer bridge")
struct FeedbackComposerBridgeTests {
    @Test func emptyMessageIsRejectedBeforeAnyNetwork() async {
        await #expect(throws: FeedbackComposerBridgeError.self) {
            _ = try await FeedbackComposerBridge().submit(
                email: "valid@example.com",
                message: "   ",
                imagePaths: []
            )
        }
    }

    @Test func invalidEmailIsRejectedBeforeAnyNetwork() async {
        await #expect(throws: FeedbackComposerBridgeError.self) {
            _ = try await FeedbackComposerBridge().submit(
                email: "not-an-email",
                message: "Real message",
                imagePaths: []
            )
        }
    }

    @Test func tooManyImagesIsRejectedBeforeAnyNetwork() async {
        let settings = FeedbackComposerSettings()
        let paths = (0..<(settings.maxAttachmentCount + 1)).map { "/tmp/feedback-\($0).png" }
        await #expect(throws: FeedbackComposerBridgeError.self) {
            _ = try await FeedbackComposerBridge().submit(
                email: "valid@example.com",
                message: "Real message",
                imagePaths: paths
            )
        }
    }

    @Test func endpointHonorsEnvironmentOverride() {
        // The override is read from the process environment; with no override set
        // the resolved endpoint falls back to the production default.
        let settings = FeedbackComposerSettings()
        if ProcessInfo.processInfo.environment[settings.endpointEnvironmentKey] == nil {
            #expect(settings.endpointURL()?.absoluteString == settings.defaultEndpoint)
        }
    }

    @Test func composerRequestedNotificationNameMatchesAppContract() {
        #expect(Notification.Name.feedbackComposerRequested.rawValue == "mosaic.feedbackComposerRequested")
    }

    @Test func defaultEndpointTargetsDashboardHost() {
        // mosaic.inc stopped serving the app's API routes after the domain
        // handed the root site to a static landing page; feedback lives on the
        // dashboard deployment now (https://github.com/emergent-inc/www).
        #expect(FeedbackComposerSettings().defaultEndpoint == "https://dashboard.mosaic.inc/api/feedback")
    }

    @Test func missingEndpointMapsToUnavailableMessage() {
        // A 404 means the endpoint is gone (deployment/domain change), so the
        // user-facing copy must steer to email rather than suggest retrying.
        let message = FeedbackComposerBridge.userFacingMessage(
            for: FeedbackComposerSubmissionError.rejected(statusCode: 404)
        )
        #expect(message == "Feedback is unavailable right now. Email contact@mosaic.inc instead.")
    }
}
