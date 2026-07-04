import Testing
@testable import MosaicCollaboration

@Suite
struct AgentRoomSelectionTests {
    @Test
    func wireBetweenTwoUnroomedSurfacesCreatesFreshRoomInsteadOfUsingLatest() {
        let selected = AgentRoomSelection.roomIDForWire(
            sourceRoomID: nil,
            targetRoomID: nil,
            newRoomID: "fresh-room"
        )

        #expect(selected == "fresh-room")
    }

    @Test
    func wireWithOneExistingSurfaceUsesThatSurfaceRoom() {
        #expect(AgentRoomSelection.roomIDForWire(
            sourceRoomID: "source-room",
            targetRoomID: nil,
            newRoomID: "fresh-room"
        ) == "source-room")
        #expect(AgentRoomSelection.roomIDForWire(
            sourceRoomID: nil,
            targetRoomID: "target-room",
            newRoomID: "fresh-room"
        ) == "target-room")
    }

    @Test
    func explicitSurfaceOperationDoesNotFallBackToHistoricalLatestRoom() {
        let selected = AgentRoomSelection.roomIDForSurfaceOperation(
            requestedRoomID: nil,
            surfaceWasExplicit: true,
            mappedSurfaceRoomID: nil,
            latestRoomID: "stale-room"
        )

        #expect(selected == nil)
    }

    @Test
    func surfaceOperationWithoutExplicitSurfaceMayUseLatestForCliDebugCompatibility() {
        let selected = AgentRoomSelection.roomIDForSurfaceOperation(
            requestedRoomID: nil,
            surfaceWasExplicit: false,
            mappedSurfaceRoomID: nil,
            latestRoomID: "latest-room"
        )

        #expect(selected == "latest-room")
    }

    @Test
    func explicitRoomIDAlwaysWins() {
        let selected = AgentRoomSelection.roomIDForSurfaceOperation(
            requestedRoomID: "requested-room",
            surfaceWasExplicit: true,
            mappedSurfaceRoomID: "mapped-room",
            latestRoomID: "latest-room"
        )

        #expect(selected == "requested-room")
    }

    @Test
    func explicitSurfaceConnectionCreatesFreshRoomWhenUnmappedEvenIfLatestExists() {
        let selected = AgentRoomSelection.roomIDForSurfaceConnection(
            requestedRoomID: nil,
            surfaceWasExplicit: true,
            mappedSurfaceRoomID: nil,
            latestRoomID: "stale-room",
            newRoomID: "fresh-room"
        )

        #expect(selected == "fresh-room")
    }
}
