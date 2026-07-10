import { DurableObject } from "cloudflare:workers";
import { json } from "./protocol";
import {
  normalizedTeamSessionListLimit,
  normalizeTeamSessionId,
  sortedByActivity,
  TEAM_SESSION_KEY_PREFIX,
  teamSessionRecordForUpsert,
  teamSessionStorageKey,
  type TeamSessionRecord,
} from "./team-sessions-record";

/// One synced session index per team (Durable Object named by team id).
/// Stores session metadata records only; transcript bodies live in R2 and are
/// read/written by the worker handler, not this object.
///
/// Internal protocol (worker handler -> DO):
///   POST /sessions            upsert from a sync request
///   GET  /sessions?limit=     list, most recently active first
///   GET  /sessions/:id        single record
///   DELETE /sessions/:id      remove a record (owner-checked by the handler)
export class TeamSessionsObject extends DurableObject {
  override async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/sessions" && request.method === "POST") {
      return this.upsert(request);
    }
    if (url.pathname === "/sessions" && request.method === "GET") {
      return this.list(url);
    }
    const sessionMatch = url.pathname.match(/^\/sessions\/([^/]+)$/);
    if (sessionMatch && request.method === "GET") {
      return this.get(decodeURIComponent(sessionMatch[1]));
    }
    if (sessionMatch && request.method === "DELETE") {
      return this.delete(decodeURIComponent(sessionMatch[1]));
    }
    return json({ error: "not_found" }, 404);
  }

  private async upsert(request: Request): Promise<Response> {
    let payload: {
      session?: Record<string, unknown>;
      userId?: string;
      displayName?: string | null;
      transcriptBytes?: number;
    };
    try {
      payload = await request.json();
    } catch {
      return json({ error: "invalid_json" }, 400);
    }
    if (
      typeof payload.userId !== "string" ||
      payload.userId === "" ||
      typeof payload.session !== "object" ||
      payload.session === null
    ) {
      return json({ error: "invalid_session" }, 400);
    }

    const sessionId = normalizeTeamSessionId(payload.session.sessionId);
    if (sessionId === null) return json({ error: "invalid_session" }, 400);

    const key = teamSessionStorageKey(sessionId);
    const existing = (await this.ctx.storage.get<TeamSessionRecord>(key)) ?? null;
    // A session id belongs to whoever synced it first; another team member
    // re-using the id cannot overwrite the record (forks get their own ids).
    if (existing !== null && existing.userId !== payload.userId) {
      return json({ error: "session_not_owned" }, 403);
    }

    const record = teamSessionRecordForUpsert({
      body: payload.session,
      userId: payload.userId,
      displayName: payload.displayName ?? null,
      transcriptBytes:
        typeof payload.transcriptBytes === "number" && payload.transcriptBytes >= 0
          ? Math.trunc(payload.transcriptBytes)
          : (existing?.transcriptBytes ?? 0),
      existing,
    });
    if (record === null) return json({ error: "invalid_session" }, 400);

    await this.ctx.storage.put(key, record);
    return json({ recorded: true, session: record });
  }

  private async list(url: URL): Promise<Response> {
    const limit = normalizedTeamSessionListLimit(url.searchParams.get("limit"));
    const entries = await this.ctx.storage.list<TeamSessionRecord>({
      prefix: TEAM_SESSION_KEY_PREFIX,
    });
    const sessions = sortedByActivity([...entries.values()]).slice(0, limit);
    return json({ sessions });
  }

  private async get(rawSessionId: string): Promise<Response> {
    const sessionId = normalizeTeamSessionId(rawSessionId);
    if (sessionId === null) return json({ error: "invalid_session" }, 400);
    const record = await this.ctx.storage.get<TeamSessionRecord>(
      teamSessionStorageKey(sessionId),
    );
    if (record === undefined) return json({ error: "not_found" }, 404);
    return json({ session: record });
  }

  private async delete(rawSessionId: string): Promise<Response> {
    const sessionId = normalizeTeamSessionId(rawSessionId);
    if (sessionId === null) return json({ error: "invalid_session" }, 400);
    const deleted = await this.ctx.storage.delete(teamSessionStorageKey(sessionId));
    return json({ deleted, sessionId });
  }
}
