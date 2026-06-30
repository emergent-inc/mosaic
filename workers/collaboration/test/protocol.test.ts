import { expect, test } from "bun:test";
import { normalizeSessionCode, parseEnvelope, parsePeer, randomSessionCode } from "../src/protocol";

test("parsePeer accepts complete peer metadata", () => {
  expect(parsePeer({ peerID: "p1", displayName: "Peer", color: "#123456" })).toEqual({
    peerID: "p1",
    displayName: "Peer",
    color: "#123456",
  });
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
  expect(randomSessionCode()).toMatch(/^[2-9A-HJ-NP-Z]{8}$/);
});

test("session code normalization accepts shareable and pasted forms", () => {
  expect(normalizeSessionCode("5znh-gf9p")).toBe("5ZNHGF9P");
  expect(normalizeSessionCode("5ZNH GF9P")).toBe("5ZNHGF9P");
  expect(normalizeSessionCode("5ZNHGF9P")).toBe("5ZNHGF9P");
  expect(normalizeSessionCode("ABCDE")).toBe("ABCDE");
  expect(normalizeSessionCode("1ZNH-GF9P")).toBeNull();
});
