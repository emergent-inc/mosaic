import { expect, test } from "bun:test";
import { teamSessionsFetch, type TeamSessionsEnv } from "../src/team-sessions-handler";
import {
  sortedByActivity,
  teamSessionRecordForUpsert,
  teamSessionStorageKey,
  TEAM_SESSION_KEY_PREFIX,
  type TeamSessionRecord,
} from "../src/team-sessions-record";
import { mintToken } from "./native-token.test";

const SECRET = "test-native-secret";

/// In-memory stand-in for a per-team TeamSessionsObject, implementing the same
/// internal /sessions protocol against a Map instead of DO storage.
class FakeTeamSessionsObject {
  private records = new Map<string, TeamSessionRecord>();

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/sessions" && request.method === "POST") {
      const payload = (await request.json()) as {
        session: Record<string, unknown>;
        userId: string;
        displayName?: string | null;
        transcriptBytes?: number;
      };
      const sessionId = String(payload.session.sessionId ?? "");
      const key = teamSessionStorageKey(sessionId);
      const existing = this.records.get(key) ?? null;
      if (existing !== null && existing.userId !== payload.userId) {
        return jsonResponse({ error: "session_not_owned" }, 403);
      }
      const record = teamSessionRecordForUpsert({
        body: payload.session,
        userId: payload.userId,
        displayName: payload.displayName ?? null,
        transcriptBytes: payload.transcriptBytes ?? existing?.transcriptBytes ?? 0,
        existing,
      });
      if (record === null) return jsonResponse({ error: "invalid_session" }, 400);
      this.records.set(key, record);
      return jsonResponse({ recorded: true, session: record });
    }
    if (url.pathname === "/sessions" && request.method === "GET") {
      const sessions = sortedByActivity(
        [...this.records.entries()]
          .filter(([key]) => key.startsWith(TEAM_SESSION_KEY_PREFIX))
          .map(([, value]) => value),
      );
      return jsonResponse({ sessions });
    }
    const match = url.pathname.match(/^\/sessions\/([^/]+)$/);
    if (match && request.method === "GET") {
      const record = this.records.get(teamSessionStorageKey(decodeURIComponent(match[1])));
      if (record === undefined) return jsonResponse({ error: "not_found" }, 404);
      return jsonResponse({ session: record });
    }
    if (match && request.method === "DELETE") {
      const key = teamSessionStorageKey(decodeURIComponent(match[1]));
      const deleted = this.records.delete(key);
      return jsonResponse({ deleted });
    }
    return jsonResponse({ error: "not_found" }, 404);
  }
}

class FakeBucket {
  objects = new Map<string, string>();

  async put(key: string, value: string): Promise<void> {
    this.objects.set(key, value);
  }

  async get(key: string): Promise<{ text(): Promise<string>; size: number } | null> {
    const value = this.objects.get(key);
    if (value === undefined) return null;
    return { text: async () => value, size: value.length };
  }

