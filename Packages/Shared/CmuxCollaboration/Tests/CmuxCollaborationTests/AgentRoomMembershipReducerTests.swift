import Foundation
import Testing
@testable import CmuxCollaboration

/// Tests for the reducer that decides which surfaces show the "Claude room"
/// header pill. The bug these guard against: after linking terminals, some
/// connected surfaces did not show the pill (only one of two, etc.).
@Suite
struct AgentRoomMembershipReducerTests {
    private func surface() -> UUID { UUID() }

    private func room(id: String = "room-1", surfaceIDs: [UUID]) -> ClaudeRoomSnapshot {
        ClaudeRoomSnapshot(
            id: id,
            members: surfaceIDs.map { surfaceID in
                ClaudeRoomMember(
                    id: "member-\(surfaceID.uuidString.prefix(8))",
                    surfaceID: surfaceID.uuidString,
                    peerID: "peer-local"
                )
            }
        )
    }

    // MARK: - Core invariant: every member shows the pill

    @Test
    func everyMemberOfTheRoomIsConnected() {
        let a = surface()
        let b = surface()
        let snapshot = room(surfaceIDs: [a, b])

        let result = AgentRoomMembershipReducer.reconciled(AgentRoomMembershipState(), with: snapshot)

        #expect(result.isConnected(surfaceID: a))
        #expect(result.isConnected(surfaceID: b))
        #expect(result.roomIDsBySurfaceID[a] == "room-1")
        #expect(result.roomIDsBySurfaceID[b] == "room-1")
    }

    @Test
    func bothSurfacesShowPillRegardlessOfMutationOrder() {
        // Reproduces "click one, then drag" — connect A first, then the wire
        // connect produces a room with both A and B. After reconciling against
        // the two-member snapshot, both must be connected.
        let a = surface()
        let b = surface()

        // A connected first (single-member snapshot).
        var state = AgentRoomMembershipReducer.reconciled(
            AgentRoomMembershipState(),
            with: room(surfaceIDs: [a])
        )
        #expect(state.isConnected(surfaceID: a))
        #expect(!state.isConnected(surfaceID: b))

        // Wire drag connects B; store now reports both members.
        state = AgentRoomMembershipReducer.reconciled(state, with: room(surfaceIDs: [a, b]))

        #expect(state.isConnected(surfaceID: a))
        #expect(state.isConnected(surfaceID: b))
    }

    @Test
    func reconcileIsIdempotent() {
        let a = surface()
        let b = surface()
        let snapshot = room(surfaceIDs: [a, b])

        let once = AgentRoomMembershipReducer.reconciled(AgentRoomMembershipState(), with: snapshot)
        let twice = AgentRoomMembershipReducer.reconciled(once, with: snapshot)

        #expect(once == twice)
    }

    @Test
    func memberIDsAreMirroredFromSnapshot() {
        let a = surface()
        let snapshot = room(surfaceIDs: [a])
        let expectedMemberID = snapshot.members[0].id

        let result = AgentRoomMembershipReducer.reconciled(AgentRoomMembershipState(), with: snapshot)

        #expect(result.memberIDsBySurfaceID[a] == expectedMemberID)
    }

    // MARK: - Removal: a surface that left drops the pill

    @Test
    func surfaceRemovedFromRoomLosesPill() {
        let a = surface()
        let b = surface()
        let connected = AgentRoomMembershipReducer.reconciled(
            AgentRoomMembershipState(),
            with: room(surfaceIDs: [a, b])
        )

        // B disconnected: store now reports only A.
        let result = AgentRoomMembershipReducer.reconciled(connected, with: room(surfaceIDs: [a]))

        #expect(result.isConnected(surfaceID: a))
        #expect(!result.isConnected(surfaceID: b))
        #expect(result.memberIDsBySurfaceID[b] == nil)
    }

    @Test
    func emptyRoomClearsAllPillsForThatRoom() {
        let a = surface()
        let b = surface()
        let connected = AgentRoomMembershipReducer.reconciled(
            AgentRoomMembershipState(),
            with: room(surfaceIDs: [a, b])
        )

        let result = AgentRoomMembershipReducer.reconciled(connected, with: room(surfaceIDs: []))

        #expect(!result.isConnected(surfaceID: a))
        #expect(!result.isConnected(surfaceID: b))
        #expect(result.roomIDsBySurfaceID.isEmpty)
    }

    // MARK: - Isolation: other rooms are untouched

    @Test
    func surfacesInOtherRoomsAreNotTouched() {
        let a = surface() // in room-1
        let c = surface() // in room-2
        var state = AgentRoomMembershipState(
            roomIDsBySurfaceID: [c: "room-2"],
            memberIDsBySurfaceID: [c: "member-c"]
        )

        state = AgentRoomMembershipReducer.reconciled(state, with: room(id: "room-1", surfaceIDs: [a]))

        // A joined room-1; C's room-2 membership is preserved.
        #expect(state.roomIDsBySurfaceID[a] == "room-1")
        #expect(state.roomIDsBySurfaceID[c] == "room-2")
        #expect(state.memberIDsBySurfaceID[c] == "member-c")
    }

    @Test
    func emptyRoomDoesNotClearOtherRoomsMembers() {
        let c = surface() // in room-2
        let state = AgentRoomMembershipState(
            roomIDsBySurfaceID: [c: "room-2"],
            memberIDsBySurfaceID: [c: "member-c"]
        )

        // Reconciling an empty room-1 must not drop room-2's member.
        let result = AgentRoomMembershipReducer.reconciled(state, with: room(id: "room-1", surfaceIDs: []))

        #expect(result.roomIDsBySurfaceID[c] == "room-2")
    }

    // MARK: - Room switching

    @Test
    func movingSurfaceToNewRoomUpdatesMembership() {
        let a = surface()
        var state = AgentRoomMembershipReducer.reconciled(
            AgentRoomMembershipState(),
            with: room(id: "room-1", surfaceIDs: [a])
        )
        #expect(state.roomIDsBySurfaceID[a] == "room-1")

        // A is now reported as a member of room-2 (after leaving room-1).
        state = AgentRoomMembershipReducer.reconciled(state, with: room(id: "room-2", surfaceIDs: [a]))

        #expect(state.roomIDsBySurfaceID[a] == "room-2")
        #expect(state.isConnected(surfaceID: a))
    }

    // MARK: - Remote surfaces are ignored

    @Test
    func nonUUIDRemoteSurfaceIDsAreIgnored() {
        let local = surface()
        let snapshot = ClaudeRoomSnapshot(
            id: "room-1",
            members: [
                ClaudeRoomMember(id: "m-local", surfaceID: local.uuidString, peerID: "peer-local"),
                ClaudeRoomMember(id: "m-remote", surfaceID: "not-a-uuid", peerID: "peer-remote"),
            ]
        )

        let result = AgentRoomMembershipReducer.reconciled(AgentRoomMembershipState(), with: snapshot)

        #expect(result.isConnected(surfaceID: local))
        #expect(result.roomIDsBySurfaceID.count == 1)
    }
}
