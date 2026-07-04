import { DurableObject } from "cloudflare:workers";
import { json, type SessionCreateResponse } from "./protocol";
import {
  indexedSessionFromBody,
  indexedSessionStorageKey,
  normalizedIndexListLimit,
  SESSION_INDEX_KEY_PREFIX,
  type IndexedCollaborationSession,
} from "./session-index-record";

export class CollaborationSessionIndexObject extends DurableObject {
  override async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/sessions" && request.method === "POST") {
      return this.record(request);
    }
    if (url.pathname === "/sessions" && request.method === "GET") {
      return this.list(url);
    }
    const deleteMatch = url.pathname.match(/^\/sessions\/([^/]+)$/);
    if (deleteMatch && request.method === "DELETE") {
      return this.delete(decodeURIComponent(deleteMatch[1]));
    }
    return json({ error: "not_found" }, 404);
  }

  private async record(request: Request): Promise<Response> {
    let body: Partial<SessionCreateResponse>;
    try {
      body = await request.json();
    } catch {
      return json({ error: "invalid_json" }, 400);
    }

    const record = indexedSessionFromBody(body);
    if (record === null) {
      return json({ error: "invalid_session" }, 400);
    }

    const key = indexedSessionStorageKey(record.sessionCode);
    if (key === null) return json({ error: "invalid_session" }, 400);
    await this.ctx.storage.put(key, record);
    return json({ recorded: true });
  }

  private async delete(rawSessionCode: string): Promise<Response> {
    const key = indexedSessionStorageKey(rawSessionCode);
    if (key === null) {
      return json({ error: "invalid_session" }, 400);
    }

    const deleted = await this.ctx.storage.delete(key);
    return json({ deleted, sessionCode: key.slice(SESSION_INDEX_KEY_PREFIX.length) });
  }

  private async list(url: URL): Promise<Response> {
    const limit = normalizedIndexListLimit(url.searchParams.get("limit"));
    const startAfter = url.searchParams.get("cursor") ?? undefined;
    const entries = await this.ctx.storage.list<IndexedCollaborationSession>({
      prefix: SESSION_INDEX_KEY_PREFIX,
      startAfter,
      limit,
    });
    const sessions = [...entries.values()].sort((left, right) => right.createdAt - left.createdAt);
    const keys = [...entries.keys()];
    return json({
      sessions,
      cursor: keys.length === limit ? keys[keys.length - 1] : null,
    });
  }
}
