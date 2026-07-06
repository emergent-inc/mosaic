@preconcurrency import XCTest
import MosaicTerminal
import MosaicTerminalCore
import AppKit

#if canImport(Mosaic_DEV)
@testable import Mosaic_DEV
#elseif canImport(Mosaic)
@testable import Mosaic
#endif

/// Regression coverage for collaboration viewer keyboard input.
///
/// A remote viewer's mirror surface is mode-synchronized to the host surface, so
/// it Kitty-encodes keystrokes (e.g. Cmd+Z -> `ESC[122;9u`, Option+Left ->
/// `ESC[1;3D`) into exactly the bytes the running program expects. The host must
/// forward those bytes to the PTY verbatim. The shared socket-input grammar used
/// by `sendInput`/`sendInputResult` instead consumes the leading `ESC` as an
/// Escape key press and leaks the remainder as literal text, which is why
/// collaboration input goes through the dedicated committed-text path.
@MainActor
final class CollaborationTerminalInputRegressionTests: XCTestCase {
    /// Cmd+Z under the Kitty keyboard protocol.
    private let cmdZKitty = "\u{1B}[122;9u"
    /// Option+Left (word motion): a modified cursor sequence.
    private let optionLeft = "\u{1B}[1;3D"

    /// Documents the bug: the shared socket grammar splits a Kitty sequence into
    /// an Escape key event plus literal text, so it cannot be used for
    /// collaboration input.
    func testSharedSocketGrammarSplitsKittySequence() {
        let panel = TerminalPanel(workspaceId: UUID())
        panel.surface.releaseSurfaceForTesting()

        XCTAssertTrue(panel.surface.sendInput(cmdZKitty))

        let pending = panel.surface.debugPendingSocketInputForTesting()
        XCTAssertGreaterThan(
            pending.keyEvents,
            0,
            "Precondition: the socket grammar splits the Kitty Cmd+Z sequence into an Escape key event, mangling the input."
        )
    }

    func testCollaborationInputDeliversKittyCmdZVerbatim() {
        let panel = TerminalPanel(workspaceId: UUID())
        panel.surface.releaseSurfaceForTesting()

        let data = Data(cmdZKitty.utf8)
        XCTAssertEqual(panel.surface.sendCollaborationInputResult(data), .queued)

        let pending = panel.surface.debugPendingSocketInputForTesting()
        XCTAssertEqual(
            pending.keyEvents,
            0,
            "Kitty Cmd+Z must not be split into an Escape key event."
        )
        XCTAssertEqual(
            pending.inputTextItems,
            1,
            "Kitty Cmd+Z must be delivered as one committed-text payload."
        )
        XCTAssertEqual(
            pending.bytes,
            data.count,
            "The full Kitty Cmd+Z sequence must reach the PTY verbatim."
        )
    }

    func testCollaborationInputDeliversOptionLeftVerbatim() {
        let panel = TerminalPanel(workspaceId: UUID())
        panel.surface.releaseSurfaceForTesting()

        let data = Data(optionLeft.utf8)
        XCTAssertEqual(panel.surface.sendCollaborationInputResult(data), .queued)

        let pending = panel.surface.debugPendingSocketInputForTesting()
        XCTAssertEqual(
            pending.keyEvents,
            0,
            "Option+Left must not be split into an Escape key event plus literal text."
        )
        XCTAssertEqual(
            pending.inputTextItems,
            1,
            "Option+Left must be delivered as one committed-text payload."
        )
        XCTAssertEqual(
            pending.bytes,
            data.count,
            "The full Option+Left sequence must reach the PTY verbatim."
        )
    }

    /// Ctrl combinations must reach kitty-mode host programs in Kitty form, just
    /// like every other modified key. The collaboration input filter previously
    /// downgraded Ctrl Kitty CSI-`u` sequences to legacy control bytes (e.g.
    /// Ctrl+C -> 0x03); now that host input is written to the PTY verbatim, that
    /// downgrade is removed.
    func testCollaborationFilterPassesCtrlKittySequenceVerbatim() {
        // Ctrl+C under the Kitty keyboard protocol: ESC [ 99 ; 5 u.
        let ctrlC = Data("\u{1B}[99;5u".utf8)

        let filtered = CollaborationRuntime.debugFilteredCollaborationInputForTesting(ctrlC)

        XCTAssertEqual(
            filtered,
            ctrlC,
            "Ctrl+C Kitty sequence must pass through verbatim instead of being downgraded to the legacy 0x03 control byte."
        )
    }

    /// Removing the Ctrl downgrade must not weaken the filter's other job:
    /// terminal query responses the mirror surface emits still must not reach the
    /// host PTY.
    func testCollaborationFilterStillDropsTerminalReports() {
        // A cursor-position report: ESC [ 10 ; 20 R.
        let cursorReport = Data("\u{1B}[10;20R".utf8)

        let filtered = CollaborationRuntime.debugFilteredCollaborationInputForTesting(cursorReport)

        XCTAssertNil(
            filtered,
            "Terminal-generated reports must still be dropped so they never reach the host program."
        )
    }
}
