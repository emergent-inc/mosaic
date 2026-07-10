// Team coding-session records: the metadata index entry stored per synced
// agent session (one per Claude Code session a teammate opted into sharing).
// The transcript body itself lives in R2 at `transcriptObjectKey`; this record
// is what dashboards and the pull flow list and filter on.

export interface TeamSessionRecord {
  sessionId: string;
  /// Owner of the session (Clerk user id from the verified access token).
  userId: string;
  displayName: string | null;
  /// Agent kind ("claude" for v1).
  agent: string;
  title: string | null;
  cwd: string | null;
  repoRemoteUrl: string | null;
  gitBranch: string | null;
  headSha: string | null;
  /// Hidden git ref carrying a WIP snapshot commit of uncommitted work
  /// (refs/mosaic/sessions/<sessionId>), when the tree was dirty at sync time.
  wipRef: string | null;
  model: string | null;
  turnCount: number | null;
  transcriptBytes: number;
  /// Session this one was forked from via a handoff pull, for lineage display.
  parentSessionId: string | null;
  createdAt: number;
  lastActivityAt: number;
}

export const TEAM_SESSION_KEY_PREFIX = "session:";

const MAX_ID_LENGTH = 256;
const MAX_TEXT_FIELD_LENGTH = 1024;
/// Session ids come from agent CLIs (Claude uses UUIDs). Constrain to a safe
/// charset because the id is embedded in storage keys and R2 object keys.
const SESSION_ID_RE = /^[A-Za-z0-9._-]{1,256}$/;

export function normalizeTeamSessionId(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return SESSION_ID_RE.test(trimmed) ? trimmed : null;
}

/// Team ids are Clerk org ids or user ids; both are opaque strings. Constrain
/// charset/length because the team id names the Durable Object and prefixes R2
/// object keys.
export function normalizeTeamId(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (trimmed === "" || trimmed.length > MAX_ID_LENGTH) return null;
  if (!/^[A-Za-z0-9:._-]+$/.test(trimmed)) return null;
  return trimmed;
}

export function teamSessionStorageKey(sessionId: string): string {
  return `${TEAM_SESSION_KEY_PREFIX}${sessionId}`;
}

export function transcriptObjectKey(teamId: string, sessionId: string): string {
  return `sessions/${teamId}/${sessionId}.jsonl`;
}

function optionalText(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (trimmed === "") return null;
  return trimmed.length > MAX_TEXT_FIELD_LENGTH
    ? trimmed.slice(0, MAX_TEXT_FIELD_LENGTH)
    : trimmed;
}

function optionalCount(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  const truncated = Math.trunc(value);
  return truncated >= 0 ? truncated : null;
}

export interface TeamSessionUpsertInput {
  body: Record<string, unknown>;
  userId: string;
  displayName: string | null;
  transcriptBytes: number;
  existing: TeamSessionRecord | null;
  now?: number;
}

/// Builds the record to store for a sync upsert. Identity fields (userId,
/// displayName) come from the verified token, never the body, so a caller
/// cannot attribute a session to someone else. Returns null when the body has
/// no valid session id.
export function teamSessionRecordForUpsert(
  input: TeamSessionUpsertInput,
): TeamSessionRecord | null {
  const { body, existing } = input;
  const now = input.now ?? Date.now();
  const sessionId = normalizeTeamSessionId(body.sessionId);
  if (sessionId === null) return null;
  const agent = optionalText(body.agent) ?? existing?.agent ?? "claude";
  return {
    sessionId,
    userId: input.userId,
    displayName: input.displayName,
    agent,
    title: optionalText(body.title) ?? existing?.title ?? null,
    cwd: optionalText(body.cwd) ?? existing?.cwd ?? null,
    repoRemoteUrl: optionalText(body.repoRemoteUrl) ?? existing?.repoRemoteUrl ?? null,
    gitBranch: optionalText(body.gitBranch) ?? existing?.gitBranch ?? null,
    headSha: optionalText(body.headSha) ?? existing?.headSha ?? null,
    // A clean tree on a later sync clears a previously-recorded WIP ref, so
    // explicit null in the body must overwrite (not fall back to existing).
    wipRef: "wipRef" in body ? optionalText(body.wipRef) : (existing?.wipRef ?? null),
    model: optionalText(body.model) ?? existing?.model ?? null,
    turnCount: optionalCount(body.turnCount) ?? existing?.turnCount ?? null,
    transcriptBytes: input.transcriptBytes,
    parentSessionId:
      normalizeTeamSessionId(body.parentSessionId) ?? existing?.parentSessionId ?? null,
    createdAt: existing?.createdAt ?? now,
    lastActivityAt: now,
  };
}

export function normalizedTeamSessionListLimit(value: string | null): number {
  const requestedLimit = Number(value ?? 200);
  return Number.isFinite(requestedLimit)
    ? Math.min(Math.max(Math.trunc(requestedLimit), 1), 500)
    : 200;
}

export function sortedByActivity(records: TeamSessionRecord[]): TeamSessionRecord[] {
  return [...records].sort((left, right) => right.lastActivityAt - left.lastActivityAt);
}
