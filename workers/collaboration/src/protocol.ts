export interface PeerInfo {
  peerID: string;
  participantID: string;
  displayName: string;
  color: string;
  imageURL?: string;
  /// Client surface that opened the connection ("web" for sharing.mosaic.inc
  /// guests). Absent for native app peers; forwarded verbatim in peer lists so
  /// clients can badge web guests.
  origin?: string;
  /// Wire-format capabilities the peer supports (e.g. "binv1" for the binary
  /// terminal I/O hot path). Forwarded verbatim so senders can gate binary
  /// frames on every recipient advertising support.
  caps?: string[];
}

export interface RelayEnvelope {
  type: string;
  [key: string]: unknown;
}

export interface SessionCreateResponse {
  sessionID: string;
  sessionCode: string;
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

export function parsePeer(value: unknown): PeerInfo | null {
  if (typeof value !== "object" || value === null) return null;
  const record = value as Record<string, unknown>;
  if (typeof record.peerID !== "string" || record.peerID.trim() === "") return null;
  if (typeof record.displayName !== "string" || record.displayName.trim() === "") return null;
  if (typeof record.color !== "string" || record.color.trim() === "") return null;
  const participantID = typeof record.participantID === "string" && record.participantID.trim() !== ""
    ? record.participantID
    : record.peerID;
  const imageURL = typeof record.imageURL === "string" && record.imageURL.trim() !== ""
    ? record.imageURL
    : undefined;
  const origin = normalizePeerOrigin(record.origin);
  const caps = normalizePeerCaps(record.caps);
  const peer: PeerInfo = {
    peerID: record.peerID,
    participantID,
    displayName: record.displayName,
    color: record.color,
  };
  if (imageURL !== undefined) peer.imageURL = imageURL;
  if (origin !== undefined) peer.origin = origin;
  if (caps !== undefined) peer.caps = caps;
  return peer;
}

/// Normalizes peer capabilities from either a connect query string
/// (comma-separated tokens) or a JSON `peer.update` array.
function normalizePeerCaps(value: unknown): string[] | undefined {
  let tokens: string[];
  if (typeof value === "string") {
    tokens = value.split(",");
  } else if (Array.isArray(value)) {
    tokens = value.filter((token): token is string => typeof token === "string");
  } else {
    return undefined;
  }
  const normalized = tokens
    .map((token) => token.trim().toLowerCase())
    .filter((token) => token !== "" && token.length <= 16 && /^[a-z0-9-]+$/.test(token));
  return normalized.length > 0 ? [...new Set(normalized)] : undefined;
}

function normalizePeerOrigin(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim().toLowerCase();
  if (trimmed === "" || trimmed.length > 16) return undefined;
  if (!/^[a-z0-9-]+$/.test(trimmed)) return undefined;
  return trimmed;
}

export function parseEnvelope(message: string | ArrayBuffer): RelayEnvelope | null {
  const text = typeof message === "string" ? message : new TextDecoder().decode(message);
  if (text.length > 1024 * 1024) return null;
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    return null;
  }
  if (typeof parsed !== "object" || parsed === null) return null;
  const record = parsed as Record<string, unknown>;
  return typeof record.type === "string" ? (record as RelayEnvelope) : null;
}

export function randomSessionCode(): string {
  const alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  const values = new Uint8Array(8);
  crypto.getRandomValues(values);
  return [...values].map((value) => alphabet[value % alphabet.length]).join("");
}

export function normalizeSessionCode(value: string): string | null {
  const compact = value.toUpperCase().replace(/[^A-Z0-9]/g, "");
  if (/^[A-Z0-9]{4}$/.test(compact)) return compact;
  if (/^[A-Z0-9]{5}$/.test(compact)) return compact;
  if (/^[A-Z0-9]{8}$/.test(compact)) return compact;
  return null;
}
