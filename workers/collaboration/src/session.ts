import { DurableObject } from "cloudflare:workers";
import { parsePeer } from "./protocol";
import { CollaborationRelaySessionState } from "./session-state";
import {
  createSessionMetadataIfAbsent,
  deleteSessionMetadata,
  readSessionMetadata,
  type SessionMetadata,
  type SessionMetadataCreateResult,
} from "./session-metadata";

interface CollaborationSessionIndexStub {
  fetch(request: Request): Promise<Response>;
}

interface CollaborationSessionIndexNamespace {
  idFromName(name: string): unknown;
  get(id: unknown): CollaborationSessionIndexStub;
}

export interface CollaborationSessionObjectEnv {
  COLLABORATION_SESSION_INDEX?: CollaborationSessionIndexNamespace;
}

const HEARTBEAT_TIMEOUT_MS = 30_000;
const EMPTY_SESSION_GRACE_MS = 10 * 60_000;
const IDLE_CLEANUP_DUE_AT_KEY = "idleCleanupDueAt";
const SESSION_INDEX_OBJECT_NAME = "global";
const liveSessionStates = new Map<string, CollaborationRelaySessionState>();

export class CollaborationSessionObject extends DurableObject<CollaborationSessionObjectEnv> {
  private metadata: SessionMetadata | null = null;
  private state = new CollaborationRelaySessionState();

  async create(sessionCode: string): Promise<SessionMetadataCreateResult> {
    // Uniqueness is scoped to this Durable Object: every candidate code maps to
    // one object via idFromName(sessionCode), and DO input gates serialize calls
    // here before storage is read or written.
    if (this.metadata !== null) return { metadata: this.metadata, created: false };
    const result = await createSessionMetadataIfAbsent(this.ctx.storage, sessionCode);
    this.metadata = result.metadata;
    if (this.state.peerCount === 0) await this.scheduleIdleCleanup();
    return result;
  }

  override async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname.endsWith("/connect")) {
      return this.handleConnect(request);
    }
    if (url.pathname === "/metadata" && request.method === "GET") {
      const metadata = await this.loadMetadata();
      if (metadata === null) {
        return new Response(JSON.stringify({ error: "session_not_found" }), {
          status: 404,
          headers: { "content-type": "application/json" },
        });
      }
      return new Response(JSON.stringify({ metadata }), {
        headers: { "content-type": "application/json" },
      });
    }
    return new Response("not found", { status: 404 });
  }

  private async handleConnect(request: Request): Promise<Response> {
    if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") {
      return new Response("expected websocket", { status: 426 });
    }
    const metadata = await this.loadMetadata();
    if (metadata === null) {
      return new Response(JSON.stringify({ error: "session_not_found" }), { status: 404 });
    }
    const url = new URL(request.url);
    const peer = parsePeer({
      peerID: url.searchParams.get("peerID"),
      participantID: url.searchParams.get("participantID"),
      displayName: url.searchParams.get("displayName"),
      color: url.searchParams.get("color"),
      imageURL: url.searchParams.get("imageURL"),
    });
    if (peer === null) {
      return new Response(JSON.stringify({ error: "invalid_peer" }), { status: 400 });
    }

    const state = this.stateFor(metadata.sessionID);
    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    const now = Date.now();
    server.accept();
    await this.cancelIdleCleanup();
    state.addPeer(metadata.sessionID, peer, server, now);
    server.addEventListener("message", (event) => state.handleMessage(peer.peerID, event.data, Date.now()));
    server.addEventListener("close", () => this.dropPeer(metadata.sessionID, peer.peerID, "disconnect"));
    server.addEventListener("error", () => this.dropPeer(metadata.sessionID, peer.peerID, "disconnect"));
    await this.ensureHeartbeatAlarm(now);
    return new Response(null, { status: 101, webSocket: client });
  }

  override async alarm(): Promise<void> {
    const now = Date.now();
    this.state.expire(now, HEARTBEAT_TIMEOUT_MS);
    if (this.state.peerCount > 0) {
      await this.cancelIdleCleanup();
      await this.ensureHeartbeatAlarm(now);
      return;
    }
    await this.runIdleCleanup(now);
  }

  private async ensureHeartbeatAlarm(now = Date.now()): Promise<void> {
    await this.ctx.storage.setAlarm(now + HEARTBEAT_TIMEOUT_MS);
  }

  private async scheduleIdleCleanup(now = Date.now()): Promise<void> {
    const metadata = await this.loadMetadata();
    if (metadata === null) return;
    if (this.state.peerCount > 0) return;
    const dueAt = now + EMPTY_SESSION_GRACE_MS;
    await this.ctx.storage.put(IDLE_CLEANUP_DUE_AT_KEY, dueAt);
    await this.ctx.storage.setAlarm(dueAt);
  }

  private async cancelIdleCleanup(): Promise<void> {
    await this.ctx.storage.delete(IDLE_CLEANUP_DUE_AT_KEY);
  }

  private async runIdleCleanup(now: number): Promise<void> {
    const dueAt = await this.ctx.storage.get<number>(IDLE_CLEANUP_DUE_AT_KEY);
    if (dueAt === undefined) {
      await this.scheduleIdleCleanup(now);
      return;
    }
    if (now < dueAt) {
      await this.ctx.storage.setAlarm(dueAt);
      return;
    }
    const metadata = await this.loadMetadata();
    await deleteSessionMetadata(this.ctx.storage);
    await this.ctx.storage.delete(IDLE_CLEANUP_DUE_AT_KEY);
    this.metadata = null;
    if (metadata !== null) await this.deleteIndexedSession(metadata.sessionCode);
  }

  private async deleteIndexedSession(sessionCode: string): Promise<void> {
    const namespace = this.env.COLLABORATION_SESSION_INDEX;
    if (!namespace) return;
    const stub = namespace.get(namespace.idFromName(SESSION_INDEX_OBJECT_NAME));
    try {
      await stub.fetch(new Request(
        `https://mosaic-collaboration-index.local/sessions/${encodeURIComponent(sessionCode)}`,
        { method: "DELETE" }
      ));
    } catch (error) {
      console.warn("failed to delete collaboration session index", error);
    }
  }

  private async loadMetadata(): Promise<SessionMetadata | null> {
    if (this.metadata !== null) return this.metadata;
    this.metadata = await readSessionMetadata(this.ctx.storage);
    return this.metadata;
  }

  private stateFor(sessionID: string): CollaborationRelaySessionState {
    let state = liveSessionStates.get(sessionID);
    if (state === undefined) {
      state = new CollaborationRelaySessionState();
      liveSessionStates.set(sessionID, state);
    }
    this.state = state;
    return state;
  }

  private dropPeer(
    sessionID: string,
    peerID: string,
    reason: "disconnect" | "timeout" | "leave",
  ): void {
    const state = this.stateFor(sessionID);
    state.dropPeer(peerID, reason);
    if (state.peerCount === 0) {
      liveSessionStates.delete(sessionID);
      this.ctx.waitUntil(this.scheduleIdleCleanup());
    }
  }
}
