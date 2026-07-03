import AppKit

private func titlebarDragViewIsVisible(_ view: NSView) -> Bool {
    var current: NSView? = view
    while let candidate = current {
        guard !candidate.isHidden, candidate.alphaValue > 0 else { return false }
        current = candidate.superview
    }
    return true
}

private func titlebarDragWindowPoint(_ windowPoint: NSPoint, isIn view: NSView) -> Bool {
    guard titlebarDragViewIsVisible(view) else { return false }
    let localPoint = view.convert(windowPoint, from: nil)
    let epsilon = max(0.5, 1.0 / max(1.0, view.window?.backingScaleFactor ?? 1.0))
    return view.bounds.insetBy(dx: -epsilon, dy: -epsilon).contains(localPoint)
}

private func titlebarDragPointHitsVisibleControl(
    _ windowPoint: NSPoint,
    in root: NSView
) -> Bool {
    guard titlebarDragViewIsVisible(root) else { return false }
    if root is NSControl, titlebarDragWindowPoint(windowPoint, isIn: root) {
        return true
    }
    for subview in root.subviews where titlebarDragPointHitsVisibleControl(windowPoint, in: subview) {
        return true
    }
    return false
}

@MainActor
func isNativeTitlebarDragGap(
    window: NSWindow,
    locationInWindow: NSPoint
) -> Bool {
    let windowBounds = NSRect(x: 0, y: 0, width: window.frame.width, height: window.frame.height)
    guard windowBounds.contains(locationInWindow),
          locationInWindow.y >= window.contentLayoutRect.maxY else {
        return false
    }

    let standardButtons: [NSWindow.ButtonType] = [
        .closeButton,
        .miniaturizeButton,
        .zoomButton
    ]
    for buttonType in standardButtons {
        guard let button = window.standardWindowButton(buttonType),
              button.window === window,
              titlebarDragWindowPoint(locationInWindow, isIn: button) else { continue }
        return false
    }

    for accessory in window.titlebarAccessoryViewControllers where !accessory.isHidden {
        guard accessory.view.window === window,
              titlebarDragWindowPoint(locationInWindow, isIn: accessory.view) else { continue }
        return false
    }

    if let frameView = window.contentView?.superview,
       titlebarDragPointHitsVisibleControl(locationInWindow, in: frameView) {
        return false
    }

    return true
}

@MainActor
@discardableResult
func performNativeTitlebarGapMouseDown(
    window: NSWindow,
    event: NSEvent
) -> Bool {
    guard event.type == .leftMouseDown,
          event.window === window,
          isNativeTitlebarDragGap(window: window, locationInWindow: event.locationInWindow),
          !isWindowDragSuppressed(window: window) else {
        return false
    }

    if event.clickCount >= 2 {
        let result = handleTitlebarDoubleClick(window: window, behavior: .standardAction)
        if result.consumesEvent {
            return true
        }
    }

    withTemporaryWindowMovableEnabled(window: window) {
        window.performDrag(with: event)
    }
    return true
}

final class TitlebarAccessoryContainerView: NSView {
    static func shouldResolveWindowDragHit(eventType: NSEvent.EventType?) -> Bool {
        eventType == nil || eventType == .leftMouseDown
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        guard Self.shouldResolveWindowDragHit(eventType: NSApp.currentEvent?.type) else {
            return super.hitTest(point)
        }
        return super.hitTest(point) ?? self
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            let result = handleTitlebarDoubleClick(
                window: window,
                behavior: .standardAction
            )
            if result.consumesEvent {
                return
            }
        }

        guard !isWindowDragSuppressed(window: window) else { return }

        if let window {
            withTemporaryWindowMovableEnabled(window: window) {
                window.performDrag(with: event)
            }
        } else {
            super.mouseDown(with: event)
        }
    }
}
