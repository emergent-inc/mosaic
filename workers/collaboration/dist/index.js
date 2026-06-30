var __defProp = Object.defineProperty;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

// src/session.ts
import { DurableObject } from "cloudflare:workers";

// src/protocol.ts
function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" }
  });
}
__name(json, "json");
function parsePeer(value) {
  if (typeof value !== "object" || value === null) return null;
  const record = value;
  if (typeof record.peerID !== "string" || record.peerID.trim() === "") return null;
  if (typeof record.displayName !== "string" || record.displayName.trim() === "") return null;
  if (typeof record.color !== "string" || record.color.trim() === "") return null;
  return {
    peerID: record.peerID,
    displayName: record.displayName,
    color: record.color
  };
}
__name(parsePeer, "parsePeer");
function parseEnvelope(message) {
  const text = typeof message === "string" ? message : new TextDecoder().decode(message);
  if (text.length > 1024 * 1024) return null;
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    return null;
  }
  if (typeof parsed !== "object" || parsed === null) return null;
  const record = parsed;
  return typeof record.type === "string" ? record : null;
}
__name(parseEnvelope, "parseEnvelope");
function randomToken(bytes = 18) {
  const values = new Uint8Array(bytes);
  crypto.getRandomValues(values);
  return [...values].map((value) => value.toString(16).padStart(2, "0")).join("");
}
__name(randomToken, "randomToken");
function randomSessionCode() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const values = new Uint8Array(8);
  crypto.getRandomValues(values);
  const chars = [...values].map((value) => alphabet[value % alphabet.length]);
  return `${chars.slice(0, 4).join("")}-${chars.slice(4).join("")}`;
}
__name(randomSessionCode, "randomSessionCode");

// src/session-state.ts
var CollaborationRelaySessionState = class {
  static {
    __name(this, "CollaborationRelaySessionState");
  }
  peers = /* @__PURE__ */ new Map();
  get peerCount() {
    return this.peers.size;
  }
  addPeer(sessionID, peer, socket, now) {
    this.peers.set(peer.peerID, { peer, socket, lastHeartbeatAt: now });
    socket.send(JSON.stringify({
      type: "session.joined",
      sessionID,
      peers: [...this.peers.values()].map((entry) => entry.peer)
    }));
    this.broadcast(peer.peerID, { type: "peer.joined", peer });
  }
  handleMessage(peerID, data, now) {
    const entry = this.peers.get(peerID);
    if (!entry) return;
    const envelope = parseEnvelope(data);
    if (envelope === null) {
      this.closePeer(peerID, 1003, "invalid frame");
      this.dropPeer(peerID, "disconnect");
      return;
    }
    if (envelope.type === "peer.heartbeat") {
      entry.lastHeartbeatAt = now;
      this.peers.set(peerID, entry);
      return;
    }
    this.broadcast(peerID, { ...envelope, fromPeerID: peerID, receivedAt: now });
  }
  expire(now, timeoutMs) {
    for (const [peerID, entry] of this.peers) {
      if (now - entry.lastHeartbeatAt > timeoutMs) {
        this.closePeer(peerID, 1001, "heartbeat timeout");
        this.dropPeer(peerID, "timeout");
      }
    }
  }
  dropPeer(peerID, reason) {
    if (!this.peers.delete(peerID)) return;
    this.broadcast(peerID, { type: "peer.left", peerID, reason });
  }
  broadcast(fromPeerID, body) {
    const encoded = JSON.stringify(body);
    for (const [peerID, entry] of this.peers) {
      if (peerID === fromPeerID) continue;
      try {
        entry.socket.send(encoded);
      } catch {
        this.dropPeer(peerID, "disconnect");
      }
    }
  }
  closePeer(peerID, code, reason) {
    const entry = this.peers.get(peerID);
    if (!entry) return;
    try {
      entry.socket.close(code, reason);
    } catch {
    }
  }
};

// src/session-metadata.ts
var METADATA_KEY = "metadata";
async function createSessionMetadata(storage, sessionCode) {
  const existing = await readSessionMetadata(storage);
  if (existing) return existing;
  const metadata = {
    sessionID: sessionCode,
    sessionCode,
    token: randomToken()
  };
  await storage.put(METADATA_KEY, metadata);
  return metadata;
}
__name(createSessionMetadata, "createSessionMetadata");
async function readSessionMetadata(storage) {
  return await storage.get(METADATA_KEY) ?? null;
}
__name(readSessionMetadata, "readSessionMetadata");

