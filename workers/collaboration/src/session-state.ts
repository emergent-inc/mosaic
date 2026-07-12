import { parseEnvelope, parsePeer, type PeerInfo, type RelayEnvelope } from "./protocol";
import { isBinaryFrame, parseBinaryFrameHeader } from "./binary";

export interface RelaySocket {
  send(data: string | ArrayBuffer | ArrayBufferView): void;
  close(code: number, reason: string): void;
}

interface PeerConnection {
  peer: PeerInfo;
  socket: RelaySocket;
  lastHeartbeatAt: number;
}

export class CollaborationRelaySessionState {
  private peers = new Map<string, PeerConnection>();

  get peerCount(): number {
    return this.peers.size;
  }

  addPeer(sessionID: string, peer: PeerInfo, socket: RelaySocket, now: number): void {
    this.peers.set(peer.peerID, { peer, socket, lastHeartbeatAt: now });
    socket.send(JSON.stringify({
      type: "session.joined",
      sessionID,
      peers: [...this.peers.values()].map((entry) => entry.peer),
    }));
    this.broadcast(peer.peerID, { type: "peer.joined", peer });
  }

  handleMessage(peerID: string, data: string | ArrayBuffer, now: number): void {
    const entry = this.peers.get(peerID);
    if (!entry) return;
    if (isBinaryFrame(data)) {
      this.handleBinaryMessage(peerID, entry, data, now);
      return;
    }
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
    if (envelope.type === "peer.update") {
      const peer = parsePeer((envelope as { peer?: unknown }).peer);
      if (peer === null || peer.peerID !== peerID) {
        this.closePeer(peerID, 1003, "invalid frame");
        this.dropPeer(peerID, "disconnect");
        return;
      }
      this.peers.set(peerID, { ...entry, peer, lastHeartbeatAt: now });
      this.broadcast(peerID, { type: "peer.update", peer });
      return;
    }
    this.broadcast(peerID, { ...envelope, fromPeerID: peerID, receivedAt: now }, this.recipientParticipantIDs(envelope));
  }

  expire(now: number, timeoutMs: number): void {
    for (const [peerID, entry] of this.peers) {
      if (now - entry.lastHeartbeatAt > timeoutMs) {
        this.closePeer(peerID, 1001, "heartbeat timeout");
        this.dropPeer(peerID, "timeout");
      }
    }
  }

  dropPeer(peerID: string, reason: "disconnect" | "timeout" | "leave"): void {
    if (!this.peers.delete(peerID)) return;
    this.broadcast(peerID, { type: "peer.left", peerID, reason });
  }

  private handleBinaryMessage(
    peerID: string,
    entry: PeerConnection,
    buffer: ArrayBuffer,
    now: number,
  ): void {
    const header = parseBinaryFrameHeader(buffer);
    // `fromPeerID` is sender-authoritative on the wire; the relay validates it
    // matches the connection's peer (mirroring the `peer.update` check) and
    // then forwards the original buffer unchanged -- the large payload is never
    // re-encoded.
    if (header === null || header.fromPeerID !== peerID) {
      this.closePeer(peerID, 1003, "invalid frame");
      this.dropPeer(peerID, "disconnect");
      return;
    }
    entry.lastHeartbeatAt = now;
    this.peers.set(peerID, entry);
    const recipients =
      header.recipientParticipantIDs === null
        ? null
        : new Set(header.recipientParticipantIDs);
    this.broadcastBinary(peerID, buffer, recipients);
  }

  private broadcast(fromPeerID: string, body: unknown, recipientParticipantIDs: Set<string> | null = null): void {
    const encoded = JSON.stringify(body);
    for (const [peerID, entry] of this.peers) {
      if (peerID === fromPeerID) continue;
      if (recipientParticipantIDs !== null && !recipientParticipantIDs.has(entry.peer.participantID)) continue;
      try {
        entry.socket.send(encoded);
      } catch {
        this.dropPeer(peerID, "disconnect");
      }
    }
  }

  private broadcastBinary(
    fromPeerID: string,
    buffer: ArrayBuffer,
    recipientParticipantIDs: Set<string> | null,
  ): void {
    for (const [peerID, entry] of this.peers) {
      if (peerID === fromPeerID) continue;
      if (recipientParticipantIDs !== null && !recipientParticipantIDs.has(entry.peer.participantID)) continue;
      try {
        entry.socket.send(buffer);
      } catch {
        this.dropPeer(peerID, "disconnect");
      }
    }
  }

  private recipientParticipantIDs(envelope: RelayEnvelope): Set<string> | null {
    if (!envelope.type.startsWith("terminal.")) return null;
    const raw = envelope.recipientParticipantIDs;
    if (raw === undefined) return null;
    if (!Array.isArray(raw)) return new Set();
    return new Set(raw.filter((id): id is string => typeof id === "string" && id.trim() !== ""));
  }

  private closePeer(peerID: string, code: number, reason: string): void {
    const entry = this.peers.get(peerID);
    if (!entry) return;
    try {
      entry.socket.close(code, reason);
    } catch {
      // Already closed.
    }
  }
}
