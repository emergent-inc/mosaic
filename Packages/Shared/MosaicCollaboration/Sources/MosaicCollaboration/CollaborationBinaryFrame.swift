public import Foundation

/// A peer's participant identity plus whether it advertises the binary
/// terminal I/O capability, used to decide whether a hot-path frame can be sent
/// binary or must fall back to JSON.
public struct CollaborationCapabilityPeer: Equatable, Sendable {
    public let participantID: String
    public let supportsBinary: Bool

    public init(participantID: String, supportsBinary: Bool) {
        self.participantID = participantID
        self.supportsBinary = supportsBinary
    }
}

/// Capability negotiation for the binary terminal I/O hot path.
public enum CollaborationBinaryCapability {
    /// Advertised capability token for the binary terminal I/O frame (v1).
    public static let token = "binv1"

    /// Whether every recipient of a hot-path frame can receive it as a binary
    /// frame. A participant is binary-eligible only when *all* of its peers
    /// advertise support, because a frame routed to a participant reaches every
    /// peer sharing that participant ID. A mixed-version session therefore falls
    /// back to JSON.
    ///
    /// - Parameters:
    ///   - recipients: The participant IDs the frame is routed to, or `nil` to
    ///     broadcast to every peer.
    ///   - peers: The other peers in the session (excluding the sender).
    /// - Returns: `true` when the binary transport is safe for all recipients.
    public static func recipientsSupportBinary(
        recipients: [String]?,
        peers: [CollaborationCapabilityPeer]
    ) -> Bool {
        guard !peers.isEmpty else { return false }
        guard let recipients else {
            return peers.allSatisfy(\.supportsBinary)
        }
        guard !recipients.isEmpty else { return false }
        var supportedByParticipant: [String: Bool] = [:]
        for peer in peers {
            let current = supportedByParticipant[peer.participantID] ?? true
            supportedByParticipant[peer.participantID] = current && peer.supportsBinary
        }
        return recipients.allSatisfy { supportedByParticipant[$0] == true }
    }
}

/// Kind tag for a binary collaboration hot-path frame.
///
/// Only the two latency-critical, byte-carrying frame types use the binary
/// transport. Everything else (seed, dimensions, pointer, selection, presence)
/// stays JSON over the text WebSocket.
public enum CollaborationBinaryFrameKind: UInt8, Sendable, Equatable {
    /// Raw PTY output bytes streamed host -> viewers (`terminal.output`).
    case terminalOutput = 1
    /// Raw input bytes streamed guest -> host (`terminal.input`).
    case terminalInput = 2
}

/// Compact binary WebSocket frame for the collaboration terminal I/O hot path.
///
/// The relay forwards these opaquely: it reads only the small header to
/// validate `fromPeerID` and route by `recipientParticipantIDs`, then relays
/// the original buffer unchanged (the large `payload` is never re-encoded).
///
/// Wire layout (all multi-byte integers big-endian; strings are a `UInt16`
/// byte length followed by UTF-8 bytes):
///
/// ```
/// u8   magic = 0xCB
/// u8   version = 1
/// u8   kind            // 1 = terminal.output, 2 = terminal.input
/// u8   flags           // bit0 hasCaretPeerID, bit1 hasRecipients
/// u64  sequence        // output byte-sequence; 0 for input
/// str  terminalID
/// str  fromPeerID      // sender-authoritative; relay validates == connection peer
/// str  caretPeerID     // iff flags bit0
/// u16  recipientCount  // iff flags bit1
///      str participantID  x recipientCount
/// ...  payload = raw bytes (rest of buffer, NOT base64)
/// ```
public struct CollaborationBinaryFrame: Equatable, Sendable {
    /// Leading byte identifying a binary collaboration frame.
    public static let magic: UInt8 = 0xCB
    /// Wire format version. Bump on incompatible layout changes.
    public static let version: UInt8 = 1

    private static let flagHasCaretPeerID: UInt8 = 0b0000_0001
    private static let flagHasRecipients: UInt8 = 0b0000_0010

    /// The frame kind (output or input).
    public let kind: CollaborationBinaryFrameKind
    /// The host byte-sequence for output frames; `0` for input frames.
    public let sequence: UInt64
    /// The shared terminal identifier.
    public let terminalID: String
    /// The sending peer's relay peer ID (relay-authoritative on receipt).
    public let fromPeerID: String
    /// The peer whose input produced this output echo, if any.
    public let caretPeerID: String?
    /// The participant IDs this frame should be routed to; `nil` broadcasts to
    /// all peers in the session (matching the JSON `recipientParticipantIDs`
    /// contract).
    public let recipientParticipantIDs: [String]?
    /// The raw terminal bytes (not base64-encoded).
    public let payload: Data

