// HTTP surface for the team coding-session corpus.
//
// The native app uploads each Claude Code session at turn boundaries
// (metadata + full transcript JSONL) and teammates list/pull them to continue
// a session locally. Metadata lives in a per-team TeamSessionsObject Durable
// Object; transcript bodies live in R2 under `sessions/<teamId>/<id>.jsonl`.
//
// Auth: writes require a www-minted `mosaicv1` access token whose claims
// include the target team (shared HMAC secret, see native-token.ts). Reads
// accept the same bearer token or the admin token (used by the www dashboard's
// server-side fetch, which already authenticated the browser via Clerk).

import {
  bearerTokenFromRequest,
  claimsAuthorizeTeam,
  verifyNativeAccessToken,
  type NativeAccessClaims,
} from "./native-token";
import { json } from "./protocol";
import {
  normalizeTeamId,
  normalizeTeamSessionId,
  transcriptObjectKey,
  type TeamSessionRecord,
} from "./team-sessions-record";

interface TeamSessionsStub {
  fetch(request: Request): Promise<Response>;
}

interface TeamSessionsNamespace {
  idFromName(name: string): unknown;
  get(id: unknown): TeamSessionsStub;
}

interface TranscriptBucketObject {
  text(): Promise<string>;
  size: number;
}

interface TranscriptBucket {
  put(key: string, value: string): Promise<unknown>;
  get(key: string): Promise<TranscriptBucketObject | null>;
  delete(key: string): Promise<void>;
}

export interface TeamSessionsEnv {
  TEAM_SESSIONS?: TeamSessionsNamespace;
  TEAM_SESSION_TRANSCRIPTS?: TranscriptBucket;
  COLLABORATION_ADMIN_TOKEN?: string;
  /// Shared HMAC secret with www (MOSAIC_NATIVE_AUTH_SECRET there); verifies
  /// the native app's `mosaicv1` access tokens. Set via `wrangler secret`.
  MOSAIC_NATIVE_AUTH_SECRET?: string;
}

/// Transcripts are typically KB-MB; cap the sync body well above that so a
/// runaway upload cannot buffer unbounded data into the worker.
const MAX_SYNC_BODY_BYTES = 32 * 1024 * 1024;

type TeamAuth =
  | { kind: "admin" }
  | { kind: "user"; claims: NativeAccessClaims };

/// Routes /v1/sessions* requests. Returns null when the path is not a team
/// sessions route so the main handler can keep matching.
export async function teamSessionsFetch(
  request: Request,
  url: URL,
  env: TeamSessionsEnv,
): Promise<Response | null> {
  if (url.pathname === "/v1/sessions/sync" && request.method === "POST") {
    return syncSession(request, env);
  }
  if (url.pathname === "/v1/sessions" && request.method === "GET") {
    return listSessions(request, url, env);
  }
  const transcriptMatch = url.pathname.match(/^\/v1\/sessions\/([^/]+)\/transcript$/);
  if (transcriptMatch && request.method === "GET") {
    return getTranscript(request, url, env, decodeURIComponent(transcriptMatch[1]));
  }
  const sessionMatch = url.pathname.match(/^\/v1\/sessions\/([^/]+)$/);
  if (sessionMatch && request.method === "GET") {
    return getSession(request, url, env, decodeURIComponent(sessionMatch[1]));
  }
  if (sessionMatch && request.method === "DELETE") {
    return deleteSession(request, url, env, decodeURIComponent(sessionMatch[1]));
  }
  return null;
}

