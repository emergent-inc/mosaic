import AppKit
import SwiftUI
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite("Titlebar interactive controls")
struct TitlebarInteractiveControlTests {
    private final class RecordingDragWindow: NSWindow {
        var performDragCallCount = 0
        var isMovableDuringPerformDrag: Bool?

        override func performDrag(with event: NSEvent) {
            performDragCallCount += 1
            isMovableDuringPerformDrag = isMovable
        }
    }

    private static func makeLeftMouseDownEvent(location: NSPoint, window: NSWindow, clickCount: Int = 1) -> NSEvent {
        guard let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: clickCount,
            pressure: 1.0
        ) else {
            fatalError("Expected to create titlebar accessory mouse-down event")
        }
        return event
    }

    private static func attachedTitlebarAccessoryContainers(
        in window: NSWindow
    ) -> [TitlebarAccessoryContainerView] {
        window.titlebarAccessoryViewControllers.compactMap {
            $0.isHidden ? nil : $0.view as? TitlebarAccessoryContainerView
        }
    }

    private static func windowFrame(of container: TitlebarAccessoryContainerView) -> NSRect {
        container.convert(container.bounds, to: nil)
    }

    /// `titlebarInteractiveControl()` registers the control's region (without
    /// reparenting it). The explicit `WindowDragHandleView` must yield to that
    /// registered region so a click toggles the control instead of starting a
    /// window drag/resize, while empty titlebar chrome stays draggable.
    @Test func dragHandleYieldsToRegisteredTitlebarControl() {
        _ = NSApplication.shared

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 48),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 48))
        window.contentView = container

        let dragHandle = NSView(frame: container.bounds)
        container.addSubview(dragHandle)

        // Mirror how `titlebarInteractiveControl()` marks a control: a transparent
        // region view sized to the control that registers itself with the registry.
        let region = TitlebarInteractiveControlRegion.RegisteredView(
            frame: NSRect(x: 12, y: 14, width: 24, height: 24)
        )
        container.addSubview(region)

        let buttonPoint = NSPoint(x: region.frame.midX, y: region.frame.midY)
        #expect(
            !windowDragHandleShouldCaptureHit(
                dragHandle.convert(buttonPoint, from: nil),
                in: dragHandle,
                eventType: .leftMouseDown,
                eventWindow: window
            ),
            "A registered titlebar control region must block explicit titlebar dragging so its click reaches the control."
        )

        #expect(
            windowDragHandleShouldCaptureHit(
                NSPoint(x: 220, y: 24),
                in: dragHandle,
                eventType: .leftMouseDown,
                eventWindow: window
            ),
            "Empty titlebar chrome outside any interactive control should remain draggable."
        )
    }

    /// A registered titlebar control region must read as a control hit so the
    /// synthetic titlebar double-click (zoom/minimize) is suppressed over it,
    /// while empty chrome still triggers the standard double-click action.
    @Test func registeredTitlebarControlSuppressesSyntheticDoubleClick() {
        _ = NSApplication.shared

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 48),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 48))
        window.contentView = container

        let region = TitlebarInteractiveControlRegion.RegisteredView(
            frame: NSRect(x: 12, y: 14, width: 24, height: 24)
        )
        container.addSubview(region)

        let insideControl = NSPoint(x: region.frame.midX, y: region.frame.midY)
        #expect(
            minimalModeTitlebarDoubleClickShouldDefer(window: window, locationInWindow: insideControl),
            "A double-click on a titlebarInteractiveControl must register as a control hit so the synthetic titlebar double-click (zoom/minimize) is suppressed."
        )

        let emptyTitlebar = NSPoint(x: 220, y: 24)
        #expect(
            !minimalModeTitlebarDoubleClickShouldDefer(window: window, locationInWindow: emptyTitlebar),
            "Empty titlebar chrome away from any interactive control must still trigger the standard titlebar double-click action."
        )
    }

    /// The region marker must never intercept clicks itself; it is a registry
    /// marker only, so the control it backs keeps receiving its own mouse-downs.
    @Test func regionMarkerIsTransparentToHitTesting() {
        let region = TitlebarInteractiveControlRegion.RegisteredView(
            frame: NSRect(x: 0, y: 0, width: 24, height: 24)
        )
        #expect(
            region.hitTest(NSPoint(x: 12, y: 12)) == nil,
            "The interactive-control region marker must be transparent to hit-testing so the hosted control receives clicks."
        )
        #expect(
            !region.mouseDownCanMoveWindow,
            "The region marker must not let a stray mouse-down move the window."
        )
    }

    @Test func emptyAccessoryChromeUsesExplicitWindowDragPath() {
        _ = NSApplication.shared

        let window = RecordingDragWindow(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 44),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        window.isMovable = false

        let controller = TitlebarControlsAccessoryViewController(notificationStore: TerminalNotificationStore.shared, settingsRuntime: nil)
        let container = controller.view
        container.frame = NSRect(x: 0, y: 0, width: 180, height: 44)
        window.contentView = container

        let emptyTopRightPoint = NSPoint(x: container.bounds.maxX - 4, y: container.bounds.maxY - 4)
        guard let hitView = container.hitTest(emptyTopRightPoint) else {
            Issue.record("Expected empty titlebar accessory chrome to receive the drag mouse-down")
            return
        }

        #expect(hitView === container)
        #expect(
            !hitView.mouseDownCanMoveWindow,
            "Empty accessory chrome must not rely on native AppKit window dragging because main windows are normally immovable."
        )

        let event = Self.makeLeftMouseDownEvent(location: emptyTopRightPoint, window: window)
        hitView.mouseDown(with: event)

        #expect(window.performDragCallCount == 1)
        #expect(
            window.isMovableDuringPerformDrag == true,
            "Empty accessory chrome should temporarily enable main-window movement before calling performDrag(with:)."
        )
        #expect(
            !window.isMovable,
            "Explicit accessory dragging must restore the main window to its normal immovable state."
        )
    }

    @Test func accessoryControlsRemainNonDraggable() {
        _ = NSApplication.shared

        let controller = TitlebarControlsAccessoryViewController(notificationStore: TerminalNotificationStore.shared, settingsRuntime: nil)
        let container = controller.view
        container.frame = NSRect(x: 0, y: 0, width: 180, height: 44)

        let button = NSButton(frame: NSRect(x: 8, y: 8, width: 24, height: 24))
        button.isBordered = false
        container.addSubview(button)

        guard let hitView = container.hitTest(NSPoint(x: 20, y: 20)) else {
            Issue.record("Expected the accessory button to receive its own hit")
            return
        }

        #expect(hitView === button)
        #expect(
            !hitView.mouseDownCanMoveWindow,
            "Actual titlebar controls must keep owning clicks instead of starting a window drag."
        )
    }

    @Test func registeredSwiftUIAccessoryControlRegionIsNonDraggable() {
        _ = NSApplication.shared

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 44),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }

        let container = TitlebarAccessoryContainerView(frame: NSRect(x: 0, y: 0, width: 180, height: 44))
        window.contentView = container

        let hostingView = NonDraggableHostingView(rootView: Color.clear)
        hostingView.frame = container.bounds
        container.addSubview(hostingView)

        let region = TitlebarInteractiveControlRegion.RegisteredView(
            frame: NSRect(x: 130, y: 8, width: 24, height: 24)
        )
        hostingView.addSubview(region)

        guard let hitView = container.hitTest(NSPoint(x: region.frame.midX, y: region.frame.midY)) else {
            Issue.record("Expected registered SwiftUI titlebar control chrome to receive a non-draggable hit")
            return
        }
        #expect(
            !hitView.mouseDownCanMoveWindow,
            "Registered SwiftUI titlebar controls must not degrade into hosting-view drag hits."
        )
    }

    @Test func nativeTitlebarGapUsesExplicitWindowDragPath() {
        _ = NSApplication.shared

        let window = RecordingDragWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_020, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        window.identifier = NSUserInterfaceItemIdentifier("cmux.main.titlebar-gap-test")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
        configureCmuxMainWindowDragBehavior(window)

        let controller = UpdateTitlebarAccessoryController(updateLog: UpdateLogStore(), settingsRuntime: nil)
        controller.attach(to: window)

        let containers = Self.attachedTitlebarAccessoryContainers(in: window)
        #expect(
            containers.count >= 2,
            "The real main-window accessory controller should install both left controls and the right logo."
        )
        let frames = containers
            .map(Self.windowFrame(of:))
            .sorted { $0.minX < $1.minX }
        guard let leftFrame = frames.first,
              let rightFrame = frames.last,
              leftFrame.maxX < rightFrame.minX else {
            Issue.record("Expected distinct left and right titlebar accessories with a native titlebar gap between them")
            return
        }

        let titlebarY = (leftFrame.midY + rightFrame.midY) / 2
        let samplePoints = stride(from: leftFrame.maxX + 12, through: rightFrame.minX - 12, by: 80)
            .map { NSPoint(x: $0, y: titlebarY) }
        #expect(!samplePoints.isEmpty, "Expected to sample at least one point in the native titlebar gap")

        for (index, point) in samplePoints.enumerated() {
            #expect(
                isNativeTitlebarDragGap(window: window, locationInWindow: point),
                "Expected sampled point \(point) to be classified as empty native titlebar gap."
            )
            let handled = performNativeTitlebarGapMouseDown(
                window: window,
                event: Self.makeLeftMouseDownEvent(location: point, window: window)
            )
            #expect(handled, "Expected native titlebar gap point \(point) to start explicit window dragging.")
            #expect(window.performDragCallCount == index + 1)
            #expect(
                window.isMovableDuringPerformDrag == true,
                "Native titlebar gap dragging should temporarily enable main-window movement before performDrag(with:)."
            )
            #expect(!window.isMovable)
        }

    }

    @Test func attachedRightLogoAccessoryUsesExplicitWindowDragPath() {
        _ = NSApplication.shared

        let window = RecordingDragWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        window.identifier = NSUserInterfaceItemIdentifier("cmux.main.titlebar-control-test")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
        configureCmuxMainWindowDragBehavior(window)

        let controller = UpdateTitlebarAccessoryController(updateLog: UpdateLogStore(), settingsRuntime: nil)
        controller.attach(to: window)

        let controlContainers = Self.attachedTitlebarAccessoryContainers(in: window)
        guard let logoContainer = controlContainers.max(by: {
            Self.windowFrame(of: $0).maxX < Self.windowFrame(of: $1).maxX
        }) else {
            Issue.record("Expected the right logo accessory to be installed")
            return
        }

        let localPoint = NSPoint(x: logoContainer.bounds.midX, y: logoContainer.bounds.midY)
        let controlPoint = logoContainer.convert(localPoint, to: nil)
        #expect(
            !isNativeTitlebarDragGap(window: window, locationInWindow: controlPoint),
            "The native gap handler must not claim points owned by the right logo accessory."
        )
        guard let hitView = logoContainer.hitTest(localPoint) else {
            Issue.record("Expected the right logo accessory to receive empty titlebar drag hits")
            return
        }
        #expect(
            hitView === logoContainer,
            "The decorative right logo should be transparent to hit-testing so its accessory container owns window dragging."
        )
        hitView.mouseDown(with: Self.makeLeftMouseDownEvent(location: controlPoint, window: window))
        #expect(window.performDragCallCount == 1)
        #expect(window.isMovableDuringPerformDrag == true)
        #expect(!window.isMovable)
    }
}
