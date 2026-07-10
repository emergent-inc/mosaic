# mosaic Collaboration Relay

This Worker is the Phase 1 mosaic Multiplayer relay. It is deliberately small: it creates code-gated sessions, accepts WebSocket peers, forwards opaque collaboration frames, and drops peers that stop heartbeating.

## Local Development

```bash
bun install
bun run typecheck
bun test
bun run dev
```

Downloadable mosaic builds default to the production relay at `https://mosaic-collaboration-worker.dorsa-rohani.workers.dev`. For local development, override the relay URL with `http://localhost:8787` in the collaboration dialog or with `mosaic collaboration create --relay-url http://localhost:8787`.

## Deploy

Pushes to `main` that touch this worker run `.github/workflows/collaboration.yml`, which typechecks, runs unit tests, dry-runs Wrangler, then deploys to Cloudflare with Durable Object migrations applied atomically.

```bash
bun run check
bun run deploy
```

The deploy job requires repository secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`. `wrangler.toml` binds the `COLLABORATION_SESSIONS` Durable Object namespace and exposes the production custom domain `mosaic-collaboration-worker.dorsa-rohani.workers.dev`; the macOS client converts `https://` relay URLs to `wss://` for WebSocket joins.

After deployment, smoke-test the public relay:

```bash
bun run smoke:relay
```

The smoke test performs a real health check, session creation, two WebSocket peer joins, heartbeat handling, and document frame forwarding. Set `MOSAIC_COLLABORATION_RELAY_URL` or pass a URL to test another relay:

```bash
MOSAIC_COLLABORATION_RELAY_URL=http://localhost:8787 bun run smoke:relay
bun run smoke:relay https://mosaic-collaboration-worker.dorsa-rohani.workers.dev
```

## HTTP API

### `GET /healthz`

Returns a static health response:

```json
{ "ok": true, "service": "mosaic-collaboration" }
```

### `POST /v1/collaboration/sessions`

Creates a code-gated relay session and returns:

```json
{
  "sessionID": "5ZNHGF9P",
  "sessionCode": "5ZNHGF9P"
}
```

### `GET /v1/collaboration/sessions/:sessionCode/connect`

Upgrades to WebSocket. Required query parameters:

- `peerID`: stable local peer ID.
- `displayName`: peer display name.
- `color`: presence color.

Optional query parameters:

- `grant`: www-minted join grant (`mosaicgrant1.<claims>.<hmac>`); also
  accepted as an `Authorization: Bearer` header.
- `origin`: client surface tag (e.g. `web` for sharing.mosaic.inc guests),
  surfaced verbatim in peer rosters so clients can badge web guests.

#### Join grants

www mints short-lived HMAC-SHA256 join grants signed with the shared
`MOSAIC_COLLAB_GRANT_SECRET` (see `src/grant.ts` and
`www/services/collab/grant.ts`). When a grant is presented it is always
verified: an invalid signature, expired `exp`, or a `room` claim that does not
match the connect path rejects the upgrade. Connects without any grant are
only rejected once `COLLABORATION_REQUIRE_GRANT="true"`, which stays off until
all shipped clients send grants.

### `GET /v1/collaboration/admin/sessions`

Lists recently indexed session codes. Requires the `x-mosaic-admin-token` header
to match the `COLLABORATION_ADMIN_TOKEN` Worker secret. Each row includes the
Durable Object ID derived from `COLLABORATION_SESSIONS.idFromName(sessionCode)`.

### `GET /v1/collaboration/admin/sessions/:sessionCode`

Describes one code. Requires the `x-mosaic-admin-token` header. The response
reports whether the code is indexed, whether the per-code Durable Object still
has active metadata, and the Durable Object ID that maps to the code.

## Team Session Corpus API

Separate from the live relay, the worker also stores the team coding-session
corpus: each teammate's synced Claude Code session (metadata + transcript
JSONL) so anyone on the team can list sessions in the dashboard and pull one
down to continue it locally. Metadata lives in a per-team `TeamSessionsObject`
Durable Object; transcript bodies live in the `TEAM_SESSION_TRANSCRIPTS` R2
bucket at `sessions/<teamId>/<sessionId>.jsonl`.

One-time setup before the first deploy with these routes:

```bash
wrangler r2 bucket create mosaic-team-session-transcripts
wrangler secret put MOSAIC_NATIVE_AUTH_SECRET   # same value as www
```

Auth: `POST /v1/sessions/sync` and `DELETE` require an `Authorization: Bearer`
`mosaicv1` access token minted by www for the signed-in native app (verified
with the shared `MOSAIC_NATIVE_AUTH_SECRET`; team scope comes from the token's
`teamIds` claims, with a user's own id doubling as their personal team). Reads
additionally accept the `x-mosaic-admin-token` header, which the www dashboard
uses for server-side fetches after authenticating the browser via Clerk; admin
reads must name the team with `?teamId=`.

### `POST /v1/sessions/sync`

Upserts one session. Body:

```json
{
  "teamId": "org_123",
  "session": {
    "sessionId": "0e9f3a52-…",
    "agent": "claude",
    "title": "Fix login bug",
    "cwd": "/Users/alex/dev/app",
    "repoRemoteUrl": "git@github.com:acme/app.git",
    "gitBranch": "fix/login",
    "headSha": "abc123…",
    "wipRef": "refs/mosaic/sessions/0e9f3a52-…",
    "model": "opus",
    "turnCount": 7,
    "parentSessionId": null
  },
  "transcript": "…full JSONL body…"
}
```

`teamId` defaults to the token's selected team. `session.userId` and
`displayName` always come from the verified token; a session id belongs to
whoever synced it first and cannot be overwritten by another member. Omitting
`transcript` updates metadata only; `wipRef: null` explicitly clears a
previously recorded WIP ref (a clean tree on a later sync).

### `GET /v1/sessions?teamId=&limit=`

Lists the team's sessions, most recently active first.

### `GET /v1/sessions/:sessionId?teamId=`

Returns one session's metadata record.

### `GET /v1/sessions/:sessionId/transcript?teamId=`

Returns the raw transcript JSONL (`application/x-ndjson`).

### `DELETE /v1/sessions/:sessionId?teamId=`

Removes a session's metadata and transcript. Only the session owner (or the
admin token) may delete.

## Forwarded Frames

The relay treats non-heartbeat frames as opaque JSON envelopes with a string `type` field. It forwards them to every other peer with `fromPeerID` and `receivedAt` added. Phase 1 clients currently use:

- `document.update`
- `document.snapshot.request`
- `document.snapshot`
- `presence.update`
- `terminal.open`
- `terminal.output`
- `terminal.render_grid`
- `terminal.render_grid.request`
- `terminal.input`
- `terminal.pointer`
- `terminal.selection`
- `terminal.close`

`peer.heartbeat` updates liveness and is not forwarded.

## Session Code Lifecycle

Session codes are keyed by Durable Object name. Each object's storage holds a
single `metadata` record that reserves the code; active peers and forwarded
frames stay in Durable Object memory only. When a session has no peers, the
worker schedules an idle cleanup alarm. If the session is still empty after the
grace window, the `metadata` record is deleted and the short code can be reused.

## Phase 1 Non-Guarantees

- No repository-wide file sync.
- No Git automation.
- No account auth or ACLs beyond the shareable session code.
- No NAT traversal or direct peer-to-peer transport.
- Durable Object active memory is the session state; document content is never persisted by the relay.
