import { expect, test } from "bun:test";
import { CollaborationRelaySessionState, type RelaySocket } from "../src/session-state";

class FakeSocket implements RelaySocket {
  sent: string[] = [];
  sentBinary: ArrayBuffer[] = [];
  closed: Array<{ code: number; reason: string }> = [];

  send(data: string | ArrayBuffer | ArrayBufferView): void {
    if (typeof data === "string") {
      this.sent.push(data);
      return;
    }
    this.sentBinary.push(data instanceof ArrayBuffer ? data : (data.buffer as ArrayBuffer));
  }

  close(code: number, reason: string): void {
    this.closed.push({ code, reason });
  }
}

const BINARY_MAGIC = 0xcb;
const BINARY_VERSION = 1;

/// Minimal encoder mirroring the wire layout in src/binary.ts, used to build
/// test frames the relay must route.
function encodeBinaryFrame(input: {
  kind: "terminal.output" | "terminal.input";
  sequence?: number;
  terminalID: string;
  fromPeerID: string;
  caretPeerID?: string;
  recipientParticipantIDs?: string[];
  payload: Uint8Array;
}): ArrayBuffer {
  const enc = new TextEncoder();
  const terminalID = enc.encode(input.terminalID);
  const fromPeerID = enc.encode(input.fromPeerID);
  const caret = input.caretPeerID != null ? enc.encode(input.caretPeerID) : null;
  const recipients =
    input.recipientParticipantIDs != null
      ? input.recipientParticipantIDs.map((id) => enc.encode(id))
      : null;
  const parts: number[] = [
    BINARY_MAGIC,
    BINARY_VERSION,
    input.kind === "terminal.output" ? 1 : 2,
    (caret !== null ? 1 : 0) | (recipients !== null ? 2 : 0),
  ];
  const seq = BigInt(input.sequence ?? 0);
  for (let i = 0; i < 8; i += 1) parts.push(Number((seq >> BigInt(8 * (7 - i))) & 0xffn));
  const pushString = (bytes: Uint8Array) => {
    parts.push((bytes.length >>> 8) & 0xff, bytes.length & 0xff);
    for (const b of bytes) parts.push(b);
  };
  pushString(terminalID);
  pushString(fromPeerID);
  if (caret !== null) pushString(caret);
  if (recipients !== null) {
    parts.push((recipients.length >>> 8) & 0xff, recipients.length & 0xff);
    for (const id of recipients) pushString(id);
  }
  for (const b of input.payload) parts.push(b);
  return new Uint8Array(parts).buffer;
}

function decodePayload(buffer: ArrayBuffer): Uint8Array {
  // The payload is the trailing bytes; find it by re-reading the header length.
  const view = new Uint8Array(buffer);
  let offset = 4 + 8;
  const readStr = () => {
    const len = (view[offset] << 8) | view[offset + 1];
    offset += 2 + len;
  };
  const flags = view[3];
  readStr(); // terminalID
  readStr(); // fromPeerID
  if ((flags & 1) !== 0) readStr(); // caret
  if ((flags & 2) !== 0) {
    const count = (view[offset] << 8) | view[offset + 1];
    offset += 2;
    for (let i = 0; i < count; i += 1) readStr();
  }
  return view.subarray(offset);
}

const peer = (peerID: string) => ({
  peerID,
  participantID: `${peerID}-participant`,
  displayName: peerID,
  color: "#123456",
});

const peerWithImage = (peerID: string, imageURL: string) => ({
  ...peer(peerID),
  imageURL,
});

test("joined frame includes existing distinct peers", () => {
  const state = new CollaborationRelaySessionState();
  const first = new FakeSocket();
  const second = new FakeSocket();

  state.addPeer("ABCD-1234", peer("p1"), first, 1000);
  state.addPeer("ABCD-1234", peer("p2"), second, 1000);

  expect(JSON.parse(second.sent[0] ?? "{}")).toEqual({
    type: "session.joined",
    sessionID: "ABCD-1234",
    peers: [peer("p1"), peer("p2")],
  });
  expect(JSON.parse(first.sent.at(-1) ?? "{}")).toEqual({
    type: "peer.joined",
    peer: peer("p2"),
  });
});

