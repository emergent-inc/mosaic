import AppKit
import Testing
import WebKit

#if canImport(Mosaic_DEV)
@testable import Mosaic_DEV
#elseif canImport(Mosaic)
@testable import Mosaic
#endif

@MainActor
@Suite(.serialized)
struct BrowserWindowPortalRegistryNotificationTests {
    private final class CountingContentView: NSView {
        var layoutPassCount = 0

        override func layout() {
            layoutPassCount += 1
            super.layout()
        }
    }

    private func realizeWindowLayout(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        window.displayIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private func advanceAnimations() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    @Test func registryDoesNotNotifyForUnchangedPortalVisibility() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        realizeWindowLayout(window)
        let contentView = try #require(window.contentView)

        let anchor = NSView(frame: NSRect(x: 20, y: 20, width: 180, height: 120))
        contentView.addSubview(anchor)
        let webView = MosaicWebView(frame: .zero, configuration: WKWebViewConfiguration())

        var notificationCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .browserPortalRegistryDidChange,
            object: webView,
            queue: nil
        ) { _ in
            notificationCount += 1
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
            BrowserWindowPortalRegistry.detach(webView: webView)
        }

        BrowserWindowPortalRegistry.bind(webView: webView, to: anchor, visibleInUI: true)
        BrowserWindowPortalRegistry.synchronizeForAnchor(anchor)
        advanceAnimations()
        #expect(notificationCount == 1)

        BrowserWindowPortalRegistry.updateEntryVisibility(for: webView, visibleInUI: true, zPriority: 0)
        #expect(
            notificationCount == 1,
            "Reapplying an unchanged portal visibility snapshot should not wake Workspace layout follow-up"
        )

        BrowserWindowPortalRegistry.updateEntryVisibility(for: webView, visibleInUI: false, zPriority: 0)
        #expect(notificationCount == 2)

        BrowserWindowPortalRegistry.updateEntryVisibility(for: webView, visibleInUI: false, zPriority: 0)
        #expect(
            notificationCount == 2,
            "Repeated hidden-state updates should not post duplicate registry-change notifications"
        )

        let slot = try #require(webView.superview as? WindowBrowserSlotView)
        #expect(!slot.isHidden)

        BrowserWindowPortalRegistry.hide(webView: webView, source: "unitTest")
        advanceAnimations()
        #expect(slot.isHidden)
        #expect(
            notificationCount == 3,
            "A hidden visibility state whose slot still needs presentation sync should notify exactly once"
        )

        BrowserWindowPortalRegistry.hide(webView: webView, source: "unitTest")
        advanceAnimations()
        #expect(
            notificationCount == 3,
            "A repeated hide after state and presentation are already hidden should not notify"
        )
    }

    @Test func unchangedPortalVisibilityDoesNotDriveWorkspaceLayoutFollowUp() throws {
        let contentView = CountingContentView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let window = NSWindow(
            contentRect: contentView.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = contentView
        defer { window.orderOut(nil) }
        realizeWindowLayout(window)
        contentView.layoutPassCount = 0

        let anchor = NSView(frame: NSRect(x: 20, y: 20, width: 180, height: 120))
        contentView.addSubview(anchor)
        let webView = MosaicWebView(frame: .zero, configuration: WKWebViewConfiguration())
        defer { BrowserWindowPortalRegistry.detach(webView: webView) }

        BrowserWindowPortalRegistry.bind(webView: webView, to: anchor, visibleInUI: true)
        BrowserWindowPortalRegistry.synchronizeForAnchor(anchor)
        advanceAnimations()

        let workspace = Workspace()
        let panelId = try #require(workspace.focusedPanelId)
        let panel = try #require(workspace.terminalPanel(for: panelId))
        let layoutObserver = NotificationCenter.default.addObserver(
            forName: .browserPortalRegistryDidChange,
            object: webView,
            queue: nil
        ) { _ in
            MainActor.assumeIsolated {
                contentView.needsLayout = true
                workspace.debugBeginReparentFocusSuppressionForTesting(
                    panel.hostedView,
                    reason: "workspace.browserPortalLayoutHotpathTest"
                )
                workspace.debugAttemptEventDrivenLayoutFollowUpForTesting()
            }
        }
        defer { NotificationCenter.default.removeObserver(layoutObserver) }

        NotificationCenter.default.post(name: .browserPortalRegistryDidChange, object: webView)
        #expect(
            contentView.layoutPassCount == 1,
            "A browser portal registry notification should drive a Workspace layout follow-up pass"
        )

        let layoutCountBeforeNoOpBurst = contentView.layoutPassCount
        for _ in 0..<50 {
            BrowserWindowPortalRegistry.updateEntryVisibility(for: webView, visibleInUI: true, zPriority: 0)
        }
        advanceAnimations()
        #expect(
            contentView.layoutPassCount == layoutCountBeforeNoOpBurst,
            "Reapplying unchanged browser portal visibility snapshots must not force Workspace layout passes"
        )

        BrowserWindowPortalRegistry.updateEntryVisibility(for: webView, visibleInUI: false, zPriority: 0)
        #expect(
            contentView.layoutPassCount == layoutCountBeforeNoOpBurst + 1,
            "A real browser portal visibility change should still wake Workspace layout follow-up"
        )
    }
}

