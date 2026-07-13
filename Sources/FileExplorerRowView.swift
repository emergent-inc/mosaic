import AppKit

final class FileExplorerRowView: NSTableRowView {
    /// Pointer-hover state, matching Vault/left-sidebar rows. Tracked on the
    /// row itself so reused rows repair stale state in `updateTrackingAreas`.
    var isRowHovered = false {
        didSet {
            guard oldValue != isRowHovered else { return }
            needsDisplay = true
        }
    }

    private var hoverTrackingArea: NSTrackingArea?

    // With selectionHighlightStyle == .none AppKit no longer owns selection
    // drawing, so make sure selection flips repaint our custom fill.
    override var isSelected: Bool {
        didSet {
            guard oldValue != isSelected else { return }
            needsDisplay = true
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area

        // Row reuse during scroll can strand a hover fill on a row the pointer
        // is no longer over; re-check against the live pointer location.
        if isRowHovered, let window {
            let localPoint = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            if !bounds.contains(localPoint) {
                isRowHovered = false
            }
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isRowHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isRowHovered = false
    }

    /// Draws both selection and hover fills. Selection lives here (not in
    /// `drawSelection(in:)`) because the outline/table views use
    /// `selectionHighlightStyle = .none` to fully opt out of native selection
    /// chrome, and AppKit skips `drawSelection` in that mode.
    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        let style = FileExplorerStyle.current
        if isSelected {
            style.selectionFillColor(focused: isKeyboardFocusActive).setFill()
            rowFillPath(style: style).fill()
        } else if isRowHovered {
            style.hoverColor.setFill()
            rowFillPath(style: style).fill()
        }
    }

    private func rowFillPath(style: FileExplorerStyle) -> NSBezierPath {
        let inset = style.selectionInset
        let insetRect = bounds.insetBy(dx: inset, dy: inset > 0 ? 1 : 0)
        return NSBezierPath(
            roundedRect: insetRect,
            xRadius: style.selectionRadius,
            yRadius: style.selectionRadius
        )
    }

    private var isKeyboardFocusActive: Bool {
        guard let tableView = enclosingTableView else { return false }
        return window?.isKeyWindow == true && window?.firstResponder === tableView
    }

    /// NSOutlineView for the file tree; plain NSTableView for search results.
    private var enclosingTableView: NSTableView? {
        var view = superview
        while let candidate = view {
            if let tableView = candidate as? NSTableView {
                return tableView
            }
            view = candidate.superview
        }
        return nil
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        guard isSelected,
              isKeyboardFocusActive,
              FileExplorerStyle.current.usesEmphasizedSelectionText else {
            return .normal
        }
        return .emphasized
    }
}