test("carries peer imageURL through the roster and join broadcasts", () => {
  // The relay is the only path a remote collaborator's profile picture takes to
  // reach other participants' sidebar/tab avatars, so imageURL must survive both
  // the session.joined roster and the peer.joined broadcast verbatim.
  const state = new CollaborationRelaySessionState();
  const first = new FakeSocket();
  const second = new FakeSocket();

  const host = peerWithImage("p1", "https://img.example/host.png");
  const joiner = peerWithImage("p2", "https://img.example/joiner.png");
  state.addPeer("ABCD-1234", host, first, 1000);
  state.addPeer("ABCD-1234", joiner, second, 1000);

  const roster = JSON.parse(second.sent[0] ?? "{}");
  expect(roster).toEqual({
    type: "session.joined",
    sessionID: "ABCD-1234",
    peers: [host, joiner],
  });
  expect(roster.peers[0].imageURL).toBe("https://img.example/host.png");

  expect(JSON.parse(first.sent.at(-1) ?? "{}")).toEqual({
    type: "peer.joined",
    peer: joiner,
  });
});

test("peer update refreshes roster imageURL and broadcasts the new profile picture", () => {
  const state = new CollaborationRelaySessionState();
  const first = new FakeSocket();
  const second = new FakeSocket();
  const third = new FakeSocket();
  state.addPeer("ABCD-1234", peer("p1"), first, 1000);
  state.addPeer("ABCD-1234", peer("p2"), second, 1000);
  const updated = peerWithImage("p1", "https://img.example/p1.png");

  state.handleMessage("p1", JSON.stringify({ type: "peer.update", peer: updated }), 1100);
  expect(JSON.parse(second.sent.at(-1) ?? "{}")).toEqual({
    type: "peer.update",
    peer: updated,
  });

  state.addPeer("ABCD-1234", peer("p3"), third, 1200);
  expect(JSON.parse(third.sent[0] ?? "{}")).toEqual({
    type: "session.joined",
    sessionID: "ABCD-1234",
    peers: [updated, peer("p2"), peer("p3")],
  });
});

test("peer update rejects missing or mismatched peer payloads and removes the sender", () => {
  const state = new CollaborationRelaySessionState();
  const first = new FakeSocket();
  const second = new FakeSocket();
  state.addPeer("ABCD-1234", peer("p1"), first, 1000);
  state.addPeer("ABCD-1234", peer("p2"), second, 1000);

  state.handleMessage("p1", JSON.stringify({ type: "peer.update", peer: peerWithImage("p2", "https://img.example/p2.png") }), 1100);

  expect(first.closed).toEqual([{ code: 1003, reason: "invalid frame" }]);
  expect(JSON.parse(second.sent.at(-1) ?? "{}")).toEqual({
    type: "peer.left",
    peerID: "p1",
    reason: "disconnect",
  });
  expect(state.peerCount).toBe(1);

  state.handleMessage("p2", JSON.stringify({ type: "peer.update" }), 1200);

  expect(second.closed).toEqual([{ code: 1003, reason: "invalid frame" }]);
  expect(state.peerCount).toBe(0);
});

test("forwards opaque non-heartbeat frames to other peers", () => {
  const state = new CollaborationRelaySessionState();
  const first = new FakeSocket();
  const second = new FakeSocket();
  state.addPeer("ABCD-1234", peer("p1"), first, 1000);
  state.addPeer("ABCD-1234", peer("p2"), second, 1000);

  state.handleMessage("p1", JSON.stringify({ type: "document.update", documentID: "doc1" }), 1100);

  const forwarded = JSON.parse(second.sent.at(-1) ?? "{}");
  expect(forwarded).toEqual({
    type: "document.update",
    documentID: "doc1",
    fromPeerID: "p1",
    receivedAt: 1100,
  });
});

test("forwards terminal collaboration frames to other peers", () => {
  const state = new CollaborationRelaySessionState();
  const first = new FakeSocket();
  const second = new FakeSocket();
  state.addPeer("ABCD-1234", peer("p1"), first, 1000);
  state.addPeer("ABCD-1234", peer("p2"), second, 1000);

  state.handleMessage(
    "p1",
    JSON.stringify({ type: "terminal.output", terminalID: "term1", sequence: 7, dataBase64: "b2s=" }),
    1100
  );
  state.handleMessage(
    "p2",
    JSON.stringify({ type: "terminal.input", terminalID: "term1", inputID: "i1", dataBase64: "ZWNobyBvaw0=" }),
    1200
  );

  expect(JSON.parse(second.sent.at(-1) ?? "{}")).toEqual({
    type: "terminal.output",
    terminalID: "term1",
    sequence: 7,
    dataBase64: "b2s=",
    fromPeerID: "p1",
    receivedAt: 1100,
  });
  expect(JSON.parse(first.sent.at(-1) ?? "{}")).toEqual({
    type: "terminal.input",
    terminalID: "term1",
    inputID: "i1",
    dataBase64: "ZWNobyBvaw0=",
    fromPeerID: "p2",
    receivedAt: 1200,
  });
});