@MainActor
@Suite(.serialized)
struct BrowserWindowPortalRightSidebarOverlapTests {
    private func realizeWindowLayout(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        window.displayIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        window.contentView?.layoutSubtreeIfNeeded()
    }

    /// Regression: the browser portal paints above all SwiftUI content, so a
    /// slot whose anchor frame is stale (e.g. right sidebar just opened but the
    /// pane has not re-laid-out yet) must never draw over the right sidebar
    /// column (Files/Find/Vault). The portal must clamp non-dock slots to the
    /// content area left of the sidebar.
    @Test func browserSlotIsClampedOutOfVisibleRightSidebarColumn() throws {
        let previousAppDelegate = AppDelegate.shared
        let appDelegate = AppDelegate()
        defer { AppDelegate.shared = previousAppDelegate }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        let windowId = UUID()
        window.identifier = NSUserInterfaceItemIdentifier("mosaic.main.\(windowId.uuidString)")
        realizeWindowLayout(window)
        let contentView = try #require(window.contentView)

        let tabManager = TabManager()
        let fileExplorerState = FileExplorerState()
        fileExplorerState.setVisible(true)
        fileExplorerState.width = 100
        appDelegate.registerMainWindowContextForTesting(
            windowId: windowId,
            tabManager: tabManager,
            fileExplorerState: fileExplorerState
        )
        defer { appDelegate.unregisterMainWindowContextForTesting(windowId: windowId) }

        // Stale anchor spanning the full content width, as if the sidebar
        // opened without the pane layout (and portal geometry) catching up.
        let anchor = NSView(frame: contentView.bounds)
        contentView.addSubview(anchor)
        let webView = MosaicWebView(frame: .zero, configuration: WKWebViewConfiguration())
        defer { BrowserWindowPortalRegistry.detach(webView: webView) }

        BrowserWindowPortalRegistry.bind(webView: webView, to: anchor, visibleInUI: true)
        BrowserWindowPortalRegistry.synchronizeForAnchor(anchor)

        let slot = try #require(webView.superview as? WindowBrowserSlotView)
        #expect(!slot.isHidden)
        let sidebarLeadingEdge = contentView.bounds.width - fileExplorerState.width
        #expect(
            slot.frame.maxX <= sidebarLeadingEdge + 0.5,
            "Browser slot must not extend into the right sidebar column (slot maxX \(slot.frame.maxX), sidebar leading edge \(sidebarLeadingEdge))"
        )
    }

}
