import { expect, test } from "bun:test";
import {
  normalizedTeamSessionListLimit,
  normalizeTeamId,
  normalizeTeamSessionId,
  sortedByActivity,
  teamSessionRecordForUpsert,
  teamSessionStorageKey,
  transcriptObjectKey,
  type TeamSessionRecord,
} from "../src/team-sessions-record";

function upsert(
  body: Record<string, unknown>,
  existing: TeamSessionRecord | null = null,
  now = 1_000,
): TeamSessionRecord | null {
  return teamSessionRecordForUpsert({
    body,
    userId: "user_1",
    displayName: "Alex",
    transcriptBytes: 42,
    existing,
    now,
  });
}

test("upsert builds a full record from a first sync", () => {
  const record = upsert({
    sessionId: "0e9f3a52-1111-2222-3333-444455556666",
    agent: "claude",
    title: "Fix login bug",
    cwd: "/Users/alex/dev/app",
    repoRemoteUrl: "git@github.com:acme/app.git",
    gitBranch: "fix/login",
    headSha: "abc123",
    wipRef: "refs/mosaic/sessions/0e9f3a52-1111-2222-3333-444455556666",
    model: "opus",
    turnCount: 7,
  });

  expect(record).not.toBeNull();
  expect(record?.userId).toBe("user_1");
  expect(record?.displayName).toBe("Alex");
  expect(record?.title).toBe("Fix login bug");
  expect(record?.wipRef).toBe(
    "refs/mosaic/sessions/0e9f3a52-1111-2222-3333-444455556666",
  );
  expect(record?.transcriptBytes).toBe(42);
  expect(record?.createdAt).toBe(1_000);
  expect(record?.lastActivityAt).toBe(1_000);
});

test("upsert preserves createdAt and fills gaps from the existing record", () => {
  const existing = upsert(
    {
      sessionId: "session-1",
      title: "Original title",
      gitBranch: "main",
      model: "opus",
    },
    null,
    500,
  );
  if (existing === null) throw new Error("expected existing record");

  const updated = upsert({ sessionId: "session-1", turnCount: 3 }, existing, 900);

  expect(updated?.createdAt).toBe(500);
  expect(updated?.lastActivityAt).toBe(900);
  expect(updated?.title).toBe("Original title");
  expect(updated?.gitBranch).toBe("main");
  expect(updated?.model).toBe("opus");
  expect(updated?.turnCount).toBe(3);
});

test("an explicit null wipRef clears a previously recorded WIP ref", () => {
  const existing = upsert({
    sessionId: "session-1",
    wipRef: "refs/mosaic/sessions/session-1",
  });
  if (existing === null) throw new Error("expected existing record");

  const cleared = upsert({ sessionId: "session-1", wipRef: null }, existing);
  const untouched = upsert({ sessionId: "session-1" }, existing);

  expect(cleared?.wipRef).toBeNull();
  expect(untouched?.wipRef).toBe("refs/mosaic/sessions/session-1");
});

test("identity comes from the token, not the body", () => {
  const record = upsert({
    sessionId: "session-1",
    userId: "user_spoofed",
    displayName: "Mallory",
  });

  expect(record?.userId).toBe("user_1");
  expect(record?.displayName).toBe("Alex");
});

test("upsert rejects invalid session ids", () => {
  expect(upsert({})).toBeNull();
  expect(upsert({ sessionId: "" })).toBeNull();
  expect(upsert({ sessionId: "has spaces" })).toBeNull();
  expect(upsert({ sessionId: "path/../traversal" })).toBeNull();
  expect(upsert({ sessionId: "a".repeat(257) })).toBeNull();
});

test("session and team id normalization constrains charset", () => {
  expect(normalizeTeamSessionId(" abc-DEF_1.2 ")).toBe("abc-DEF_1.2");
  expect(normalizeTeamSessionId("nope/slash")).toBeNull();
  expect(normalizeTeamId("org_2abcDEF")).toBe("org_2abcDEF");
  expect(normalizeTeamId("user_1")).toBe("user_1");
  expect(normalizeTeamId("bad/id")).toBeNull();
  expect(normalizeTeamId("")).toBeNull();
  expect(normalizeTeamId(42)).toBeNull();
});

test("storage and object keys embed normalized ids", () => {
  expect(teamSessionStorageKey("session-1")).toBe("session:session-1");
  expect(transcriptObjectKey("org_1", "session-1")).toBe(
    "sessions/org_1/session-1.jsonl",
  );
});

test("list limit defaults, truncates, and clamps", () => {
  expect(normalizedTeamSessionListLimit(null)).toBe(200);
  expect(normalizedTeamSessionListLimit("not-a-number")).toBe(200);
  expect(normalizedTeamSessionListLimit("0")).toBe(1);
  expect(normalizedTeamSessionListLimit("9999")).toBe(500);
});

test("sortedByActivity orders most recent first", () => {
  const older = upsert({ sessionId: "older" }, null, 100);
  const newer = upsert({ sessionId: "newer" }, null, 200);
  if (older === null || newer === null) throw new Error("expected records");

  expect(sortedByActivity([older, newer]).map((record) => record.sessionId)).toEqual([
    "newer",
    "older",
  ]);
});