  async delete(key: string): Promise<void> {
    this.objects.delete(key);
  }
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function makeEnv(): { env: TeamSessionsEnv; bucket: FakeBucket } {
  const objects = new Map<string, FakeTeamSessionsObject>();
  const bucket = new FakeBucket();
  const env: TeamSessionsEnv = {
    TEAM_SESSIONS: {
      idFromName: (name: string) => name,
      get: (id: unknown) => {
        const key = String(id);
        let object = objects.get(key);
        if (object === undefined) {
          object = new FakeTeamSessionsObject();
          objects.set(key, object);
        }
        return object;
      },
    },
    TEAM_SESSION_TRANSCRIPTS: bucket,
    COLLABORATION_ADMIN_TOKEN: "admin-token",
    MOSAIC_NATIVE_AUTH_SECRET: SECRET,
  };
  return { env, bucket };
}

async function accessToken(overrides: Record<string, unknown> = {}): Promise<string> {
  return mintToken({
    kind: "access",
    userId: "user_1",
    displayName: "Alex",
    selectedTeamId: "org_1",
    teamIds: ["org_1"],
    exp: Math.floor(Date.now() / 1000) + 600,
    ...overrides,
  });
}

async function callHandler(
  env: TeamSessionsEnv,
  path: string,
  init: RequestInit = {},
): Promise<Response> {
  const request = new Request(`https://relay.test${path}`, init);
  const response = await teamSessionsFetch(request, new URL(request.url), env);
  if (response === null) throw new Error(`route not matched: ${path}`);
  return response;
}

async function syncSession(
  env: TeamSessionsEnv,
  token: string,
  body: Record<string, unknown>,
): Promise<Response> {
  return callHandler(env, "/v1/sessions/sync", {
    method: "POST",
    headers: { authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });
}

test("sync stores metadata and transcript, list and transcript read them back", async () => {
  const { env, bucket } = makeEnv();
  const token = await accessToken();

  const syncResponse = await syncSession(env, token, {
    teamId: "org_1",
    session: {
      sessionId: "session-1",
      title: "Fix login bug",
      gitBranch: "fix/login",
      turnCount: 2,
    },
    transcript: '{"type":"user"}\n{"type":"assistant"}\n',
  });
  expect(syncResponse.status).toBe(200);
  const synced = (await syncResponse.json()) as {
    teamId: string;
    session: TeamSessionRecord;
  };
  expect(synced.teamId).toBe("org_1");
  expect(synced.session.userId).toBe("user_1");
  expect(synced.session.transcriptBytes).toBeGreaterThan(0);
  expect(bucket.objects.has("sessions/org_1/session-1.jsonl")).toBe(true);

  const listResponse = await callHandler(env, "/v1/sessions?teamId=org_1", {
    headers: { authorization: `Bearer ${token}` },
  });
  expect(listResponse.status).toBe(200);
  const listed = (await listResponse.json()) as { sessions: TeamSessionRecord[] };
  expect(listed.sessions.map((session) => session.sessionId)).toEqual(["session-1"]);

  const transcriptResponse = await callHandler(
    env,
    "/v1/sessions/session-1/transcript?teamId=org_1",
    { headers: { authorization: `Bearer ${token}` } },
  );
  expect(transcriptResponse.status).toBe(200);
  expect(await transcriptResponse.text()).toBe('{"type":"user"}\n{"type":"assistant"}\n');
});

test("sync defaults the team to the token's selected team", async () => {
  const { env } = makeEnv();
  const token = await accessToken();

  const response = await syncSession(env, token, {
    session: { sessionId: "session-1" },
  });

  expect(response.status).toBe(200);
  const body = (await response.json()) as { teamId: string };
  expect(body.teamId).toBe("org_1");
});

test("requests without a valid token are unauthorized", async () => {
  const { env } = makeEnv();

  const noToken = await callHandler(env, "/v1/sessions?teamId=org_1");
  const badToken = await callHandler(env, "/v1/sessions?teamId=org_1", {
    headers: { authorization: "Bearer mosaicv1.garbage.garbage" },
  });
  const syncNoToken = await callHandler(env, "/v1/sessions/sync", {
    method: "POST",
    body: JSON.stringify({ session: { sessionId: "session-1" } }),
  });

  expect(noToken.status).toBe(401);
  expect(badToken.status).toBe(401);
  expect(syncNoToken.status).toBe(401);
});

test("a token cannot touch a team outside its claims", async () => {
  const { env } = makeEnv();
  const token = await accessToken();

  const syncResponse = await syncSession(env, token, {
    teamId: "org_other",
    session: { sessionId: "session-1" },
  });
  const listResponse = await callHandler(env, "/v1/sessions?teamId=org_other", {
    headers: { authorization: `Bearer ${token}` },
  });

  expect(syncResponse.status).toBe(403);
  expect(listResponse.status).toBe(403);
});

test("the admin token reads any team but must name it", async () => {
  const { env } = makeEnv();
  const token = await accessToken();
  await syncSession(env, token, { session: { sessionId: "session-1" } });

  const listed = await callHandler(env, "/v1/sessions?teamId=org_1", {
    headers: { "x-mosaic-admin-token": "admin-token" },
  });
  const missingTeam = await callHandler(env, "/v1/sessions", {
    headers: { "x-mosaic-admin-token": "admin-token" },
  });

  expect(listed.status).toBe(200);
  const body = (await listed.json()) as { sessions: TeamSessionRecord[] };
  expect(body.sessions).toHaveLength(1);
  expect(missingTeam.status).toBe(400);
});

test("another member cannot overwrite or delete someone else's session", async () => {
  const { env, bucket } = makeEnv();
  const owner = await accessToken();
  const other = await accessToken({ userId: "user_2", displayName: "Blake" });
  await syncSession(env, owner, {
    teamId: "org_1",
    session: { sessionId: "session-1" },
    transcript: "{}\n",
  });

  const overwrite = await syncSession(env, other, {
    teamId: "org_1",
    session: { sessionId: "session-1" },
    transcript: '{"forged":true}\n',
  });
  const deleteAttempt = await callHandler(env, "/v1/sessions/session-1?teamId=org_1", {
    method: "DELETE",
    headers: { authorization: `Bearer ${other}` },
  });

  expect(overwrite.status).toBe(403);
  expect(bucket.objects.get("sessions/org_1/session-1.jsonl")).toBe("{}\n");
  expect(deleteAttempt.status).toBe(403);
});

test("the owner can delete their session, removing metadata and transcript", async () => {
  const { env, bucket } = makeEnv();
  const token = await accessToken();
  await syncSession(env, token, {
    teamId: "org_1",
    session: { sessionId: "session-1" },
    transcript: "{}\n",
  });

  const deleteResponse = await callHandler(env, "/v1/sessions/session-1?teamId=org_1", {
    method: "DELETE",
    headers: { authorization: `Bearer ${token}` },
  });
  const getResponse = await callHandler(env, "/v1/sessions/session-1?teamId=org_1", {
    headers: { authorization: `Bearer ${token}` },
  });

  expect(deleteResponse.status).toBe(200);
  expect(getResponse.status).toBe(404);
  expect(bucket.objects.size).toBe(0);
});

test("teams are isolated from each other", async () => {
  const { env } = makeEnv();
  const orgOne = await accessToken();
  const orgTwo = await accessToken({
    userId: "user_2",
    selectedTeamId: "org_2",
    teamIds: ["org_2"],
  });
  await syncSession(env, orgOne, { session: { sessionId: "session-a" } });
  await syncSession(env, orgTwo, { session: { sessionId: "session-b" } });

  const orgTwoList = await callHandler(env, "/v1/sessions?teamId=org_2", {
    headers: { authorization: `Bearer ${orgTwo}` },
  });

  const body = (await orgTwoList.json()) as { sessions: TeamSessionRecord[] };
  expect(body.sessions.map((session) => session.sessionId)).toEqual(["session-b"]);
});

test("unmatched paths fall through to the main handler", async () => {
  const { env } = makeEnv();
  const request = new Request("https://relay.test/v1/collaboration/sessions", {
    method: "POST",
  });

  expect(await teamSessionsFetch(request, new URL(request.url), env)).toBeNull();
});
