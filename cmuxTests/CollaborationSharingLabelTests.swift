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

    @Test(arguments: ["Sign In", "Join Session", "Copy Code"])
    func collaborationAccentAlertButtonsUseBlackTitleTint(title: String) throws {
        let button = NSButton(title: title, target: nil, action: nil)

        applyCollaborationAccentAlertButtonTitleStyle(button)

        #expect(button.contentTintColor == .black)

        let foreground = try #require(
            button.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        )
        #expect(foreground == .black)
    }
}
