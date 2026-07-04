import AppKit
import Testing

#if canImport(Mosaic_DEV)
@testable import Mosaic_DEV
#elseif canImport(Mosaic)
@testable import Mosaic
#endif

/// Behavior of collaboration header labels and accent alert button styling.
@MainActor
@Suite struct CollaborationSharingLabelTests {
    @Test func noPeersSummaryUsesCurrentCopy() {
        #expect(CollaborationStrings.noPeers == "No peers")
    }

    @Test func onePeerSummaryUsesCurrentCopy() {
        #expect(CollaborationStrings.onePeer == "1 peer")
    }

    @Test(arguments: [2, 5, 12])
    func peerCountSummaryFormatsCount(count: Int) {
        #expect(String(format: CollaborationStrings.peerCountFormat, count) == "\(count) peers")
    }

    @Test func sessionCreatedMessageOmitsInviteCode() {
        let inviteCode = "NXPLXZAH"

        #expect(CollaborationStrings.sessionCreatedMessage == "Share this session code with collaborators")
        #expect(!CollaborationStrings.sessionCreatedMessage.contains(inviteCode))
        #expect(!CollaborationStrings.sessionCreatedMessage.hasSuffix(":"))
    }

    @Test(arguments: ["Sign In", "Join Session", "Copy Code"])
    func collaborationAccentAlertButtonsUseBlackTitleTint(title: String) throws {
        let button = NSButton(title: title, target: nil, action: nil)

        applyCollaborationAccentAlertButtonTitleStyle(button)

        #expect(button.contentTintColor == .black)

        let foreground = try #require(
            button.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        )
        #expect(foreground == .black)

        let cell = try #require(button.cell as? NSButtonCell)
        let cellForeground = try #require(
            cell.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        )
        #expect(cellForeground == .black)
    }

    @Test func joinAcknowledgementSucceedsWhenRelayJoinedFrameArrives() async {
        let gate = CollaborationJoinAcknowledgementGate()
        let waiter = Task { @MainActor in
            await gate.wait(timeout: .seconds(1))
        }

        await Task.yield()
        gate.succeed()

        #expect(await waiter.value)
    }

    @Test func joinAcknowledgementReplaysSuccessToLaterWaiters() async {
        let gate = CollaborationJoinAcknowledgementGate()

        gate.succeed()

        #expect(await gate.wait(timeout: .milliseconds(1)))
    }

    @Test func joinAcknowledgementResumesAllPendingWaitersOnSuccess() async {
        let gate = CollaborationJoinAcknowledgementGate()
        let first = Task { @MainActor in
            await gate.wait(timeout: .seconds(1))
        }
        let second = Task { @MainActor in
            await gate.wait(timeout: .seconds(1))
        }

        await Task.yield()
        gate.succeed()

        #expect(await first.value)
        #expect(await second.value)
    }

    @Test func joinAcknowledgementFailsWhenRelayRejectsBeforeJoinedFrame() async {
        let gate = CollaborationJoinAcknowledgementGate()
        let waiter = Task { @MainActor in
            await gate.wait(timeout: .seconds(1))
        }

        await Task.yield()
        gate.fail()

        #expect(await waiter.value == false)
    }

    @Test func joinAcknowledgementReplaysFailureToLaterWaiters() async {
        let gate = CollaborationJoinAcknowledgementGate()

        gate.fail()

        #expect(await gate.wait(timeout: .milliseconds(1)) == false)
    }

    @Test func joinAcknowledgementIgnoresLaterFailureAfterSuccess() async {
        let gate = CollaborationJoinAcknowledgementGate()

        gate.succeed()
        gate.fail()

        #expect(await gate.wait(timeout: .milliseconds(1)))
    }

    @Test func joinAcknowledgementIgnoresLaterSuccessAfterFailure() async {
        let gate = CollaborationJoinAcknowledgementGate()

        gate.fail()
        gate.succeed()

        #expect(await gate.wait(timeout: .milliseconds(1)) == false)
    }

    @Test func joinAcknowledgementTimesOutWithoutRelayJoinedFrame() async {
        let gate = CollaborationJoinAcknowledgementGate()

        let result = await gate.wait(timeout: .milliseconds(1))

        #expect(result == false)
    }

    @Test func joinAcknowledgementTimeoutResultIsStable() async {
        let gate = CollaborationJoinAcknowledgementGate()

        _ = await gate.wait(timeout: .milliseconds(1))
        gate.succeed()

        #expect(await gate.wait(timeout: .milliseconds(1)) == false)
    }
}
