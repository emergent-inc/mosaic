import AppKit
import XCTest

#if canImport(Mosaic_DEV)
@testable import Mosaic_DEV
#elseif canImport(Mosaic)
@testable import Mosaic
#endif

#if DEBUG
@MainActor
final class MosaicMainWindowConstrainFrameTests: XCTestCase {
    // On a display/system sleep→wake, AppKit re-runs its constrain pass over
    // every window and repositions even windows that are already fully
    // on-screen; mosaic never re-asserts its saved frame afterward, so the window
    // creeps each sleep cycle. MosaicMainWindow.constrainFrameRect must leave an
    // on-screen frame untouched so AppKit can no longer move it. A titlebar
    // flush under the menu bar is one such on-screen frame (and an easy,
    // deterministic one to construct), but it is not the only triggering
    // arrangement — see the screen-agnostic helper cases below.
    func testConstrainPreservesOnScreenFrameOverlappingMenuBar() throws {
        guard let screen = NSScreen.main else {
            throw XCTSkip("No screen available for constrainFrameRect regression")
        }
        let window = MosaicMainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer {
            window.orderOut(nil)
            window.close()
        }

        let size = NSSize(width: 800, height: 600)
        // Flush against the very top of the physical screen so the titlebar
        // overlaps the menu bar — one on-screen placement AppKit's default
        // constrain pass would push downward.
        let proposed = NSRect(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )

        let constrained = window.constrainFrameRect(proposed, to: screen)

        XCTAssertEqual(constrained.origin.x, proposed.origin.x, accuracy: 0.5)
        XCTAssertEqual(constrained.origin.y, proposed.origin.y, accuracy: 0.5)
        XCTAssertEqual(constrained.size.width, proposed.size.width, accuracy: 0.5)
        XCTAssertEqual(constrained.size.height, proposed.size.height, accuracy: 0.5)
    }

    // The decision helper is screen-agnostic, so these cases run deterministically
    // on CI regardless of the test host's display configuration.

    func testPreservesFrameFullyInsideVisibleArea() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NSRect(x: 100, y: 100, width: 800, height: 600)
        XCTAssertTrue(
            MosaicMainWindow.shouldPreserveFrameDuringConstrain(frame, visibleFrames: [visible])
        )
    }

    func testPreservesFrameWhoseTitlebarOverlapsMenuBarBand() {
        // The visible area excludes a 37pt menu-bar band at the top; the window's
        // titlebar pokes into it — the placement AppKit would otherwise push down.
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 863)
        let frame = NSRect(x: 320, y: 263, width: 800, height: 637) // maxY 900 > 863
        XCTAssertTrue(
            MosaicMainWindow.shouldPreserveFrameDuringConstrain(frame, visibleFrames: [visible])
        )
    }

    func testDoesNotPreserveFrameStrandedOffScreen() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NSRect(x: 3000, y: 2000, width: 800, height: 600)
        XCTAssertFalse(
            MosaicMainWindow.shouldPreserveFrameDuringConstrain(frame, visibleFrames: [visible])
        )
    }

    func testDoesNotPreserveBarelyPeekingFrame() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
        // Only ~20pt of the window overlaps the bottom-left corner — not grabbable.
        let frame = NSRect(x: -780, y: -580, width: 800, height: 600)
        XCTAssertFalse(
            MosaicMainWindow.shouldPreserveFrameDuringConstrain(frame, visibleFrames: [visible])
        )
    }

    func testDoesNotPreserveWhenNoScreensAvailable() {
        let frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertFalse(
            MosaicMainWindow.shouldPreserveFrameDuringConstrain(frame, visibleFrames: [])
        )
    }
}
#endif
