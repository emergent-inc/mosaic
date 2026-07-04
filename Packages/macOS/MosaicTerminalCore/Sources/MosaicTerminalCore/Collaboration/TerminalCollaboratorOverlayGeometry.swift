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
}
