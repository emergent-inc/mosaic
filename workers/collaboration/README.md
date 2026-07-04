# cmux Collaboration Relay

This Worker is the Phase 1 cmux Multiplayer relay. It is deliberately small: it creates code-gated sessions, accepts WebSocket peers, forwards opaque collaboration frames, and drops peers that stop heartbeating.

## Local Development

```bash
bun install
bun run typecheck
bun test
bun run dev
```

Downloadable cmux builds default to the production relay at `https://cmux-collaboration-worker.dorsa-rohani.workers.dev`. For local development, override the relay URL with `http://localhost:8787` in the collaboration dialog or with `cmux collaboration create --relay-url http://localhost:8787`.

## Deploy

Pushes to `main` that touch this worker run `.github/workflows/collaboration.yml`, which typechecks, runs unit tests, dry-runs Wrangler, then deploys to Cloudflare with Durable Object migrations applied atomically.

```bash
bun run check
bun run deploy
```

The deploy job requires repository secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`. `wrangler.toml` binds the `COLLABORATION_SESSIONS` Durable Object namespace and exposes the production custom domain `cmux-collaboration-worker.dorsa-rohani.workers.dev`; the macOS client converts `https://` relay URLs to `wss://` for WebSocket joins.

After deployment, smoke-test the public relay:

```bash
bun run smoke:relay
```

The smoke test performs a real health check, session creation, two WebSocket peer joins, heartbeat handling, and document frame forwarding. Set `CMUX_COLLABORATION_RELAY_URL` or pass a URL to test another relay:

```bash
CMUX_COLLABORATION_RELAY_URL=http://localhost:8787 bun run smoke:relay
bun run smoke:relay https://cmux-collaboration-worker.dorsa-rohani.workers.dev
```

## HTTP API

### `GET /healthz`

Returns a static health response:

```json
{ "ok": true, "service": "cmux-collaboration" }
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

### `GET /v1/collaboration/admin/sessions`

Lists recently indexed session codes. Requires the `x-cmux-admin-token` header
to match the `COLLABORATION_ADMIN_TOKEN` Worker secret. Each row includes the
Durable Object ID derived from `COLLABORATION_SESSIONS.idFromName(sessionCode)`.

### `GET /v1/collaboration/admin/sessions/:sessionCode`

Describes one code. Requires the `x-cmux-admin-token` header. The response
reports whether the code is indexed, whether the per-code Durable Object still
has active metadata, and the Durable Object ID that maps to the code.

## Forwarded Frames

The relay treats non-heartbeat frames as opaque JSON envelopes with a string `type` field. It forwards them to every other peer with `fromPeerID` and `receivedAt` added. Phase 1 clients currently use:

- `document.update`
- `document.snapshot.request`
- `document.snapshot`
- `presence.update`
- `terminal.open`
- `terminal.output`
- `terminal.render_grid`
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