test("forwards targeted terminal frames only to selected participants", () => {
  const state = new CollaborationRelaySessionState();
  const first = new FakeSocket();
  const second = new FakeSocket();
  const third = new FakeSocket();
  state.addPeer("ABCD-1234", peer("p1"), first, 1000);
  state.addPeer("ABCD-1234", peer("p2"), second, 1000);
  state.addPeer("ABCD-1234", peer("p3"), third, 1000);
  const beforeSecond = second.sent.length;
  const beforeThird = third.sent.length;

  state.handleMessage(
    "p1",
    JSON.stringify({
      type: "terminal.output",
      terminalID: "term1",
      sequence: 7,
      dataBase64: "b2s=",
      recipientParticipantIDs: ["p2-participant"],
    }),
    1100
  );

  expect(JSON.parse(second.sent.at(-1) ?? "{}")).toEqual({
    type: "terminal.output",
    terminalID: "term1",
    sequence: 7,
    dataBase64: "b2s=",
    recipientParticipantIDs: ["p2-participant"],
    fromPeerID: "p1",
    receivedAt: 1100,
  });
  expect(second.sent.length).toBe(beforeSecond + 1);
  expect(third.sent.length).toBe(beforeThird);
});

test("targeted terminal frames with empty recipients are not forwarded", () => {
  const state = new CollaborationRelaySessionState();
  const first = new FakeSocket();
  const second = new FakeSocket();
  state.addPeer("ABCD-1234", peer("p1"), first, 1000);
  state.addPeer("ABCD-1234", peer("p2"), second, 1000);
  const before = second.sent.length;

  state.handleMessage(
    "p1",
    JSON.stringify({
      type: "terminal.output",
      terminalID: "term1",
      sequence: 7,
      dataBase64: "b2s=",
      recipientParticipantIDs: [],
    }),
    1100
  );

  expect(second.sent.length).toBe(before);
});

test("preserves terminal output caret attribution", () => {
  const state = new CollaborationRelaySessionState();
  const first = new FakeSocket();
  const second = new FakeSocket();
  state.addPeer("ABCD-1234", peer("p1"), first, 1000);
  state.addPeer("ABCD-1234", peer("p2"), second, 1000);

  state.handleMessage(
    "p1",
    JSON.stringify({
      type: "terminal.output",
      terminalID: "term1",
      sequence: 7,
      dataBase64: "b2s=",
      caretPeerID: null,
    }),
    1100
  );

  expect(JSON.parse(second.sent.at(-1) ?? "{}")).toEqual({
    type: "terminal.output",
    terminalID: "term1",
    sequence: 7,
    dataBase64: "b2s=",
    caretPeerID: null,
    fromPeerID: "p1",
    receivedAt: 1100,
  });
});

test("rejects malformed frames and broadcasts peer departure", () => {
  const state = new CollaborationRelaySessionState();
  const first = new FakeSocket();
  const second = new FakeSocket();
  state.addPeer("ABCD-1234", peer("p1"), first, 1000);
  state.addPeer("ABCD-1234", peer("p2"), second, 1000);

  state.handleMessage("p1", "{", 1100);

  expect(first.closed).toEqual([{ code: 1003, reason: "invalid frame" }]);
  expect(JSON.parse(second.sent.at(-1) ?? "{}")).toEqual({
    type: "peer.left",
    peerID: "p1",
    reason: "disconnect",
  });
});

test("heartbeat refreshes liveness without forwarding", () => {
  const state = new CollaborationRelaySessionState();
  const first = new FakeSocket();
  const second = new FakeSocket();
  state.addPeer("ABCD-1234", peer("p1"), first, 1000);
  state.addPeer("ABCD-1234", peer("p2"), second, 1000);
  const before = second.sent.length;

  state.handleMessage("p1", JSON.stringify({ type: "peer.heartbeat" }), 31_000);
  state.expire(31_001, 30_000);

  expect(second.sent.length).toBe(before);
  expect(first.closed).toEqual([]);
});

