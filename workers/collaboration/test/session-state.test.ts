import { expect, test } from "bun:test";
import { CollaborationRelaySessionState, type RelaySocket } from "../src/session-state";

class FakeSocket implements RelaySocket {
  sent: string[] = [];
  closed: Array<{ code: number; reason: string }> = [];

  send(data: string): void {
    this.sent.push(data);
  }

  close(code: number, reason: string): void {
    this.closed.push({ code, reason });
  }
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
