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
    func displayNumberStaysStableWhenAnotherRoomEmpties() {
        // Persistent first-seen wiring order: room-1 was wired before room-2.
        let persistentOrder = ["room-1", "room-2"]

        // room-1 has since emptied (its last pane was wired elsewhere) and only
        // room-2 remains populated. Numbering must follow the persistent order,
        // so room-2 keeps display number 2 rather than being relabeled to 1.
        #expect(AgentRoomDisplayPalette.displayNumber(for: "room-2", orderedRoomIDs: persistentOrder) == 2)

        // Contrast with the previous behavior: computing the number over only
        // currently-populated rooms renumbered survivors, which made a wire that
        // merged every pane into one room read "Room 1" instead of "Room 2".
        let populatedOnly = persistentOrder.filter { $0 == "room-2" }
        #expect(AgentRoomDisplayPalette.displayNumber(for: "room-2", orderedRoomIDs: populatedOnly) == 1)
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
