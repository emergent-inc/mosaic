import { json, normalizeSessionCode, randomSessionCode, type SessionCreateResponse } from "./protocol";

interface CollaborationSessionStub {
  create(sessionCode: string): Promise<{ metadata: SessionCreateResponse; created: boolean }>;
  fetch(request: Request): Promise<Response>;
}

interface CollaborationSessionIndexStub {
  fetch(request: Request): Promise<Response>;
}

interface CollaborationSessionNamespace {
  idFromName(name: string): unknown;
  get(id: unknown): CollaborationSessionStub;
}

interface CollaborationSessionIndexNamespace {
  idFromName(name: string): unknown;
  get(id: unknown): CollaborationSessionIndexStub;
}

export interface CollaborationWorkerEnv {
  COLLABORATION_SESSIONS: CollaborationSessionNamespace;
  COLLABORATION_SESSION_INDEX?: CollaborationSessionIndexNamespace;
  COLLABORATION_ADMIN_TOKEN?: string;
}

const SESSION_INDEX_OBJECT_NAME = "global";

export async function collaborationFetch(request: Request, env: CollaborationWorkerEnv): Promise<Response> {
  const url = new URL(request.url);

  if (url.pathname === "/healthz") {
    return json({ ok: true, service: "cmux-collaboration" });
  }

  if (url.pathname === "/v1/collaboration/sessions" && request.method === "POST") {
    const metadata = await createUniqueSession(env);
    await recordIndexedSession(env, metadata);
    return json(metadata, 201);
  }

  if (url.pathname === "/v1/collaboration/admin/sessions" && request.method === "GET") {
    const adminError = requireAdminToken(request, env);
    if (adminError) return adminError;
    return listIndexedSessions(url, env);
  }

  const adminSessionMatch = url.pathname.match(/^\/v1\/collaboration\/admin\/sessions\/([^/]+)$/);
  if (adminSessionMatch && request.method === "GET") {
    const adminError = requireAdminToken(request, env);
    if (adminError) return adminError;
    return describeSessionCode(decodeURIComponent(adminSessionMatch[1]), env);
  }

  const match = url.pathname.match(/^\/v1\/collaboration\/sessions\/([^/]+)\/connect$/);
  if (match && request.method === "GET") {
    const sessionCode = normalizeSessionCode(decodeURIComponent(match[1]));
    if (!sessionCode) return json({ error: "invalid_session_code" }, 400);
    const stub = env.COLLABORATION_SESSIONS.get(env.COLLABORATION_SESSIONS.idFromName(sessionCode));
    return stub.fetch(request);
  }

  return json({ error: "not_found" }, 404);
}

async function createUniqueSession(env: CollaborationWorkerEnv): Promise<SessionCreateResponse> {
  while (true) {
    const sessionCode = randomSessionCode();
    const stub = env.COLLABORATION_SESSIONS.get(env.COLLABORATION_SESSIONS.idFromName(sessionCode));
    const result = await stub.create(sessionCode);
    if (result.created) return result.metadata;
  }
}

async function recordIndexedSession(env: CollaborationWorkerEnv, metadata: SessionCreateResponse): Promise<void> {
  if (!env.COLLABORATION_SESSION_INDEX) return;
  const stub = env.COLLABORATION_SESSION_INDEX.get(
    env.COLLABORATION_SESSION_INDEX.idFromName(SESSION_INDEX_OBJECT_NAME)
  );
  try {
    await stub.fetch(new Request("https://cmux-collaboration-index.local/sessions", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(metadata),
    }));
  } catch (error) {
    console.warn("failed to record collaboration session index", error);
  }
}

function requireAdminToken(request: Request, env: CollaborationWorkerEnv): Response | null {
  const expectedToken = env.COLLABORATION_ADMIN_TOKEN?.trim();
  if (!expectedToken) return json({ error: "admin_index_disabled" }, 404);
  const providedToken = request.headers.get("x-cmux-admin-token")?.trim();
  if (providedToken !== expectedToken) return json({ error: "forbidden" }, 403);
  return null;
}

async function listIndexedSessions(url: URL, env: CollaborationWorkerEnv): Promise<Response> {
  if (!env.COLLABORATION_SESSION_INDEX) return json({ error: "admin_index_disabled" }, 404);
  const stub = env.COLLABORATION_SESSION_INDEX.get(
    env.COLLABORATION_SESSION_INDEX.idFromName(SESSION_INDEX_OBJECT_NAME)
  );
  const indexURL = new URL("https://cmux-collaboration-index.local/sessions");
  indexURL.search = url.search;
  const response = await stub.fetch(new Request(indexURL, { method: "GET" }));
  const body = await response.json() as {
    sessions?: Array<Record<string, unknown>>;
    cursor?: string | null;
  };
  return json({
    ...body,
    sessions: (body.sessions ?? []).map((session) => {
      const code = typeof session.sessionCode === "string"
        ? normalizeSessionCode(session.sessionCode)
        : null;
      return code === null
        ? session
        : { ...session, durableObjectID: durableObjectIDForSessionCode(env, code) };
    }),
  }, response.status);
}

async function describeSessionCode(rawCode: string, env: CollaborationWorkerEnv): Promise<Response> {
  const sessionCode = normalizeSessionCode(rawCode);
  if (sessionCode === null) return json({ error: "invalid_session_code" }, 400);
  const durableObjectID = durableObjectIDForSessionCode(env, sessionCode);
  const metadataResponse = await sessionMetadataResponse(env, sessionCode);
  const indexed = await indexedSessionRecord(env, sessionCode);
  if (metadataResponse.status === 404) {
    return json({
      sessionCode,
      durableObjectID,
      indexed: indexed !== null,
      active: false,
      metadata: null,
      indexedSession: indexed,
    });
  }
  if (!metadataResponse.ok) {
    return json({
      sessionCode,
      durableObjectID,
      indexed: indexed !== null,
      active: false,
      metadata: null,
      indexedSession: indexed,
      error: "metadata_lookup_failed",
    }, 502);
  }
  const body = await metadataResponse.json() as { metadata?: SessionCreateResponse };
  return json({
    sessionCode,
    durableObjectID,
    indexed: indexed !== null,
    active: body.metadata !== undefined,
    metadata: body.metadata ?? null,
    indexedSession: indexed,
  });
}

function durableObjectIDForSessionCode(env: CollaborationWorkerEnv, sessionCode: string): string {
  return String(env.COLLABORATION_SESSIONS.idFromName(sessionCode));
}

async function sessionMetadataResponse(env: CollaborationWorkerEnv, sessionCode: string): Promise<Response> {
  const id = env.COLLABORATION_SESSIONS.idFromName(sessionCode);
  const stub = env.COLLABORATION_SESSIONS.get(id);
  return stub.fetch(new Request("https://cmux-collaboration-session.local/metadata", { method: "GET" }));
}

async function indexedSessionRecord(
  env: CollaborationWorkerEnv,
  sessionCode: string
): Promise<Record<string, unknown> | null> {
  if (!env.COLLABORATION_SESSION_INDEX) return null;
  const stub = env.COLLABORATION_SESSION_INDEX.get(
    env.COLLABORATION_SESSION_INDEX.idFromName(SESSION_INDEX_OBJECT_NAME)
  );
  const response = await stub.fetch(new Request(
    "https://cmux-collaboration-index.local/sessions?limit=500",
    { method: "GET" }
  ));
  if (!response.ok) return null;
  const body = await response.json() as { sessions?: Array<Record<string, unknown>> };
  return (body.sessions ?? []).find((session) => session.sessionCode === sessionCode) ?? null;
}
