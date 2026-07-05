import Foundation

/// Maps a collaborator's overlay anchor from a host-independent, absolute
/// scrollback coordinate into the local viewport.
///
/// Collaboration terminals are not pixel mirrors: each participant runs its own
/// Ghostty instance fed the same PTY bytes. To make the host's mouse pointer and
/// text highlight land on the exact same text cell on every peer, overlays are
/// anchored to an absolute scrollback line expressed *bottom-relative*
/// (`rowFromBottom`) rather than to a viewport row. Each side converts that
/// absolute line into its own viewport using its own scrollback geometry, so the
/// mapping stays correct across differing window heights and independent scroll
/// positions.
///
/// This is only valid when both sides number lines identically, which requires
/// the mirror grid width to be locked to the host's column count (otherwise the
/// same bytes wrap differently and an absolute line points at different text).
public enum TerminalCollaboratorOverlayGeometry {
    /// Converts an absolute scrollback line (rows-from-bottom) into a local
    /// viewport row using this side's own scrollback geometry.
    ///
    /// The line is `bottomRow - rowFromBottom` in content space, where
    /// `bottomRow = totalRows - 1`; subtracting the viewport scroll offset yields
    /// the viewport row (0 = top of the visible viewport).
    ///
    /// - Parameters:
    ///   - rowFromBottom: The absolute line's distance from the bottom of
    ///     scrollback, in rows (0 = bottom-most line). Fractional values are
    ///     preserved for sub-cell pointer precision.
    ///   - totalRows: This side's total scrollback height, in rows.
    ///   - scrollOffset: This side's viewport offset from the top of scrollback,
    ///     in rows.
    ///   - viewportRows: This side's visible viewport height, in rows.
    /// - Returns: The viewport row, or `nil` when the line is outside the visible
    ///   viewport (so the caller hides the overlay instead of clamping it to an
    ///   edge).
    public static func viewportRow(
        rowFromBottom: Double,
        totalRows: UInt64,
        scrollOffset: UInt64,
        viewportRows: Int
    ) -> Double? {
        guard viewportRows > 0 else { return nil }
        let bottomRow = Double(max(totalRows, 1)) - 1
        let viewportRow = bottomRow - rowFromBottom - Double(scrollOffset)
        guard viewportRow >= 0, viewportRow < Double(viewportRows) else { return nil }
        return viewportRow
    }

    /// Converts an absolute selection band (its top edge as rows-from-bottom plus
    /// a row height) into the visible portion within the local viewport.
    ///
    /// Unlike ``viewportRow(rowFromBottom:totalRows:scrollOffset:viewportRows:)``
    /// this keeps bands that are only partially visible, clipping them to the
    /// viewport, and returns `nil` only when the band is entirely off-viewport.
    ///
    /// - Parameters:
    ///   - rowFromBottom: The band's top edge as a distance from the bottom of
    ///     scrollback, in rows.
    ///   - heightRows: The band height, in rows.
    ///   - totalRows: This side's total scrollback height, in rows.
    ///   - scrollOffset: This side's viewport offset from the top of scrollback,
    ///     in rows.
    ///   - viewportRows: This side's visible viewport height, in rows.
    /// - Returns: The clipped top row (0 = top of viewport) and the number of
    ///   visible rows, or `nil` when the band is entirely outside the viewport.
    public static func viewportRowBand(
        rowFromBottom: Double,
        heightRows: Double,
        totalRows: UInt64,
        scrollOffset: UInt64,
        viewportRows: Int
    ) -> (clampedRow: Double, visibleRows: Double)? {
        guard viewportRows > 0, heightRows > 0 else { return nil }
        let bottomRow = Double(max(totalRows, 1)) - 1
        let row = bottomRow - rowFromBottom - Double(scrollOffset)
        let viewportRowCount = Double(viewportRows)
        guard row + heightRows > 0, row < viewportRowCount else { return nil }
        let clampedRow = max(row, 0)
        let visibleRows = min(row + heightRows, viewportRowCount) - clampedRow
        guard visibleRows > 0 else { return nil }
        return (clampedRow, visibleRows)
    }

    /// Decides whether a collaborator pointer sent in the `terminalContentBottom`
    /// coordinate space should use the top-origin identity mapping (see
    /// ``topAlignedViewportRow(senderRow:receiverViewportRows:)``) instead of
    /// being routed through the absolute scrollback line
    /// (`contentRowFromBottom`).
    ///
    /// The identity mapping is preferred whenever both peers are viewing the
    /// live bottom of scrollback. The mirror lock pins both grids to the exact
    /// same rows x columns, and Ghostty anchors content at the TOP-LEFT of the
    /// surface, so the sender's top-origin viewport row IS the receiver's
    /// viewport row for the same text cell. Crucially this is independent of
    /// each side's *visible fitted* row count (which is derived from the local
    /// pane height and can differ from the locked grid via letterboxing or
    /// clipping — mapping through a bottom-of-viewport distance baked that
    /// visible-row delta in as a constant vertical offset). It also has no
    /// dependency on either side's never-synchronized, continuously-growing
    /// scrollback total, so a stationary pointer neither jitters nor flickers.
    ///
    /// Only once a peer scrolls into history does the shared-content assumption
    /// stop holding; then this returns `false` and the caller falls back to
    /// ``viewportRow(rowFromBottom:totalRows:scrollOffset:viewportRows:)``.
    ///
    /// - Parameters:
    ///   - senderScrolledToBottom: Whether the sender was at the live scrollback
    ///     bottom when the pointer was captured. Treat a missing wire value
    ///     (older peer) as `false` so those peers keep the absolute-line path.
    ///   - receiverScrolledToBottom: Whether this side is at the live scrollback
    ///     bottom now.
    /// - Returns: `true` to use the top-origin identity viewport mapping.
    public static func prefersViewportBottomMapping(
        senderScrolledToBottom: Bool,
        receiverScrolledToBottom: Bool
    ) -> Bool {
        senderScrolledToBottom && receiverScrolledToBottom
    }

