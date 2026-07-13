import Foundation
import Testing
@testable import MosaicCollaboration

@Suite
struct AgentRoomDataSourceGuideTests {
    private func room(members: [ClaudeRoomMember]) -> ClaudeRoomSnapshot {
        var room = ClaudeRoomSnapshot(id: "room-1")
        room.members = members
        return room
    }

    @Test
    func entriesReturnOnlyDataSourceMembersExcludingRecipient() {
        let snapshot = room(members: [
            ClaudeRoomMember(id: "m-a", surfaceID: "surface-agent", peerID: "peer", role: .agent),
            ClaudeRoomMember(id: "m-b", surfaceID: "surface-source", peerID: "peer", role: .dataSource),
            ClaudeRoomMember(id: "m-c", surfaceID: "surface-self", peerID: "peer", role: .dataSource),
            ClaudeRoomMember(id: "m-d", surfaceID: "surface-legacy", peerID: "peer"),
        ])

        let entries = AgentRoomDataSourceGuide.entries(in: snapshot, excludingSurfaceID: "surface-self")

        #expect(entries.map(\.surfaceID) == ["surface-source"])
    }

    @Test
    func standingInstructionsIncludeReadCommandPerSource() {
        let entries = [
            AgentRoomDataSourceGuide.Entry(surfaceID: "AAAA-1111", displayName: "build logs"),
            AgentRoomDataSourceGuide.Entry(surfaceID: "BBBB-2222", displayName: nil),
        ]

        let text = AgentRoomDataSourceGuide.standingInstructions(for: entries)

        #expect(text.contains("read-only"))
        #expect(text.contains("shared agent context"))
        #expect(text.contains("- build logs: mosaic read-screen --surface AAAA-1111 --scrollback --lines 200"))
        #expect(text.contains("- surface BBBB-2222: mosaic read-screen --surface BBBB-2222 --scrollback --lines 200"))
    }

    @Test
    func standingInstructionsAreEmptyWithoutSources() {
        #expect(AgentRoomDataSourceGuide.standingInstructions(for: []) == "")
    }

    @Test
    func connectedEventTextCarriesLabelAndReadCommand() {
        let entry = AgentRoomDataSourceGuide.Entry(surfaceID: "AAAA-1111", displayName: "server logs")

        let text = AgentRoomDataSourceGuide.connectedEventText(entry: entry)

        #expect(text.contains("server logs"))
        #expect(text.contains("linked to this shared agent context"))
        #expect(text.contains("mosaic read-screen --surface AAAA-1111 --scrollback --lines 200"))
    }

    @Test
    func disconnectedEventTextNamesTheSurface() {
        let entry = AgentRoomDataSourceGuide.Entry(surfaceID: "AAAA-1111", displayName: "server logs")

        let text = AgentRoomDataSourceGuide.disconnectedEventText(entry: entry)

        #expect(text.contains("server logs"))
        #expect(text.contains("AAAA-1111"))
        #expect(text.contains("unlinked"))
    }

    @Test
    func entryLabelFallsBackToSurfaceID() {
        let entry = AgentRoomDataSourceGuide.Entry(surfaceID: "AAAA-1111", displayName: "  ")
        #expect(entry.label == "surface AAAA-1111")
    }
}
