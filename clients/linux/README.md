# mosaic-linux — Mosaic collaboration client for Linux/WSL

Mosaic proper is a native macOS app (Swift/AppKit on libghostty); there is no
Linux build and porting the ~900k-line app is out of scope. But the *sharing*
layer is cross-platform: the collaboration relay is a Cloudflare Worker and the
wire protocol is plain JSON over a WebSocket, with no account auth — possession
of the room's 8-character code is the only credential the relay checks.

`mosaic-linux` is a small, dependency-light Go client that speaks that protocol
so a Linux or WSL user can participate in a Mosaic collaboration room without a
Mac. It does two things:

- **`join <code>`** — join a room, attach to a shared terminal pane, watch its
  live output, and (unless the host restricts it) type into it.
- **`host`** — share a local shell into a room so Mosaic users (or other
  `mosaic-linux` clients) can watch and, optionally, drive it.

It is a **participant client**, not a port of the Mosaic UI: no windows, tabs,
file explorer, or agent panels — just terminal sharing over the real relay.

## Build

Requires Go 1.22+. Pure Go, `CGO_ENABLED=0`, cross-compiles cleanly.

```bash
cd clients/linux
make build            # -> ./mosaic-linux
make cross            # -> dist/mosaic-linux-linux-{amd64,arm64}
```

## Use

Share your shell into a new room:

```bash
./mosaic-linux host -allow-input
# prints:  Join from another machine with:  mosaic-linux join <CODE>
```

Join a room and attach to the shared terminal:

```bash
./mosaic-linux join <CODE>
# type to drive it; press Ctrl-] to detach; -read-only to just watch
```

By default `host` is **view-only**; pass `-allow-input` to let room peers type.
The relay is unauthenticated, so treat the room code like a password — anyone
with the code and the relay URL can join. See "Security notes" below.

Point at a self-hosted relay with `-relay https://…` or `MOSAIC_RELAY_URL`.
The default is the same production relay the macOS app ships with.

## Interop with the macOS app

- **A `mosaic-linux` viewer attaching to a macOS host** is the best-supported
  path: the Mac host sends a structured `render_grid` seed (decoded and
  replayed here into a VT byte stream that is **byte-for-byte identical** to
  the Swift/iOS implementation — see the render-grid tests) followed by live
  output.
- **A macOS viewer attaching to a `mosaic-linux` host** works for live output,
  but this client does not synthesize a `render_grid` snapshot: a late joiner
  gets the current screen repainted (via a redraw nudge) rather than scrollback
  history. See limitations.

## What's verified

- **Real relay, no Mac:** an interop test creates a room on the deployed Mosaic
  Cloudflare relay, joins with two clients, and round-trips terminal
  output/input frames. This empirically confirms code-only connect is accepted,
  `session.joined` acknowledges the join, and the relay stamps `fromPeerID` and
  forwards as modeled. Run it with `make interop` (needs outbound network).
- **End-to-end with real PTYs:** `make e2e` spawns the built binary as both host
  and viewer over real OS PTYs and an in-process relay, and asserts host output
  reaches the viewer, viewer keystrokes drive the host shell, and a
  `-read-only` viewer cannot type.
- **Wire codec + render-grid** unit tests, including the exact VT byte strings
  from the Swift test suite; `go test -race` clean.

Not yet exercised against a live macOS Mosaic app (no Mac available); the
macOS-interop claims above are derived from the shared relay + a render-grid
implementation tested for byte-compatibility, and confirmed on the relay side.

## Limitations (v0)

- **No scrollback transfer from a Linux host.** `host` does not build a
  `render_grid` seed, so a viewer joining a `mosaic-linux` host mid-session
  sees a repaint of the current screen, not prior history.
- **Seed/live seam.** When attaching to a macOS host, the seed and the first
  live `terminal.output` are both applied without trimming their overlap by
  `sequence` (the Mac client trims it); a brief double-paint at attach is
  possible. Output after the seam is correct.
- **Host-side recipient gating.** A macOS host only sends output/`terminal.open`
  to participants it has selected in its UI. A freshly joined `mosaic-linux`
  viewer may see nothing until the host grants it — that's Mac-side behavior,
  not a client bug.
- **One pane at a time.** `join` attaches to a single terminal (first match, or
  `-terminal <substr>`); it does not present a multi-pane workspace.
- **Presence overlays** (remote cursors/selection) and the collaborative-text
  and agent-room frame families are not rendered.

## Architecture

```
cmd/mosaic-linux/   CLI: join (viewer) and host commands
proto/              relay wire schema (JSON frames) + envelope routing
rendergrid/         render-grid snapshot decode + VT synthesis (Swift-compatible)
relay/              relay client: create/join, join-ack gate, heartbeats, frames
relay/relaytest/    in-process relay double replicating the Worker's forwarding
e2e/                real-binary + real-PTY end-to-end test
```

Protocol sources: `workers/collaboration/src/*.ts` (relay),
`Sources/CollaborationRuntime.swift` (wire structs),
`Packages/Shared/MosaicMobileCore/.../MobileTerminalRenderGrid*.swift`
(render grid). All frames are JSON text; terminal bytes travel base64-encoded
inside `dataBase64`; the relay caps a frame at 1 MiB.

## Security notes

- The relay performs **no authentication** — the room code is the only gate,
  and any peer may self-assert its identity fields. Share codes carefully.
- `host` defaults to view-only; `-allow-input` grants every current room peer
  the ability to type into your shell. Only enable it with people you trust.
- Span text from render-grid frames is stripped of control characters before
  replay, so a malicious host cannot inject live escape sequences through cell
  contents.