    /// Creates a binary hot-path frame.
    public init(
        kind: CollaborationBinaryFrameKind,
        sequence: UInt64,
        terminalID: String,
        fromPeerID: String,
        caretPeerID: String? = nil,
        recipientParticipantIDs: [String]? = nil,
        payload: Data
    ) {
        self.kind = kind
        self.sequence = sequence
        self.terminalID = terminalID
        self.fromPeerID = fromPeerID
        self.caretPeerID = caretPeerID
        self.recipientParticipantIDs = recipientParticipantIDs
        self.payload = payload
    }

    /// Whether `data` looks like a binary collaboration frame (cheap magic-byte
    /// prescan; avoids a JSON parse on the hot path).
    public static func isBinaryFrame(_ data: Data) -> Bool {
        data.first == magic
    }

    /// Encodes this frame to its binary wire representation.
    public func encoded() -> Data {
        var out = Data()
        out.reserveCapacity(24 + terminalID.utf8.count + fromPeerID.utf8.count + payload.count)
        out.append(Self.magic)
        out.append(Self.version)
        out.append(kind.rawValue)

        var flags: UInt8 = 0
        if caretPeerID != nil { flags |= Self.flagHasCaretPeerID }
        if recipientParticipantIDs != nil { flags |= Self.flagHasRecipients }
        out.append(flags)

        Self.appendUInt64(sequence, to: &out)
        Self.appendString(terminalID, to: &out)
        Self.appendString(fromPeerID, to: &out)
        if let caretPeerID {
            Self.appendString(caretPeerID, to: &out)
        }
        if let recipientParticipantIDs {
            Self.appendUInt16(UInt16(min(recipientParticipantIDs.count, Int(UInt16.max))), to: &out)
            for id in recipientParticipantIDs.prefix(Int(UInt16.max)) {
                Self.appendString(id, to: &out)
            }
        }
        out.append(payload)
        return out
    }

    /// Decodes a binary wire frame, returning `nil` on malformed or
    /// non-matching input.
    public static func decode(_ data: Data) -> CollaborationBinaryFrame? {
        var reader = ByteReader(data)
        guard reader.readUInt8() == magic,
              reader.readUInt8() == version,
              let kindRaw = reader.readUInt8(),
              let kind = CollaborationBinaryFrameKind(rawValue: kindRaw),
              let flags = reader.readUInt8(),
              let sequence = reader.readUInt64(),
              let terminalID = reader.readString(),
              let fromPeerID = reader.readString()
        else { return nil }

        var caretPeerID: String?
        if flags & flagHasCaretPeerID != 0 {
            guard let value = reader.readString() else { return nil }
            caretPeerID = value
        }

        var recipientParticipantIDs: [String]?
        if flags & flagHasRecipients != 0 {
            guard let count = reader.readUInt16() else { return nil }
            var ids: [String] = []
            ids.reserveCapacity(Int(count))
            for _ in 0..<count {
                guard let id = reader.readString() else { return nil }
                ids.append(id)
            }
            recipientParticipantIDs = ids
        }

        let payload = reader.readRemaining()
        return CollaborationBinaryFrame(
            kind: kind,
            sequence: sequence,
            terminalID: terminalID,
            fromPeerID: fromPeerID,
            caretPeerID: caretPeerID,
            recipientParticipantIDs: recipientParticipantIDs,
            payload: payload
        )
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value))
    }

    private static func appendUInt64(_ value: UInt64, to data: inout Data) {
        for shift in stride(from: 56, through: 0, by: -8) {
            data.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
        }
    }

    private static func appendString(_ value: String, to data: inout Data) {
        let bytes = Array(value.utf8.prefix(Int(UInt16.max)))
        appendUInt16(UInt16(bytes.count), to: &data)
        data.append(contentsOf: bytes)
    }
}

/// Big-endian cursor over a `Data` buffer used to decode binary frames.
private struct ByteReader {
    private let bytes: [UInt8]
    private var offset = 0

    init(_ data: Data) {
        bytes = [UInt8](data)
    }

    mutating func readUInt8() -> UInt8? {
        guard offset < bytes.count else { return nil }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func readUInt16() -> UInt16? {
        guard offset + 2 <= bytes.count else { return nil }
        let value = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
        offset += 2
        return value
    }

    mutating func readUInt64() -> UInt64? {
        guard offset + 8 <= bytes.count else { return nil }
        var value: UInt64 = 0
        for index in 0..<8 {
            value = value << 8 | UInt64(bytes[offset + index])
        }
        offset += 8
        return value
    }

    mutating func readString() -> String? {
        guard let length = readUInt16() else { return nil }
        let count = Int(length)
        guard offset + count <= bytes.count else { return nil }
        let slice = bytes[offset..<(offset + count)]
        offset += count
        return String(decoding: slice, as: UTF8.self)
    }

    mutating func readRemaining() -> Data {
        guard offset <= bytes.count else { return Data() }
        let slice = bytes[offset..<bytes.count]
        offset = bytes.count
        return Data(slice)
    }
}