async function syncSession(request: Request, env: TeamSessionsEnv): Promise<Response> {
  if (!env.TEAM_SESSIONS || !env.TEAM_SESSION_TRANSCRIPTS) {
    return json({ error: "team_sessions_disabled" }, 404);
  }
  const claims = await userClaims(request, env);
  if (claims === null) return json({ error: "unauthorized" }, 401);

  const lengthHeader = request.headers.get("content-length");
  if (lengthHeader !== null && Number(lengthHeader) > MAX_SYNC_BODY_BYTES) {
    return json({ error: "payload_too_large" }, 413);
  }
  let raw: string;
  try {
    raw = await request.text();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  if (raw.length > MAX_SYNC_BODY_BYTES) return json({ error: "payload_too_large" }, 413);
  let body: Record<string, unknown>;
  try {
    body = JSON.parse(raw) as Record<string, unknown>;
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return json({ error: "invalid_json" }, 400);
  }

  const teamId =
    normalizeTeamId(body.teamId) ??
    normalizeTeamId(claims.selectedTeamId) ??
    normalizeTeamId(claims.userId);
  if (teamId === null) return json({ error: "invalid_team" }, 400);
  if (!claimsAuthorizeTeam(claims, teamId)) return json({ error: "team_not_found" }, 403);

  const session =
    typeof body.session === "object" && body.session !== null && !Array.isArray(body.session)
      ? (body.session as Record<string, unknown>)
      : null;
  if (session === null) return json({ error: "invalid_session" }, 400);
  const sessionId = normalizeTeamSessionId(session.sessionId);
  if (sessionId === null) return json({ error: "invalid_session" }, 400);

  const transcript = typeof body.transcript === "string" ? body.transcript : null;
  let transcriptBytes: number | null = null;
  if (transcript !== null) {
    transcriptBytes = new TextEncoder().encode(transcript).byteLength;
  }

  // Upsert metadata first: the DO enforces session ownership, and a rejected
  // upsert must not overwrite another member's transcript in R2.
  const stub = teamSessionsStub(env, teamId);
  const upsertResponse = await stub.fetch(
    new Request("https://mosaic-team-sessions.local/sessions", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        session,
        userId: claims.userId,
        displayName: claims.displayName,
        ...(transcriptBytes !== null ? { transcriptBytes } : {}),
      }),
    }),
  );
  if (!upsertResponse.ok) {
    return json(await upsertResponse.json(), upsertResponse.status);
  }

  if (transcript !== null) {
    await env.TEAM_SESSION_TRANSCRIPTS.put(transcriptObjectKey(teamId, sessionId), transcript);
  }

  const result = (await upsertResponse.json()) as { session?: TeamSessionRecord };
  return json({ ok: true, teamId, session: result.session ?? null });
}

async function listSessions(
  request: Request,
  url: URL,
  env: TeamSessionsEnv,
): Promise<Response> {
  if (!env.TEAM_SESSIONS) return json({ error: "team_sessions_disabled" }, 404);
  const auth = await authorize(request, env);
  if (auth === null) return json({ error: "unauthorized" }, 401);
  const teamId = resolveTeamId(url, auth);
  if (teamId === null) return json({ error: "invalid_team" }, 400);
  if (!authAllowsTeam(auth, teamId)) return json({ error: "team_not_found" }, 403);

  const stub = teamSessionsStub(env, teamId);
  const listURL = new URL("https://mosaic-team-sessions.local/sessions");
  const limit = url.searchParams.get("limit");
  if (limit !== null) listURL.searchParams.set("limit", limit);
  const response = await stub.fetch(new Request(listURL, { method: "GET" }));
  const body = (await response.json()) as { sessions?: TeamSessionRecord[] };
  return json({ teamId, sessions: body.sessions ?? [] }, response.status);
}

async function getSession(
  request: Request,
  url: URL,
  env: TeamSessionsEnv,
  rawSessionId: string,
): Promise<Response> {
  if (!env.TEAM_SESSIONS) return json({ error: "team_sessions_disabled" }, 404);
  const auth = await authorize(request, env);
  if (auth === null) return json({ error: "unauthorized" }, 401);
  const teamId = resolveTeamId(url, auth);
  if (teamId === null) return json({ error: "invalid_team" }, 400);
  if (!authAllowsTeam(auth, teamId)) return json({ error: "team_not_found" }, 403);
  const sessionId = normalizeTeamSessionId(rawSessionId);
  if (sessionId === null) return json({ error: "invalid_session" }, 400);

  const stub = teamSessionsStub(env, teamId);
  const response = await stub.fetch(
    new Request(
      `https://mosaic-team-sessions.local/sessions/${encodeURIComponent(sessionId)}`,
      { method: "GET" },
    ),
  );
  const body = (await response.json()) as Record<string, unknown>;
  return json(response.ok ? { teamId, ...body } : body, response.status);
}

