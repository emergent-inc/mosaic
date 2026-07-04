import Foundation
import Testing

#if canImport(Mosaic_DEV)
@testable import Mosaic_DEV
#elseif canImport(Mosaic)
@testable import Mosaic
#endif

/// The collaboration relay silently drops websocket messages over 1 MiB, so
/// the terminal share seed must shrink its scrollback until the encoded frame
/// fits (https://github.com/emergent-inc/mosaic — shared terminal shows a
/// black pane to viewers until the host presses Enter).
@Suite struct CollaborationTerminalRenderGridSeedLimiterTests {
    /// Simulates an encoder whose payload grows with requested scrollback:
    /// a fixed screen cost plus a per-line cost.
    private func payload(screenBytes: Int, bytesPerLine: Int) -> (Int) -> Data? {
        { lines in Data(count: screenBytes + lines * bytesPerLine) }
    }

    @Test func smallSeedSendsAtFullScrollback() {
        var requested: [Int] = []
        let data = CollaborationTerminalRenderGridSeedLimiter.firstPayloadUnderLimit(
            startingScrollbackLines: 10_000,
            limit: 1_000
        ) { lines in
            requested.append(lines)
            return Data(count: 500)
        }
        #expect(data?.count == 500)
        #expect(requested == [10_000])
    }

    @Test func oversizedSeedHalvesScrollbackUntilItFits() {
        // 10k lines at 200 bytes each = ~2 MB, well over the 768 KiB cap.
        var requested: [Int] = []
        let make = payload(screenBytes: 4_096, bytesPerLine: 200)
        let data = CollaborationTerminalRenderGridSeedLimiter.firstPayloadUnderLimit(
            startingScrollbackLines: 10_000
        ) { lines in
            requested.append(lines)
            return make(lines)
        }
        let limit = CollaborationTerminalRenderGridSeedLimiter.maxWireBytes
        #expect(data != nil)
        #expect((data?.count ?? .max) <= limit)
        #expect(requested == [10_000, 5_000, 2_500])
    }

    @Test func screenOnlyFrameIsSentEvenWhenOverLimit() {
        // Nothing smaller than a screen-only frame exists, so the limiter
        // must still return it rather than dropping the seed entirely.
        let data = CollaborationTerminalRenderGridSeedLimiter.firstPayloadUnderLimit(
            startingScrollbackLines: 4,
            limit: 10
        ) { lines in Data(count: 100 + lines) }
        #expect(data?.count == 100)
    }

    @Test func reachesZeroFromOneLine() {
        var requested: [Int] = []
        _ = CollaborationTerminalRenderGridSeedLimiter.firstPayloadUnderLimit(
            startingScrollbackLines: 1,
            limit: 10
        ) { lines in
            requested.append(lines)
            return Data(count: 100 + lines)
        }
        #expect(requested == [1, 0])
    }

    @Test func unavailableFrameReturnsNil() {
        let data = CollaborationTerminalRenderGridSeedLimiter.firstPayloadUnderLimit(
            startingScrollbackLines: 10_000
        ) { _ in nil }
        #expect(data == nil)
    }

    @Test func negativeScrollbackClampsToScreenOnly() {
        var requested: [Int] = []
        _ = CollaborationTerminalRenderGridSeedLimiter.firstPayloadUnderLimit(
            startingScrollbackLines: -5,
            limit: 10
        ) { lines in
            requested.append(lines)
            return Data(count: 100)
        }
        #expect(requested == [0])
    }
}
