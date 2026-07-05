import Foundation
import Testing
import MosaicTerminalCore

@Suite struct TerminalCollaboratorOverlayGeometryTests {
    // MARK: viewportRow (pointer anchor)

    @Test func mapsAbsoluteLineToOwnViewport() {
        // total=100 so bottomRow=99; viewport shows content rows [76, 100).
        // Bottom-most line (rowFromBottom 0) is the last viewport row (23).
        #expect(
            TerminalCollaboratorOverlayGeometry.viewportRow(
                rowFromBottom: 0,
                totalRows: 100,
                scrollOffset: 76,
                viewportRows: 24
            ) == 23
        )
        // The top viewport line (rowFromBottom 23) maps to viewport row 0.
        #expect(
            TerminalCollaboratorOverlayGeometry.viewportRow(
                rowFromBottom: 23,
                totalRows: 100,
                scrollOffset: 76,
                viewportRows: 24
            ) == 0
        )
    }

    @Test func sameAbsoluteLineLandsCorrectlyOnTallerPeer() {
        // Host: 24 rows, scrolled so its top viewport line is rowFromBottom 23.
        // Peer: 48 rows, scrolled to a different offset. The SAME absolute line
        // must resolve to the peer's own viewport row, not the peer's edge.
        let hostTopLineFromBottom: Double = 23
        let peerRow = TerminalCollaboratorOverlayGeometry.viewportRow(
            rowFromBottom: hostTopLineFromBottom,
            totalRows: 100,
            scrollOffset: 52,
            viewportRows: 48
        )
        // bottomRow 99 - 23 - 52 = 24.
        #expect(peerRow == 24)
    }

    @Test func hidesLineScrolledAboveViewport() {
        // rowFromBottom 24 => content row 75, which is above offset 76.
        #expect(
            TerminalCollaboratorOverlayGeometry.viewportRow(
                rowFromBottom: 24,
                totalRows: 100,
                scrollOffset: 76,
                viewportRows: 24
            ) == nil
        )
    }

    @Test func hidesLineScrolledBelowViewport() {
        // Peer scrolled up (offset 0) so the bottom lines are off-viewport.
        #expect(
            TerminalCollaboratorOverlayGeometry.viewportRow(
                rowFromBottom: 0,
                totalRows: 100,
                scrollOffset: 0,
                viewportRows: 24
            ) == nil
        )
    }

    @Test func hidesLineOlderThanLateJoinerScrollback() {
        // A late joiner retained less scrollback (total 50). A host line 60
        // rows from the bottom predates the peer's history and must hide.
        #expect(
            TerminalCollaboratorOverlayGeometry.viewportRow(
                rowFromBottom: 60,
                totalRows: 50,
                scrollOffset: 0,
                viewportRows: 24
            ) == nil
        )
    }

    @Test func preservesFractionalRowForSubCellPrecision() {
        let row = TerminalCollaboratorOverlayGeometry.viewportRow(
            rowFromBottom: 0.5,
            totalRows: 100,
            scrollOffset: 76,
            viewportRows: 24
        )
        #expect(row == 22.5)
    }

    @Test func returnsNilForEmptyViewport() {
        #expect(
            TerminalCollaboratorOverlayGeometry.viewportRow(
                rowFromBottom: 0,
                totalRows: 100,
                scrollOffset: 99,
                viewportRows: 0
            ) == nil
        )
    }

    // MARK: viewportRowBand (selection overlay)

    @Test func mapsFullyVisibleBand() {
        let band = TerminalCollaboratorOverlayGeometry.viewportRowBand(
            rowFromBottom: 5,
            heightRows: 1,
            totalRows: 100,
            scrollOffset: 76,
            viewportRows: 24
        )
        // bottomRow 99 - 5 - 76 = 18.
        #expect(band?.clampedRow == 18)
        #expect(band?.visibleRows == 1)
    }

    @Test func clipsBandOverflowingBottomEdge() {
        // row = 99 - 1 - 76 = 22, height 3 => [22, 25) clipped to 24 => 2 rows.
        let band = TerminalCollaboratorOverlayGeometry.viewportRowBand(
            rowFromBottom: 1,
            heightRows: 3,
            totalRows: 100,
            scrollOffset: 76,
            viewportRows: 24
        )
        #expect(band?.clampedRow == 22)
        #expect(band?.visibleRows == 2)
    }

    @Test func clipsBandStraddlingTopEdge() {
        // row = 99 - 24 - 76 = -1, height 3 => visible portion [0, 2).
        let band = TerminalCollaboratorOverlayGeometry.viewportRowBand(
            rowFromBottom: 24,
            heightRows: 3,
            totalRows: 100,
            scrollOffset: 76,
            viewportRows: 24
        )
        #expect(band?.clampedRow == 0)
        #expect(band?.visibleRows == 2)
    }

    @Test func hidesBandEntirelyAboveViewport() {
        // row = 99 - 30 - 76 = -7, height 1 => entirely above.
        #expect(
            TerminalCollaboratorOverlayGeometry.viewportRowBand(
                rowFromBottom: 30,
                heightRows: 1,
                totalRows: 100,
                scrollOffset: 76,
                viewportRows: 24
            ) == nil
        )
    }

    @Test func hidesBandEntirelyBelowViewport() {
        // Peer scrolled to top (offset 0); bottom selection is off-viewport.
        #expect(
            TerminalCollaboratorOverlayGeometry.viewportRowBand(
                rowFromBottom: 0,
                heightRows: 1,
                totalRows: 100,
                scrollOffset: 0,
                viewportRows: 24
            ) == nil
        )
    }

    @Test func returnsNilForNonPositiveHeight() {
        #expect(
            TerminalCollaboratorOverlayGeometry.viewportRowBand(
                rowFromBottom: 5,
                heightRows: 0,
                totalRows: 100,
                scrollOffset: 76,
                viewportRows: 24
            ) == nil
        )
    }

    // MARK: anchorPoint / gridCell (grid-origin model)

    @Test func anchorPointUsesTopLeftOrigin() {
        // Row 0 sits at the top of the view (AppKit Y == viewHeight); each row
        // steps down by one cell height. Column 0 is at the left edge.
        let top = TerminalCollaboratorOverlayGeometry.anchorPoint(
            row: 0, column: 0, cellWidth: 8, cellHeight: 18, viewHeight: 800
        )
        #expect(top.x == 0)
        #expect(top.y == 800)

        let third = TerminalCollaboratorOverlayGeometry.anchorPoint(
            row: 3, column: 5, cellWidth: 8, cellHeight: 18, viewHeight: 800
        )
        #expect(third.x == 40)
        #expect(third.y == 800 - 54)
    }

    @Test func gridCellInvertsAnchorPoint() {
        // A point captured on one machine must decode back to the exact same
        // fractional cell, so a pointer round-trips to the same text cell.
        for row in stride(from: 0.0, through: 20.0, by: 2.5) {
            for column in stride(from: 0.0, through: 40.0, by: 3.0) {
                let point = TerminalCollaboratorOverlayGeometry.anchorPoint(
                    row: row, column: column, cellWidth: 8, cellHeight: 18, viewHeight: 733
                )
                let cell = TerminalCollaboratorOverlayGeometry.gridCell(
                    x: point.x, y: point.y, cellWidth: 8, cellHeight: 18, viewHeight: 733
                )
                #expect(abs(cell.row - row) < 1e-9)
                #expect(abs(cell.column - column) < 1e-9)
            }
        }
    }

    @Test func gridCellIsSafeForZeroCellSize() {
        let cell = TerminalCollaboratorOverlayGeometry.gridCell(
            x: 10, y: 10, cellWidth: 0, cellHeight: 0, viewHeight: 100
        )
        #expect(cell.row == 0)
        #expect(cell.column == 0)
    }

    // MARK: cross-pane regression (constant vertical offset)

    /// The reported bug: with the SAME locked grid and cell height but two panes
    /// of different pixel height, a collaborator cursor renders at a constant
    /// vertical offset that is present even at the bottom line. With the shared
    /// top-left origin the same viewport row lands the same distance below the
    /// grid top on both panes (zero relative offset). A centered inset - the old
    /// model - would offset it by half the pane-height difference, uniformly at
    /// every row including the bottom, which is exactly what was observed.
    @Test func sharedTopLeftOriginRemovesCrossPaneConstantOffset() {
        let cellHeight = 18.0
        let rows = 40
        // Two panes that are NOT exact multiples of the cell height, differing
        // by a non-cell remainder (the realistic cross-Mac case).
        let hostViewHeight = 731.0
        let viewerViewHeight = 749.0

        // Distance of a rendered viewport row from the grid's top edge, under the
        // shipping (top-left) model, is independent of pane height.
        func distanceFromTop(row: Double, viewHeight: Double) -> Double {
            let anchor = TerminalCollaboratorOverlayGeometry.anchorPoint(
                row: row, column: 0, cellWidth: 8, cellHeight: cellHeight, viewHeight: viewHeight
            )
            return viewHeight - anchor.y
        }

        for row in [0.0, Double(rows) / 2.0, Double(rows - 1)] {
            let host = distanceFromTop(row: row, viewHeight: hostViewHeight)
            let viewer = distanceFromTop(row: row, viewHeight: viewerViewHeight)
            #expect(abs(host - viewer) < 1e-9)
        }

        // Guard rail: the OLD centered model would have drifted by exactly half
        // the pane-height difference at every row (including the bottom), so this
        // documents the regression the fix removes.
        func centeredDistanceFromTop(row: Double, viewHeight: Double) -> Double {
            let inset = max(0, (viewHeight - Double(rows) * cellHeight) / 2)
            let y = viewHeight - inset - row * cellHeight
            return viewHeight - y
        }
        let hostCentered = centeredDistanceFromTop(row: Double(rows - 1), viewHeight: hostViewHeight)
        let viewerCentered = centeredDistanceFromTop(row: Double(rows - 1), viewHeight: viewerViewHeight)
        #expect(abs(hostCentered - viewerCentered) == abs(viewerViewHeight - hostViewHeight) / 2)
    }

    @Test func anchorPointFromNormalizedGridMatchesRowColumn() {
        let padding = TerminalCollaboratorOverlayGeometry.defaultWindowPaddingPoints(backingScaleFactor: 2)
        let normalized = TerminalCollaboratorOverlayGeometry.anchorPointFromNormalizedGrid(
            normalizedX: 0.5,
            normalizedY: 0.25,
            columns: 80,
            rows: 24,
            cellWidth: 8,
            cellHeight: 18,
            viewHeight: 500,
            topPadding: padding.top,
            leftPadding: padding.left
        )
        let expected = TerminalCollaboratorOverlayGeometry.anchorPoint(
            row: 6,
            column: 40,
            cellWidth: 8,
            cellHeight: 18,
            viewHeight: 500,
            topPadding: padding.top,
            leftPadding: padding.left
        )
        #expect(abs(normalized.x - expected.x) < 1e-9)
        #expect(abs(normalized.y - expected.y) < 1e-9)
    }

    // MARK: top-origin identity viewport mapping (offset + flicker fix)

    @Test func prefersBottomMappingWhenBothAtLiveBottom() {
        #expect(
            TerminalCollaboratorOverlayGeometry.prefersViewportBottomMapping(
                senderScrolledToBottom: true,
                receiverScrolledToBottom: true
            ) == true
        )
    }

    @Test func fallsBackToAbsoluteLineWhenEitherScrolledIntoHistory() {
        #expect(
            TerminalCollaboratorOverlayGeometry.prefersViewportBottomMapping(
                senderScrolledToBottom: false,
                receiverScrolledToBottom: true
            ) == false
        )
        #expect(
            TerminalCollaboratorOverlayGeometry.prefersViewportBottomMapping(
                senderScrolledToBottom: true,
                receiverScrolledToBottom: false
            ) == false
        )
    }

    /// When the grids match, the top-origin mapping is the identity of the
    /// sender's own viewport row.
    @Test func topAlignedMappingIsExactWhenGridsMatch() {
        let mapped = TerminalCollaboratorOverlayGeometry.topAlignedViewportRow(
            senderRow: 5,
            receiverViewportRows: 24
        )
        #expect(mapped == 5)
    }

    /// The reported "cursor renders a few lines up/down" bug: both grids are
    /// locked to the SAME 28 rows, but each side's *visible fitted* row count
    /// (derived from local pane height / cell height) differs -- the sender's
    /// pane fits only 25 rows while the receiver shows all 28 (or vice versa).
    /// Content is top-anchored, so mapping through distance-from-viewport-bottom
    /// (`visibleRows - row` on each side) baked the visible-row delta in as a
    /// constant offset. The top-origin mapping is independent of visible fitted
    /// rows and lands on the exact sender row.
    @Test func topAlignedMappingIgnoresVisibleRowMismatch() {
        let senderRow = 10.0
        let senderVisibleRows = 25
        let receiverVisibleRows = 28

        // Old bottom-distance model: sender encodes against ITS visible rows,
        // receiver decodes against ITS visible rows -> off by the delta (3).
        let bottomDistance = Double(senderVisibleRows) - senderRow
        let bottomMappedRow = Double(receiverVisibleRows) - bottomDistance
        #expect(bottomMappedRow == senderRow + 3)

        // Top-origin model (the fix): identity, zero offset.
        let mapped = TerminalCollaboratorOverlayGeometry.topAlignedViewportRow(
            senderRow: senderRow,
            receiverViewportRows: receiverVisibleRows
        )
        #expect(mapped == senderRow)

        // Symmetric direction (sender sees more rows than the receiver) is also
        // the identity, clamped only when off the receiver's visible viewport.
        let mappedReverse = TerminalCollaboratorOverlayGeometry.topAlignedViewportRow(
            senderRow: senderRow,
            receiverViewportRows: senderVisibleRows
        )
        #expect(mappedReverse == senderRow)
    }

    /// A viewer whose visible viewport is shorter than the sender's keeps the
    /// cursor visible, clamped to its bottom edge, instead of hiding it.
    @Test func topAlignedMappingClampsOnShorterViewer() {
        // Sender points at row 38 of the locked 40-row grid; the viewer's pane
        // only fits 24 rows (top-anchored content, bottom clipped).
        let below = TerminalCollaboratorOverlayGeometry.topAlignedViewportRow(
            senderRow: 38,
            receiverViewportRows: 24
        )
        #expect(below == 24)

        // Rows inside the viewer's visible window map to themselves.
        let inside = TerminalCollaboratorOverlayGeometry.topAlignedViewportRow(
            senderRow: 5,
            receiverViewportRows: 24
        )
        #expect(inside == 5)

        // Negative input clamps to the top edge.
        let above = TerminalCollaboratorOverlayGeometry.topAlignedViewportRow(
            senderRow: -2,
            receiverViewportRows: 24
        )
        #expect(above == 0)
    }

    /// The flicker/jitter bug at the behavior level: both peers render the SAME
    /// 24-row grid and view the live bottom, but the two runtimes' scrollback
    /// geometries have drifted (totals are never synchronized between peers and
    /// grow as output streams). The absolute-line mapping bakes that drift in as
    /// a constant vertical offset (the ~5-line drift), while the top-origin
    /// mapping ignores scrollback entirely and lands on the exact sender row.
    @Test func topAlignedMappingAvoidsScrollbackDriftOffset() {
        let senderRow = 5.0

        // Absolute-line path: the sender encodes rowFromBottom from ITS scrollback
        // (total 100, a 19-row viewport at the bottom -> offset 81), and the
        // receiver decodes with ITS own geometry (total 100, offset 76, 24 rows).
        let senderContentRowFromBottom = Double(100 - 1) - senderRow - 81
        let absoluteLineRow = TerminalCollaboratorOverlayGeometry.viewportRow(
            rowFromBottom: senderContentRowFromBottom,
            totalRows: 100,
            scrollOffset: 76,
            viewportRows: 24
        )
        // Drifts 5 rows below the row the sender actually pointed at.
        #expect(absoluteLineRow == senderRow + 5)

        // Top-origin path (the fix): uses the sender's viewport row directly
        // and lands on the exact sender row.
        #expect(
            TerminalCollaboratorOverlayGeometry.prefersViewportBottomMapping(
                senderScrolledToBottom: true,
                receiverScrolledToBottom: true
            ) == true
        )
        let topAlignedRow = TerminalCollaboratorOverlayGeometry.topAlignedViewportRow(
            senderRow: senderRow,
            receiverViewportRows: 24
        )
        #expect(topAlignedRow == senderRow)
    }
}
