import { DurableObject } from "cloudflare:workers";
import { json } from "./protocol";
import { CollaborationInboxState } from "./inbox-state";

// Idle connections are swept after this window; clients heartbeat well within it.
const INBOX_HEARTBEAT_TIMEOUT_MS = 60_000;

/// One Durable Object per user (addressed via idFromName(userID)). It holds the
/// user's live inbox WebSockets and fans out lightweight "check your inbox"
/// nudges. It intentionally stores no invite data — www remains authoritative.
export class CollaborationInboxObject extends DurableObject {
  private state = new CollaborationInboxState();

  override async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname.endsWith("/connect")) {
      return this.handleConnect(request);
    }
    if (url.pathname === "/notify" && request.method === "POST") {
      return this.handleNotify(request);
    }
    return json({ error: "not_found" }, 404);
  }

  private async handleConnect(request: Request): Promise<Response> {
    if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") {
      return new Response("expected websocket", { status: 426 });
    }
    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    const now = Date.now();
    const connectionID = crypto.randomUUID();
    server.accept();
    this.state.addConnection(connectionID, server, now);
    server.addEventListener("message", (event) =>
      this.state.handleMessage(connectionID, event.data, Date.now()),
    );
    server.addEventListener("close", () =>
      this.state.dropConnection(connectionID),
    );
    server.addEventListener("error", () =>
      this.state.dropConnection(connectionID),
    );
    await this.ensureHeartbeatAlarm(now);
    return new Response(null, { status: 101, webSocket: client });
  }

  private async handleNotify(request: Request): Promise<Response> {
    let reason = "invite";
    try {
      const body = (await request.json()) as { reason?: unknown };
      if (typeof body?.reason === "string" && body.reason.trim() !== "") {
        reason = body.reason;
      }
    } catch {
      // The notify body is optional; fall back to the default reason.
    }
    const delivered = this.state.notify(reason, Date.now());
    return json({ delivered });
  }

  override async alarm(): Promise<void> {
    const now = Date.now();
    this.state.expire(now, INBOX_HEARTBEAT_TIMEOUT_MS);
    if (this.state.connectionCount > 0) {
      await this.ensureHeartbeatAlarm(now);
    }
  }

  private async ensureHeartbeatAlarm(now = Date.now()): Promise<void> {
    await this.ctx.storage.setAlarm(now + INBOX_HEARTBEAT_TIMEOUT_MS);
  }
}
