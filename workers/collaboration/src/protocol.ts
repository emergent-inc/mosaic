export interface PeerInfo {
  peerID: string;
  participantID: string;
  displayName: string;
  color: string;
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
  return {
    peerID: record.peerID,
    participantID,
    displayName: record.displayName,
    color: record.color,
  };
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
  const alphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
  const values = new Uint8Array(4);
  crypto.getRandomValues(values);
  return [...values].map((value) => alphabet[value % alphabet.length]).join("");
}

export function normalizeSessionCode(value: string): string | null {
  const compact = value.toUpperCase().replace(/[^A-Z0-9]/g, "");
  if (/^[2-9A-HJ-NP-Z]{4}$/.test(compact)) return compact;
  if (/^[A-Z]{5}$/.test(compact)) return compact;
  if (/^[2-9A-HJ-NP-Z]{8}$/.test(compact)) return compact;
  return null;
}