async function getTranscript(
  request: Request,
  url: URL,
  env: TeamSessionsEnv,
  rawSessionId: string,
): Promise<Response> {
  if (!env.TEAM_SESSIONS || !env.TEAM_SESSION_TRANSCRIPTS) {
    return json({ error: "team_sessions_disabled" }, 404);
  }
  const auth = await authorize(request, env);
  if (auth === null) return json({ error: "unauthorized" }, 401);
  const teamId = resolveTeamId(url, auth);
  if (teamId === null) return json({ error: "invalid_team" }, 400);
  if (!authAllowsTeam(auth, teamId)) return json({ error: "team_not_found" }, 403);
  const sessionId = normalizeTeamSessionId(rawSessionId);
  if (sessionId === null) return json({ error: "invalid_session" }, 400);

  const object = await env.TEAM_SESSION_TRANSCRIPTS.get(transcriptObjectKey(teamId, sessionId));
  if (object === null) return json({ error: "not_found" }, 404);
  return new Response(await object.text(), {
    status: 200,
    headers: { "content-type": "application/x-ndjson" },
  });
}

async function deleteSession(
  request: Request,
  url: URL,
  env: TeamSessionsEnv,
  rawSessionId: string,
): Promise<Response> {
  if (!env.TEAM_SESSIONS) return json({ error: "team_sessions_disabled" }, 404);
  const auth = await authorize(request, env);
  if (auth === null) return json({ error: "unauthorized" }, 401);
  const teamId = resolveTeamId(url, auth);
  if (teamId === null) return json({ error: "invalid_team" }, 400);
  if (!authAllowsTeam(auth, teamId)) return json({ error: "team_not_found" }, 403);
  const sessionId = normalizeTeamSessionId(rawSessionId);
  if (sessionId === null) return json({ error: "invalid_session" }, 400);

  const stub = teamSessionsStub(env, teamId);
  // Only the session owner (or the admin path) may delete: a teammate can
  // pull and fork a session but not remove it from its owner's corpus.
  if (auth.kind === "user") {
    const existingResponse = await stub.fetch(
      new Request(
        `https://mosaic-team-sessions.local/sessions/${encodeURIComponent(sessionId)}`,
        { method: "GET" },
      ),
    );
    if (existingResponse.status === 404) return json({ error: "not_found" }, 404);
    if (!existingResponse.ok) {
      return json(await existingResponse.json(), existingResponse.status);
    }
    const existing = (await existingResponse.json()) as { session?: TeamSessionRecord };
    if (existing.session?.userId !== auth.claims.userId) {
      return json({ error: "session_not_owned" }, 403);
    }
  }

  const response = await stub.fetch(
    new Request(
      `https://mosaic-team-sessions.local/sessions/${encodeURIComponent(sessionId)}`,
      { method: "DELETE" },
    ),
  );
  if (response.ok && env.TEAM_SESSION_TRANSCRIPTS) {
    try {
      await env.TEAM_SESSION_TRANSCRIPTS.delete(transcriptObjectKey(teamId, sessionId));
    } catch {
      // Metadata removal already succeeded; an orphaned transcript object is
      // unreachable through the API and harmless.
    }
  }
  const body = (await response.json()) as Record<string, unknown>;
  return json(body, response.status);
}

function teamSessionsStub(env: TeamSessionsEnv, teamId: string): TeamSessionsStub {
  const namespace = env.TEAM_SESSIONS;
  if (!namespace) throw new Error("TEAM_SESSIONS binding missing");
  return namespace.get(namespace.idFromName(teamId));
}

async function userClaims(
  request: Request,
  env: TeamSessionsEnv,
): Promise<NativeAccessClaims | null> {
  const secret = env.MOSAIC_NATIVE_AUTH_SECRET?.trim() ?? "";
  if (secret === "") return null;
  const token = bearerTokenFromRequest(request);
  if (token === null) return null;
  return verifyNativeAccessToken(token, secret);
}

async function authorize(request: Request, env: TeamSessionsEnv): Promise<TeamAuth | null> {
  const adminToken = env.COLLABORATION_ADMIN_TOKEN?.trim();
  const providedAdmin = request.headers.get("x-mosaic-admin-token")?.trim();
  if (adminToken && providedAdmin === adminToken) return { kind: "admin" };
  const claims = await userClaims(request, env);
  return claims === null ? null : { kind: "user", claims };
}

function resolveTeamId(url: URL, auth: TeamAuth): string | null {
  const requested = normalizeTeamId(url.searchParams.get("teamId"));
  if (requested !== null) return requested;
  if (auth.kind === "user") {
    return normalizeTeamId(auth.claims.selectedTeamId) ?? normalizeTeamId(auth.claims.userId);
  }
  // Admin reads are on behalf of a dashboard org and must name the team.
  return null;
}

function authAllowsTeam(auth: TeamAuth, teamId: string): boolean {
  return auth.kind === "admin" || claimsAuthorizeTeam(auth.claims, teamId);
}
