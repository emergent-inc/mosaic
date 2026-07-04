import { normalizeSessionCode, type SessionCreateResponse } from "./protocol";

export interface IndexedCollaborationSession {
  sessionID: string;
  sessionCode: string;
  createdAt: number;
}

export const SESSION_INDEX_KEY_PREFIX = "session:";

export function indexedSessionStorageKey(rawSessionCode: string): string | null {
  const sessionCode = normalizeSessionCode(rawSessionCode);
  return sessionCode === null ? null : `${SESSION_INDEX_KEY_PREFIX}${sessionCode}`;
}

export function indexedSessionFromBody(
  body: Partial<SessionCreateResponse>,
  createdAt = Date.now()
): IndexedCollaborationSession | null {
  const sessionCode = typeof body.sessionCode === "string" ? normalizeSessionCode(body.sessionCode) : null;
  const sessionID = typeof body.sessionID === "string" && body.sessionID.trim() !== ""
    ? body.sessionID
    : sessionCode;
  if (sessionCode === null || sessionID === null) return null;
  return {
    sessionID,
    sessionCode,
    createdAt,
  };
}

export function normalizedIndexListLimit(value: string | null): number {
  const requestedLimit = Number(value ?? 100);
  return Number.isFinite(requestedLimit)
    ? Math.min(Math.max(Math.trunc(requestedLimit), 1), 500)
    : 100;
}
