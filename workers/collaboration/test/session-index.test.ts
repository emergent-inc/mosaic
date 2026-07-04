import { expect, test } from "bun:test";
import { indexedSessionFromBody, indexedSessionStorageKey, normalizedIndexListLimit } from "../src/session-index-record";

test("index record normalizes session code and preserves explicit session id", () => {
  expect(indexedSessionFromBody({
    sessionID: "session-123",
    sessionCode: "1z0o-if9p",
  }, 1234)).toEqual({
    sessionID: "session-123",
    sessionCode: "1Z0OIF9P",
    createdAt: 1234,
  });
});

test("index record falls back to session code for blank session id", () => {
  expect(indexedSessionFromBody({
    sessionID: "   ",
    sessionCode: "abcd",
  }, 5678)).toEqual({
    sessionID: "ABCD",
    sessionCode: "ABCD",
    createdAt: 5678,
  });
});

test("index record rejects missing or malformed session codes", () => {
  expect(indexedSessionFromBody({ sessionID: "s1" }, 1)).toBeNull();
  expect(indexedSessionFromBody({ sessionCode: "ABC" }, 1)).toBeNull();
  expect(indexedSessionFromBody({ sessionCode: "ABCDEFGHI" }, 1)).toBeNull();
});

test("index storage key normalizes valid codes and rejects malformed codes", () => {
  expect(indexedSessionStorageKey("nxpl-xzah")).toBe("session:NXPLXZAH");
  expect(indexedSessionStorageKey("ABC")).toBeNull();
  expect(indexedSessionStorageKey("ABCDEFGHI")).toBeNull();
});

test("index list limit defaults, truncates, and clamps", () => {
  expect(normalizedIndexListLimit(null)).toBe(100);
  expect(normalizedIndexListLimit("not-a-number")).toBe(100);
  expect(normalizedIndexListLimit("0")).toBe(1);
  expect(normalizedIndexListLimit("2.9")).toBe(2);
  expect(normalizedIndexListLimit("9999")).toBe(500);
});
