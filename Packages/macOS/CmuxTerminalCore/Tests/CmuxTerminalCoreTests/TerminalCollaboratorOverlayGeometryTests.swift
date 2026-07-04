import Foundation
import Testing
import CmuxTerminalCore

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
}
