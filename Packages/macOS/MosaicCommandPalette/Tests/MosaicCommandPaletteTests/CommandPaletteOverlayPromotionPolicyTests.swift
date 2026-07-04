import Testing
@testable import MosaicCommandPalette

@Suite("CommandPaletteOverlayPromotionPolicy")
struct CommandPaletteOverlayPromotionPolicyTests {
    @Test func promotesOnlyOnHiddenToVisibleTransition() {
        #expect(CommandPaletteOverlayPromotionPolicy(previouslyVisible: false, isVisible: true).shouldPromote)
        #expect(!CommandPaletteOverlayPromotionPolicy(previouslyVisible: true, isVisible: true).shouldPromote)
        #expect(!CommandPaletteOverlayPromotionPolicy(previouslyVisible: false, isVisible: false).shouldPromote)
        #expect(!CommandPaletteOverlayPromotionPolicy(previouslyVisible: true, isVisible: false).shouldPromote)
    }
}
