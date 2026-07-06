import Foundation
import Testing
@testable import MosaicCollaboration

@Suite
struct SharedTerminalDescriptorTests {
    @Test
    func terminalIDRoundTripsThroughParse() {
        let descriptor = SharedTerminalDescriptor(
            workspaceID: UUID(),
            surfaceID: UUID(),
            title: "build"
        )
        let terminalID = descriptor.terminalID(sessionID: "SESSION-CODE")

        let parsed = SharedTerminalDescriptor.parse(terminalID: terminalID)

        #expect(parsed?.workspaceID == descriptor.workspaceID)
        #expect(parsed?.surfaceID == descriptor.surfaceID)
    }

    @Test
    func parseExtractsHostSurfaceEvenWhenSessionCodeContainsColons() {
        let workspaceID = UUID()
        let surfaceID = UUID()
        // A defensive check: only the trailing two components after the first
        // ":terminal:" marker are the host workspace and surface UUIDs.
        let terminalID = "weird:session:terminal:\(workspaceID.uuidString):\(surfaceID.uuidString)"

        let parsed = SharedTerminalDescriptor.parse(terminalID: terminalID)

        #expect(parsed?.workspaceID == workspaceID)
        #expect(parsed?.surfaceID == surfaceID)
    }

    @Test
    func parseReturnsNilForMalformedIdentifiers() {
        #expect(SharedTerminalDescriptor.parse(terminalID: "no-marker-here") == nil)
        #expect(SharedTerminalDescriptor.parse(terminalID: "s:terminal:not-a-uuid:also-not") == nil)
        #expect(SharedTerminalDescriptor.parse(terminalID: "s:terminal:\(UUID().uuidString)") == nil)
    }
}