    /// Maps a sender's top-origin viewport row onto this side's viewport row.
    ///
    /// Because the mirror grid is locked to identical dimensions and Ghostty
    /// anchors content at the top-left, this is the identity mapping, clamped
    /// into the local visible viewport so a viewer whose visible grid is shorter
    /// than the sender's keeps the collaborator cursor visible (pinned to the
    /// bottom edge when the sender points below the viewer's clipped window)
    /// rather than hiding it.
    ///
    /// - Parameters:
    ///   - senderRow: The sender's viewport row (0 = top), fractional for
    ///     sub-cell precision.
    ///   - receiverViewportRows: This side's visible viewport height, in rows.
    /// - Returns: The local viewport row (0 = top), clamped to
    ///   `0...receiverViewportRows`.
    public static func topAlignedViewportRow(
        senderRow: Double,
        receiverViewportRows: Int
    ) -> Double {
        let rows = Double(max(receiverViewportRows, 0))
        return min(max(senderRow, 0), rows)
    }

    /// Ghostty's default `window-padding-x/y` top-left value (2) scaled to points
    /// for the current backing scale, matching `Surface.scaledPadding` in the
    /// Ghostty fork (`floor(padding * dpi / 72) / scale`).
    public static func defaultWindowPaddingPoints(backingScaleFactor: Double) -> (top: Double, left: Double) {
        let scale = max(backingScaleFactor, 1)
        let xDpi = 96.0 * scale
        let yDpi = 96.0 * scale
        return (
            top: floor(2.0 * yDpi / 72.0) / scale,
            left: floor(2.0 * xDpi / 72.0) / scale
        )
    }

    /// Converts a fractional grid cell (viewport row/column, `(0, 0)` = the
    /// top-left cell) into a view-local AppKit point (flipped Y, origin at the
    /// bottom-left of the host view).
    ///
    /// Ghostty renders the terminal grid flush to the TOP-LEFT of its surface
    /// (after explicit window padding) and pushes any leftover space to the
    /// bottom-right when `window-padding-balance = false`.
    ///
    /// - Parameters:
    ///   - row: The viewport row (0 = top), fractional for sub-cell precision.
    ///   - column: The viewport column (0 = left), fractional.
    ///   - cellWidth: The cell width in points.
    ///   - cellHeight: The cell height in points.
    ///   - viewHeight: The host view height in points.
    ///   - topPadding: Ghostty's top window padding in points.
    ///   - leftPadding: Ghostty's left window padding in points.
    /// - Returns: The AppKit point of the cell's top-left, in view coordinates.
    public static func anchorPoint(
        row: Double,
        column: Double,
        cellWidth: Double,
        cellHeight: Double,
        viewHeight: Double,
        topPadding: Double = 0,
        leftPadding: Double = 0
    ) -> (x: Double, y: Double) {
        (
            x: leftPadding + column * cellWidth,
            y: viewHeight - topPadding - row * cellHeight
        )
    }

    /// Inverse of ``anchorPoint(row:column:cellWidth:cellHeight:viewHeight:topPadding:leftPadding:)``.
    public static func gridCell(
        x: Double,
        y: Double,
        cellWidth: Double,
        cellHeight: Double,
        viewHeight: Double,
        topPadding: Double = 0,
        leftPadding: Double = 0
    ) -> (row: Double, column: Double) {
        guard cellWidth > 0, cellHeight > 0 else { return (0, 0) }
        return (
            row: (viewHeight - y - topPadding) / cellHeight,
            column: (x - leftPadding) / cellWidth
        )
    }

    /// Renders a collaborator pointer from grid-normalized fractions (the values
    /// sent on the wire as `x`/`y` within the terminal grid area).
    public static func anchorPointFromNormalizedGrid(
        normalizedX: Double,
        normalizedY: Double,
        columns: Int,
        rows: Int,
        cellWidth: Double,
        cellHeight: Double,
        viewHeight: Double,
        topPadding: Double = 0,
        leftPadding: Double = 0
    ) -> (x: Double, y: Double) {
        let gridWidth = Double(max(columns, 1)) * cellWidth
        let gridHeight = Double(max(rows, 1)) * cellHeight
        let clampedX = min(max(normalizedX, 0), 1)
        let clampedY = min(max(normalizedY, 0), 1)
        return (
            x: leftPadding + clampedX * gridWidth,
            y: viewHeight - topPadding - clampedY * gridHeight
        )
    }
}
