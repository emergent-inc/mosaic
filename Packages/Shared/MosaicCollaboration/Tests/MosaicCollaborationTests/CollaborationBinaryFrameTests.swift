import Foundation
import Testing
@testable import MosaicCollaboration

@Suite
struct CollaborationBinaryFrameTests {
    /// Golden hex shared byte-for-byte with the TS codec test
    /// (sharing/tests/binary-frame.test.ts). Any layout change must update both.
    static let goldenHex =
        "cb01010300000000000001020002743100057065657241000570656572420001000270316869"

    static func goldenFrame() -> CollaborationBinaryFrame {
        CollaborationBinaryFrame(
            kind: .terminalOutput,
            sequence: 258,
            terminalID: "t1",
            fromPeerID: "peerA",
            caretPeerID: "peerB",
            recipientParticipantIDs: ["p1"],
            payload: Data([0x68, 0x69])
        )
    }

    @Test
    func encodesGoldenLayout() {
        let encoded = Self.goldenFrame().encoded()
        #expect(encoded.map { String(format: "%02x", $0) }.joined() == Self.goldenHex)
    }

    @Test
    func decodesGoldenLayout() throws {
        let data = Data(Self.hexBytes(Self.goldenHex))
        let frame = try #require(CollaborationBinaryFrame.decode(data))
        #expect(frame.kind == .terminalOutput)
        #expect(frame.sequence == 258)
        #expect(frame.terminalID == "t1")
        #expect(frame.fromPeerID == "peerA")
        #expect(frame.caretPeerID == "peerB")
        #expect(frame.recipientParticipantIDs == ["p1"])
        #expect(frame.payload == Data([0x68, 0x69]))
    }

    @Test
    func roundTripsOutputWithoutOptionalFields() throws {
        let frame = CollaborationBinaryFrame(
            kind: .terminalOutput,
            sequence: 9_000_000_000,
            terminalID: "terminal-xyz",
            fromPeerID: "host-peer",
            caretPeerID: nil,
            recipientParticipantIDs: nil,
            payload: Data("ls -la\r\n".utf8)
        )
        let decoded = try #require(CollaborationBinaryFrame.decode(frame.encoded()))
        #expect(decoded == frame)
        #expect(decoded.caretPeerID == nil)
        #expect(decoded.recipientParticipantIDs == nil)
    }

    @Test
    func roundTripsInputFrame() throws {
        let frame = CollaborationBinaryFrame(
            kind: .terminalInput,
            sequence: 0,
            terminalID: "t",
            fromPeerID: "guest-peer",
            recipientParticipantIDs: ["host-participant"],
            payload: Data([0x03])
        )
        let decoded = try #require(CollaborationBinaryFrame.decode(frame.encoded()))
        #expect(decoded == frame)
        #expect(decoded.kind == .terminalInput)
        #expect(decoded.recipientParticipantIDs == ["host-participant"])
    }

    @Test
    func emptyRecipientsEncodesBroadcastToNoOne() throws {
        let frame = CollaborationBinaryFrame(
            kind: .terminalOutput,
            sequence: 1,
            terminalID: "t",
            fromPeerID: "p",
            recipientParticipantIDs: [],
            payload: Data()
        )
        let decoded = try #require(CollaborationBinaryFrame.decode(frame.encoded()))
        #expect(decoded.recipientParticipantIDs == [])
    }

    @Test
    func isBinaryFrameDetectsMagic() {
        #expect(CollaborationBinaryFrame.isBinaryFrame(Data([CollaborationBinaryFrame.magic, 0x01])))
        #expect(!CollaborationBinaryFrame.isBinaryFrame(Data("{".utf8)))
        #expect(!CollaborationBinaryFrame.isBinaryFrame(Data()))
    }

    @Test
    func decodeRejectsWrongMagic() {
        #expect(CollaborationBinaryFrame.decode(Data([0x7b, 0x01, 0x01])) == nil)
    }

    @Test
    func decodeRejectsUnknownVersion() {
        var bytes = Self.hexBytes(Self.goldenHex)
        bytes[1] = 0x99
        #expect(CollaborationBinaryFrame.decode(Data(bytes)) == nil)
    }

    @Test
    func decodeRejectsTruncatedHeader() {
        let truncated = Data(Self.hexBytes(Self.goldenHex).prefix(6))
        #expect(CollaborationBinaryFrame.decode(truncated) == nil)
    }

    @Test
    func binaryEligibleWhenAllRecipientsSupport() {
        let peers = [
            CollaborationCapabilityPeer(participantID: "p1", supportsBinary: true),
            CollaborationCapabilityPeer(participantID: "p2", supportsBinary: true),
        ]
        #expect(CollaborationBinaryCapability.recipientsSupportBinary(recipients: ["p1", "p2"], peers: peers))
    }

    @Test
    func binaryFallsBackWhenAnyRecipientLacksSupport() {
        let peers = [
            CollaborationCapabilityPeer(participantID: "p1", supportsBinary: true),
            CollaborationCapabilityPeer(participantID: "p2", supportsBinary: false),
        ]
        #expect(!CollaborationBinaryCapability.recipientsSupportBinary(recipients: ["p1", "p2"], peers: peers))
        #expect(CollaborationBinaryCapability.recipientsSupportBinary(recipients: ["p1"], peers: peers))
    }

    @Test
    func participantIsIneligibleWhenAnySharedPeerLacksSupport() {
        // Same participant across two peers (e.g. two windows): one legacy peer
        // makes the whole participant JSON-only, since a routed frame reaches
        // both peers.
        let peers = [
            CollaborationCapabilityPeer(participantID: "shared", supportsBinary: true),
            CollaborationCapabilityPeer(participantID: "shared", supportsBinary: false),
        ]
        #expect(!CollaborationBinaryCapability.recipientsSupportBinary(recipients: ["shared"], peers: peers))
    }

    @Test
    func broadcastRequiresAllPeersToSupport() {
        let allSupport = [
            CollaborationCapabilityPeer(participantID: "p1", supportsBinary: true),
            CollaborationCapabilityPeer(participantID: "p2", supportsBinary: true),
        ]
        #expect(CollaborationBinaryCapability.recipientsSupportBinary(recipients: nil, peers: allSupport))
        let oneLegacy = allSupport + [CollaborationCapabilityPeer(participantID: "p3", supportsBinary: false)]
        #expect(!CollaborationBinaryCapability.recipientsSupportBinary(recipients: nil, peers: oneLegacy))
    }

    @Test
    func noPeersOrEmptyRecipientsAreNotBinaryEligible() {
        #expect(!CollaborationBinaryCapability.recipientsSupportBinary(recipients: nil, peers: []))
        #expect(!CollaborationBinaryCapability.recipientsSupportBinary(
            recipients: [],
            peers: [CollaborationCapabilityPeer(participantID: "p1", supportsBinary: true)]
        ))
    }

    private static func hexBytes(_ hex: String) -> [UInt8] {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16) ?? 0)
            index = next
        }
        return bytes
    }
}
