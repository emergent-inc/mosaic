// Header parser for the binary collaboration hot-path frame. The relay only
// needs the routing metadata (kind, fromPeerID, recipientParticipantIDs); the
// large payload is never decoded or re-encoded -- the original buffer is
// forwarded unchanged. Layout mirrors the codecs in
// cmux Packages/Shared/MosaicCollaboration/.../CollaborationBinaryFrame.swift
// and sharing/lib/relay/binaryFrame.ts.

export const BINARY_FRAME_MAGIC = 0xcb;
export const BINARY_FRAME_VERSION = 1;

const FLAG_HAS_CARET_PEER_ID = 0b0000_0001;
const FLAG_HAS_RECIPIENTS = 0b0000_0010;

const KIND_OUTPUT = 1;
const KIND_INPUT = 2;

export interface BinaryFrameHeader {
  kind: "terminal.output" | "terminal.input";
  fromPeerID: string;
  /// Participant IDs to route to; `null` broadcasts to every peer (matching the
  /// JSON `recipientParticipantIDs` contract).
  recipientParticipantIDs: string[] | null;
}

export function isBinaryFrame(data: string | ArrayBuffer): data is ArrayBuffer {
  if (typeof data === "string") return false;
  return data.byteLength > 0 && new Uint8Array(data, 0, 1)[0] === BINARY_FRAME_MAGIC;
}

/// Parses the routing header from a binary frame, returning `null` on any
/// malformed or non-matching input.
export function parseBinaryFrameHeader(buffer: ArrayBuffer): BinaryFrameHeader | null {
  const view = new Uint8Array(buffer);
  const reader = new HeaderReader(view);
  if (reader.readUInt8() !== BINARY_FRAME_MAGIC) return null;
  if (reader.readUInt8() !== BINARY_FRAME_VERSION) return null;
  const kindRaw = reader.readUInt8();
  const kind =
    kindRaw === KIND_OUTPUT
      ? "terminal.output"
      : kindRaw === KIND_INPUT
        ? "terminal.input"
        : null;
  if (kind === null) return null;
  const flags = reader.readUInt8();
  if (flags === null) return null;
  if (reader.skip(8) === false) return null; // sequence
  if (reader.skipString() === false) return null; // terminalID
  const fromPeerID = reader.readString();
  if (fromPeerID === null) return null;
  if ((flags & FLAG_HAS_CARET_PEER_ID) !== 0) {
    if (reader.skipString() === false) return null; // caretPeerID
  }
  let recipientParticipantIDs: string[] | null = null;
  if ((flags & FLAG_HAS_RECIPIENTS) !== 0) {
    const count = reader.readUInt16();
    if (count === null) return null;
    const ids: string[] = [];
    for (let i = 0; i < count; i += 1) {
      const id = reader.readString();
      if (id === null) return null;
      ids.push(id);
    }
    recipientParticipantIDs = ids;
  }
  return { kind, fromPeerID, recipientParticipantIDs };
}

class HeaderReader {
  private readonly view: Uint8Array;
  private offset = 0;

  constructor(view: Uint8Array) {
    this.view = view;
  }

  readUInt8(): number | null {
    if (this.offset >= this.view.length) return null;
    return this.view[this.offset++];
  }

  readUInt16(): number | null {
    if (this.offset + 2 > this.view.length) return null;
    const value = (this.view[this.offset] << 8) | this.view[this.offset + 1];
    this.offset += 2;
    return value;
  }

  readString(): string | null {
    const length = this.readUInt16();
    if (length === null) return null;
    if (this.offset + length > this.view.length) return null;
    const slice = this.view.subarray(this.offset, this.offset + length);
    this.offset += length;
    return new TextDecoder().decode(slice);
  }

  skip(count: number): boolean {
    if (this.offset + count > this.view.length) return false;
    this.offset += count;
    return true;
  }

  skipString(): boolean {
    const length = this.readUInt16();
    if (length === null) return false;
    return this.skip(length);
  }
}