test("heartbeat timeout closes stale peers and notifies survivors", () => {
  const state = new CollaborationRelaySessionState();
  const first = new FakeSocket();
  const second = new FakeSocket();
  state.addPeer("ABCD-1234", peer("p1"), first, 1000);
  state.addPeer("ABCD-1234", peer("p2"), second, 1000);

  state.expire(31_001, 30_000);

  expect(first.closed).toEqual([{ code: 1001, reason: "heartbeat timeout" }]);
  expect(JSON.parse(second.sent.at(-1) ?? "{}")).toEqual({
    type: "peer.left",
    peerID: "p1",
    reason: "timeout",
  });
});

test("forwards binary terminal output unchanged to other peers", () => {
  const state = new CollaborationRelaySessionState();
  const first = new FakeSocket();
  const second = new FakeSocket();
  state.addPeer("ABCD-1234", peer("p1"), first, 1000);
  state.addPeer("ABCD-1234", peer("p2"), second, 1000);

  const frame = encodeBinaryFrame({
    kind: "terminal.output",
    sequence: 42,
    terminalID: "term1",
    fromPeerID: "p1",
    payload: new Uint8Array([0x6f, 0x6b]),
  });
  state.handleMessage("p1", frame, 1100);

  expect(second.sentBinary).toHaveLength(1);
  // Zero-copy forward: the exact same buffer is relayed.
  expect(second.sentBinary[0]).toBe(frame);
  expect([...decodePayload(second.sentBinary[0])]).toEqual([0x6f, 0x6b]);
  expect(first.sentBinary).toHaveLength(0);
});

test("routes binary frames only to selected participants", () => {
  const state = new CollaborationRelaySessionState();
  const first = new FakeSocket();
  const second = new FakeSocket();
  const third = new FakeSocket();
  state.addPeer("ABCD-1234", peer("p1"), first, 1000);
  state.addPeer("ABCD-1234", peer("p2"), second, 1000);
  state.addPeer("ABCD-1234", peer("p3"), third, 1000);

  state.handleMessage(
    "p1",
    encodeBinaryFrame({
      kind: "terminal.output",
      sequence: 1,
      terminalID: "term1",
      fromPeerID: "p1",
      recipientParticipantIDs: ["p2-participant"],
      payload: new Uint8Array([0x01]),
    }),
    1100,
  );

  expect(second.sentBinary).toHaveLength(1);
  expect(third.sentBinary).toHaveLength(0);
});

test("binary frames with empty recipients are not forwarded", () => {
  const state = new CollaborationRelaySessionState();
  const first = new FakeSocket();
  const second = new FakeSocket();
  state.addPeer("ABCD-1234", peer("p1"), first, 1000);
  state.addPeer("ABCD-1234", peer("p2"), second, 1000);

  state.handleMessage(
    "p1",
    encodeBinaryFrame({
      kind: "terminal.output",
      sequence: 1,
      terminalID: "term1",
      fromPeerID: "p1",
      recipientParticipantIDs: [],
      payload: new Uint8Array([0x01]),
    }),
    1100,
  );

  expect(second.sentBinary).toHaveLength(0);
});

test("binary frame with a spoofed fromPeerID closes the sender", () => {
  const state = new CollaborationRelaySessionState();
  const first = new FakeSocket();
  const second = new FakeSocket();
  state.addPeer("ABCD-1234", peer("p1"), first, 1000);
  state.addPeer("ABCD-1234", peer("p2"), second, 1000);

  state.handleMessage(
    "p1",
    encodeBinaryFrame({
      kind: "terminal.output",
      sequence: 1,
      terminalID: "term1",
      fromPeerID: "p2",
      payload: new Uint8Array([0x01]),
    }),
    1100,
  );

  expect(first.closed).toEqual([{ code: 1003, reason: "invalid frame" }]);
  expect(JSON.parse(second.sent.at(-1) ?? "{}")).toEqual({
    type: "peer.left",
    peerID: "p1",
    reason: "disconnect",
  });
  expect(state.peerCount).toBe(1);
});

test("binary traffic refreshes liveness", () => {
  const state = new CollaborationRelaySessionState();
  const first = new FakeSocket();
  const second = new FakeSocket();
  state.addPeer("ABCD-1234", peer("p1"), first, 1000);
  state.addPeer("ABCD-1234", peer("p2"), second, 1000);

  state.handleMessage(
    "p1",
    encodeBinaryFrame({
      kind: "terminal.output",
      sequence: 1,
      terminalID: "term1",
      fromPeerID: "p1",
      payload: new Uint8Array([0x01]),
    }),
    31_000,
  );
  state.expire(31_001, 30_000);

  expect(first.closed).toEqual([]);
});
