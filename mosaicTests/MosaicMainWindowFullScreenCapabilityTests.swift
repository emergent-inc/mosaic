import AppKit
import Testing

#if canImport(Mosaic_DEV)
@testable import Mosaic_DEV
#elseif canImport(Mosaic)
@testable import Mosaic
#endif

@MainActor
@Suite("MosaicMainWindow native fullscreen capability")
struct MosaicMainWindowFullScreenCapabilityTests {
    // mosaic creates its main window programmatically and never loaded fullscreen
    // capability from a nib, so it historically relied on AppKit *implicitly*
    // granting `.fullScreenPrimary` to a resizable, titled window. That implicit
    // grant is not reliable across macOS versions / display arrangements: on
    // macOS 26 (Tahoe) a freshly-created MosaicMainWindow reports an empty
    // collection behavior (`rawValue == 0`) and AppKit does NOT treat it as
    // fullscreen-capable — so `toggleFullScreen(_:)`, ⌃⌘F, and the green
    // traffic-light button all fail to enter a native fullscreen Space (the
    // green button only zooms). See issue #5933.
    //
    // A MosaicMainWindow must therefore *declare* `.fullScreenPrimary` itself so
    // native fullscreen is reachable regardless of the OS's implicit default.
    @Test func mainWindowDeclaresFullScreenPrimaryCapability() {
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

        #expect(
            window.collectionBehavior.contains(.fullScreenPrimary),
            "Main window must declare .fullScreenPrimary so native fullscreen is reachable"
        )
        #expect(
            !window.collectionBehavior.contains(.fullScreenNone),
            "Main window must never carry .fullScreenNone, which suppresses native fullscreen"
        )
    }

    // The capability decision is a pure, screen-agnostic transform so it runs
    // deterministically on CI regardless of the test host's display setup.

    @Test func canonicalBehaviorAddsFullScreenPrimaryToEmptyBehavior() {
        let result = MosaicMainWindow.canonicalCollectionBehavior([])
        #expect(result.contains(.fullScreenPrimary))
        #expect(!result.contains(.fullScreenNone))
    }

    @Test func canonicalBehaviorDropsStaleFullScreenNone() {
        let result = MosaicMainWindow.canonicalCollectionBehavior([.fullScreenNone])
        #expect(result.contains(.fullScreenPrimary))
        #expect(!result.contains(.fullScreenNone))
    }

    @Test func canonicalBehaviorPreservesUnrelatedBehaviorBits() {
        // The window factory may layer `.fullScreenDisallowsTiling` on top when
        // spawning out of an existing fullscreen Space; canonicalization must
        // not clobber that (or any other unrelated bit).
        let base: NSWindow.CollectionBehavior = [.fullScreenDisallowsTiling, .moveToActiveSpace]
        let result = MosaicMainWindow.canonicalCollectionBehavior(base)
        #expect(result.contains(.fullScreenPrimary))
        #expect(result.contains(.fullScreenDisallowsTiling))
        #expect(result.contains(.moveToActiveSpace))
    }

    @Test func canonicalBehaviorIsIdempotent() {
        let once = MosaicMainWindow.canonicalCollectionBehavior([])
        let twice = MosaicMainWindow.canonicalCollectionBehavior(once)
        #expect(once == twice)
    }
}
