import Foundation
import Testing
@testable import MosaicCollaboration

@Suite
struct ClaudeRoomMemberRoleTests {
    @Test
    func legacyMemberWithoutRoleDecodesAsAgent() throws {
        // Persisted rooms written before the role existed carry no `role` key;
        // they must decode and default to `.agent`.
        let legacyJSON = """
        {
            "id": "m-1",
            "surfaceID": "surface-a",
            "peerID": "peer-a"
        }
        """
        let member = try JSONDecoder().decode(ClaudeRoomMember.self, from: Data(legacyJSON.utf8))
        #expect(member.role == nil)
        #expect(member.resolvedRole == .agent)
    }

    @Test
    func roleRoundTripsThroughCoding() throws {
        let member = ClaudeRoomMember(
            id: "m-1",
            surfaceID: "surface-a",
            peerID: "peer-a",
            role: .dataSource
        )
        let data = try JSONEncoder().encode(member)
        let decoded = try JSONDecoder().decode(ClaudeRoomMember.self, from: data)
        #expect(decoded.role == .dataSource)
        #expect(decoded.resolvedRole == .dataSource)
    }

    @Test
    func reconnectWithoutRoleKeepsClassifiedRole() async throws {
        // A reconnect that does not restate the role (e.g. a session rebind)
        // must not silently flip a data source back to an agent.
        let store = ClaudeRoomStore()
        _ = await store.createRoom(id: "room-1")
        _ = await store.connect(
            member: ClaudeRoomMember(id: "m-a", surfaceID: "surface-a", peerID: "peer", role: .dataSource),
            to: "room-1"
        )
        let room = await store.connect(
            member: ClaudeRoomMember(id: "m-a", surfaceID: "surface-a", peerID: "peer"),
            to: "room-1"
        )
        #expect(room.members.first?.resolvedRole == .dataSource)
    }

    @Test
    func reconnectWithExplicitRoleOverridesStoredRole() async throws {
        // Starting an agent in a previously data-source pane reclassifies it.
        let store = ClaudeRoomStore()
        _ = await store.createRoom(id: "room-1")
        _ = await store.connect(
            member: ClaudeRoomMember(id: "m-a", surfaceID: "surface-a", peerID: "peer", role: .dataSource),
            to: "room-1"
        )
        let room = await store.connect(
            member: ClaudeRoomMember(id: "m-a", surfaceID: "surface-a", peerID: "peer", role: .agent),
            to: "room-1"
        )
        #expect(room.members.first?.resolvedRole == .agent)
    }
}
