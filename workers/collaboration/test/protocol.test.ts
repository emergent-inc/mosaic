import { expect, test } from "bun:test";
import { normalizeSessionCode, parseEnvelope, parsePeer, randomSessionCode } from "../src/protocol";

test("parsePeer accepts complete peer metadata", () => {
  expect(parsePeer({
    peerID: "p1",
    participantID: "person-1",
    displayName: "Peer",
    color: "#123456",
    imageURL: "https://img.example/peer.png",
  })).toEqual({
    peerID: "p1",
    participantID: "person-1",
    displayName: "Peer",
    color: "#123456",
    imageURL: "https://img.example/peer.png",
  });
});

test("parsePeer falls back to peerID for older clients without participant metadata", () => {
  expect(parsePeer({ peerID: "p1", displayName: "Peer", color: "#123456" })).toEqual({
    peerID: "p1",
    participantID: "p1",
    displayName: "Peer",
    color: "#123456",
  });
});

test("parsePeer drops absent, empty, whitespace, and non-string imageURL", () => {
  for (const imageURL of [undefined, null, "", "   ", 42]) {
    const parsed = parsePeer({
      peerID: "p1",
      displayName: "Peer",
      color: "#123456",
      imageURL,
    });
    expect(parsed).not.toBeNull();
    expect(parsed).not.toHaveProperty("imageURL");
  }
});

test("parseEnvelope rejects malformed or oversized frames", () => {
  expect(parseEnvelope("{")).toBeNull();
  expect(parseEnvelope(JSON.stringify({ nope: true }))).toBeNull();
  expect(parseEnvelope("x".repeat(1024 * 1024 + 1))).toBeNull();
  expect(parseEnvelope(JSON.stringify({ type: "document.update", payloadBase64: "abc" }))).toEqual({
    type: "document.update",
    payloadBase64: "abc",
  });
});

test("invite material has expected shape", () => {
  expect(randomSessionCode()).toMatch(/^[A-HJ-NP-Z]{4}$/);
});

test("session code normalization accepts shareable and pasted forms", () => {
  expect(normalizeSessionCode("5znh")).toBe("5ZNH");
  expect(normalizeSessionCode("5z-nh")).toBe("5ZNH");
  expect(normalizeSessionCode("5znh-gf9p")).toBe("5ZNHGF9P");
  expect(normalizeSessionCode("5ZNH GF9P")).toBe("5ZNHGF9P");
  expect(normalizeSessionCode("5ZNHGF9P")).toBe("5ZNHGF9P");
  expect(normalizeSessionCode("ABCDE")).toBe("ABCDE");
  expect(normalizeSessionCode("1ZNH")).toBeNull();
  expect(normalizeSessionCode("1ZNH-GF9P")).toBeNull();
});
