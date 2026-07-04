import Foundation
import Testing

#if canImport(Mosaic_DEV)
@testable import Mosaic_DEV
#elseif canImport(Mosaic)
@testable import Mosaic
#endif

@MainActor
@Suite(.serialized)
struct BrowserMediaPlaybackAudioActivityTests {
    @Test func activeSilentMediaPlaybackBlocksDiscardWithoutAudioGlyph() {
        let panel = BrowserPanel(workspaceId: UUID(), renderInitialNavigation: false)
        defer { panel.close() }

        panel.applyMediaPlaybackReport(frameID: "main", isPlaying: true, isAudible: false)

        #expect(panel.isPlayingMedia)
        #expect(panel.isPlayingAudio == false)
    }

    @Test func audibleMediaPlaybackDrivesAudioGlyphIndependentlyOfDiscardBlocker() {
        let panel = BrowserPanel(workspaceId: UUID(), renderInitialNavigation: false)
        defer { panel.close() }

        panel.applyMediaPlaybackReport(frameID: "main", isPlaying: true, isAudible: true)

        #expect(panel.isPlayingMedia)
        #expect(panel.isPlayingAudio)

        panel.applyMediaPlaybackReport(frameID: "main", isPlaying: true, isAudible: false)

        #expect(panel.isPlayingMedia)
        #expect(panel.isPlayingAudio == false)
    }
}
