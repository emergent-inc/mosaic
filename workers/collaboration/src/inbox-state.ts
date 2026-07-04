import { parseEnvelope } from "./protocol";

export interface InboxSocket {
  send(data: string): void;
  close(code: number, reason: string): void;
}

interface InboxConnection {
  socket: InboxSocket;
  lastHeartbeatAt: number;
}

/// Push frame telling a client to refetch its authoritative inbox from www.
export const INBOX_NUDGE_TYPE = "inbox.invite";
/// Client keepalive frame; keeps the connection out of the expiry sweep.
export const INBOX_HEARTBEAT_TYPE = "inbox.heartbeat";

/// In-memory fan-out for a single user's inbox channel. The relay never carries
/// invite contents: it only nudges connected clients to refetch from www.
export class CollaborationInboxState {
  private connections = new Map<string, InboxConnection>();

  get connectionCount(): number {
    return this.connections.size;
  }

  addConnection(connectionID: string, socket: InboxSocket, now: number): void {
    this.connections.set(connectionID, { socket, lastHeartbeatAt: now });
    // Nudge immediately so a freshly (re)connected client reconciles any invites
    // it may have missed while offline.
    try {
      socket.send(
        JSON.stringify({ type: INBOX_NUDGE_TYPE, reason: "connected", at: now }),
      );
    } catch {
      this.dropConnection(connectionID);
    }
  }

  handleMessage(
    connectionID: string,
    data: string | ArrayBuffer,
    now: number,
  ): void {
    const entry = this.connections.get(connectionID);
    if (!entry) return;
    const envelope = parseEnvelope(data);
    if (envelope === null) {
      this.closeConnection(connectionID, 1003, "invalid frame");
      this.dropConnection(connectionID);
      return;
    }
    if (envelope.type === INBOX_HEARTBEAT_TYPE) {
      entry.lastHeartbeatAt = now;
      this.connections.set(connectionID, entry);
    }
    // The inbox channel is push-only; any other client frame is ignored.
  }

  /// Fan a nudge out to every live connection. Returns the delivered count.
  notify(reason: string, now: number): number {
    const encoded = JSON.stringify({
      type: INBOX_NUDGE_TYPE,
      reason,
      at: now,
    });
    let delivered = 0;
    for (const [connectionID, entry] of this.connections) {
      try {
        entry.socket.send(encoded);
        delivered += 1;
      } catch {
        this.dropConnection(connectionID);
      }
    }
    return delivered;
  }

  expire(now: number, timeoutMs: number): void {
    for (const [connectionID, entry] of this.connections) {
      if (now - entry.lastHeartbeatAt > timeoutMs) {
        this.closeConnection(connectionID, 1001, "heartbeat timeout");
        this.dropConnection(connectionID);
      }
    }
  }

  dropConnection(connectionID: string): void {
    this.connections.delete(connectionID);
  }

  private closeConnection(
    connectionID: string,
    code: number,
    reason: string,
  ): void {
    const entry = this.connections.get(connectionID);
    if (!entry) return;
    try {
      entry.socket.close(code, reason);
    } catch {
      // Already closed.
    }
  }
}