// src/session.ts
var HEARTBEAT_TIMEOUT_MS = 3e4;
var liveSessionStates = /* @__PURE__ */ new Map();
var CollaborationSessionObject = class extends DurableObject {
  static {
    __name(this, "CollaborationSessionObject");
  }
  metadata = null;
  state = new CollaborationRelaySessionState();
  async create(sessionCode) {
    if (this.metadata !== null) return this.metadata;
    this.metadata = await createSessionMetadata(this.ctx.storage, sessionCode);
    return this.metadata;
  }
  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname.endsWith("/connect")) {
      return this.handleConnect(request);
    }
    return new Response("not found", { status: 404 });
  }
  async handleConnect(request) {
    if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") {
      return new Response("expected websocket", { status: 426 });
    }
    const metadata = await this.loadMetadata();
    if (metadata === null) {
      return new Response(JSON.stringify({ error: "session_not_found" }), { status: 404 });
    }
    const url = new URL(request.url);
    if (url.searchParams.get("token") !== metadata.token) {
      return new Response(JSON.stringify({ error: "invalid_token" }), { status: 403 });
    }
    const peer = parsePeer({
      peerID: url.searchParams.get("peerID"),
      displayName: url.searchParams.get("displayName"),
      color: url.searchParams.get("color")
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
    state.addPeer(metadata.sessionID, peer, server, now);
    server.addEventListener("message", (event) => state.handleMessage(peer.peerID, event.data, Date.now()));
    server.addEventListener("close", () => this.dropPeer(metadata.sessionID, peer.peerID, "disconnect"));
    server.addEventListener("error", () => this.dropPeer(metadata.sessionID, peer.peerID, "disconnect"));
    await this.ensureAlarm();
    return new Response(null, { status: 101, webSocket: client });
  }
  async alarm() {
    this.state.expire(Date.now(), HEARTBEAT_TIMEOUT_MS);
    if (this.state.peerCount > 0) await this.ensureAlarm();
  }
  async ensureAlarm() {
    await this.ctx.storage.setAlarm(Date.now() + HEARTBEAT_TIMEOUT_MS);
  }
  async loadMetadata() {
    if (this.metadata !== null) return this.metadata;
    this.metadata = await readSessionMetadata(this.ctx.storage);
    return this.metadata;
  }
  stateFor(sessionID) {
    let state = liveSessionStates.get(sessionID);
    if (state === void 0) {
      state = new CollaborationRelaySessionState();
      liveSessionStates.set(sessionID, state);
    }
    this.state = state;
    return state;
  }
  dropPeer(sessionID, peerID, reason) {
    const state = this.stateFor(sessionID);
    state.dropPeer(peerID, reason);
    if (state.peerCount === 0) {
      liveSessionStates.delete(sessionID);
    }
  }
};

// src/handler.ts
async function collaborationFetch(request, env) {
  const url = new URL(request.url);
  if (url.pathname === "/healthz") {
    return json({ ok: true, service: "cmux-collaboration" });
  }
  if (url.pathname === "/v1/collaboration/sessions" && request.method === "POST") {
    const sessionCode = randomSessionCode();
    const stub = env.COLLABORATION_SESSIONS.get(env.COLLABORATION_SESSIONS.idFromName(sessionCode));
    return json(await stub.create(sessionCode), 201);
  }
  const match = url.pathname.match(/^\/v1\/collaboration\/sessions\/([A-Z0-9-]+)\/connect$/);
  if (match && request.method === "GET") {
    const sessionCode = match[1];
    const stub = env.COLLABORATION_SESSIONS.get(env.COLLABORATION_SESSIONS.idFromName(sessionCode));
    return stub.fetch(request);
  }
  return json({ error: "not_found" }, 404);
}
__name(collaborationFetch, "collaborationFetch");

// src/index.ts
var index_default = {
  async fetch(request, env) {
    return collaborationFetch(request, env);
  }
};
export {
  CollaborationSessionObject,
  index_default as default
};
//# sourceMappingURL=index.js.map
