import { json, normalizeSessionCode, randomSessionCode, type SessionCreateResponse } from "./protocol";

interface CollaborationSessionStub {
  create(sessionCode: string): Promise<{ metadata: SessionCreateResponse; created: boolean }>;
  fetch(request: Request): Promise<Response>;
}

interface CollaborationSessionNamespace {
  idFromName(name: string): unknown;
  get(id: unknown): CollaborationSessionStub;
}

export interface CollaborationWorkerEnv {
  COLLABORATION_SESSIONS: CollaborationSessionNamespace;
}

const CREATE_SESSION_MAX_ATTEMPTS = 8;

export async function collaborationFetch(request: Request, env: CollaborationWorkerEnv): Promise<Response> {
  const url = new URL(request.url);

  if (url.pathname === "/healthz") {
    return json({ ok: true, service: "cmux-collaboration" });
  }

  if (url.pathname === "/v1/collaboration/sessions" && request.method === "POST") {
    for (let attempt = 0; attempt < CREATE_SESSION_MAX_ATTEMPTS; attempt += 1) {
      const sessionCode = randomSessionCode();
      const stub = env.COLLABORATION_SESSIONS.get(env.COLLABORATION_SESSIONS.idFromName(sessionCode));
      const result = await stub.create(sessionCode);
      if (result.created) return json(result.metadata, 201);
    }
    return json({ error: "session_code_exhausted" }, 503);
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
