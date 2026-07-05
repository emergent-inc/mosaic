import Testing
@testable import MosaicCollaboration

@Suite
struct AgentRoomDisplayPaletteTests {
    @Test
    func displayNumberFollowsWiringOrderNotAlphabeticalSort() {
        let order = ["room-z-first-wired", "room-a-second-wired"]
        #expect(AgentRoomDisplayPalette.displayNumber(for: "room-z-first-wired", orderedRoomIDs: order) == 1)
        #expect(AgentRoomDisplayPalette.displayNumber(for: "room-a-second-wired", orderedRoomIDs: order) == 2)
    }

    @Test
    func linkedRoomsShareDisplayNumber() {
        let order = ["room-1", "room-2"]
        let first = AgentRoomDisplayPalette.displayNumber(for: "room-1", orderedRoomIDs: order)
        let second = AgentRoomDisplayPalette.displayNumber(for: "room-1", orderedRoomIDs: order)
        #expect(first == second)
        #expect(first == 1)
    }

    @Test
    func paletteIndexTracksDisplayNumber() {
        #expect(AgentRoomDisplayPalette.paletteIndex(forDisplayNumber: 1) == 0)
        #expect(AgentRoomDisplayPalette.paletteIndex(forDisplayNumber: 2) == 1)
        #expect(
            AgentRoomDisplayPalette.paletteIndex(forDisplayNumber: AgentRoomDisplayPalette.accentHexColors.count + 1)
                == 0
        )
    }

    @Test
    func hashPaletteIndexIsStableForRoomID() {
        let once = AgentRoomDisplayPalette.paletteIndex(for: "room-stable")
        let twice = AgentRoomDisplayPalette.paletteIndex(for: "room-stable")
        #expect(once == twice)
        #expect(once >= 0)
        #expect(once < AgentRoomDisplayPalette.accentHexColors.count)
    }
}
