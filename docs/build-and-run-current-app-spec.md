# Build, Run, And Installable Release Spec

Last updated: June 30, 2026

This document defines the supported ways to build cmux from this repository:

1. A tagged isolated Debug app for local development and agent verification.
2. The signed, notarized macOS DMG that real users download and run.

The public installable is not a Debug build. It is the `cmux-macos.dmg` asset produced by the stable release pipeline and attached to a GitHub Release tag.

## Outcomes

### Local Debug Outcome

Use this when validating a worktree change on the same machine.

- Product: `cmux DEV <tag>.app`
- Configuration: Debug
- Bundle ID: tag-scoped debug bundle ID
- Socket: tag-scoped debug socket
- Distribution: local only
- Signing/notarization: not the public release path

### Public Installable Outcome

Use this when producing the app others download.

- Product: `cmux-macos.dmg`
- Contents: signed and notarized `cmux.app`
- Configuration: Release, universal macOS app
- Bundle ID: `com.cmuxterm.app`
- Update feed: Sparkle `appcast.xml`
- Download URL: `https://github.com/manaflow-ai/cmux/releases/latest/download/cmux-macos.dmg`
- Release trigger: push a `v*` tag to GitHub

Nightly has the same shape but a different channel:

- Product: `cmux-nightly-macos.dmg`
- Contents: signed and notarized `cmux NIGHTLY.app`
- Bundle ID: `com.cmuxterm.app.nightly`
- Update feed: `https://files.cmux.com/nightly/appcast.xml`
- Release target: the mutable `nightly` GitHub Release

## Public Stable Release Path

The stable installable is produced by `.github/workflows/release.yml`. This is the source of truth for the downloadable app.

### Required Inputs

The release must be prepared from a clean, reviewed state on `main`:

1. Changelog updated in `CHANGELOG.md`.
2. Version bumped with `scripts/bump-version.sh`.
3. `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` committed.
4. `scripts/release-pretag-guard.sh` passes.
5. Multiplayer relay changes, if any, are already merged and deployable.
6. GhosttyKit prebuilt artifact exists for the current `ghostty` submodule SHA.

Run the standard release prep:

```bash
./scripts/bump-version.sh
./scripts/release-pretag-guard.sh
```

By default, bump the minor version unless the release is explicitly a patch, major, or fixed version:

```bash
./scripts/bump-version.sh patch
./scripts/bump-version.sh major
./scripts/bump-version.sh 1.0.0
```

### Required Repository Secrets

Stable release CI requires these GitHub Actions secrets:

- `APPLE_CERTIFICATE_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_SIGNING_IDENTITY`
- `APPLE_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
- `APPLE_TEAM_ID`
- `APPLE_RELEASE_PROVISIONING_PROFILE_BASE64`
- `SPARKLE_PRIVATE_KEY`

Optional or adjacent release operations use:

- `CF_R2_ACCESS_KEY_ID`
- `CF_R2_SECRET_ACCESS_KEY`
- `CF_R2_ACCOUNT_ID`
- `HOMEBREW_TAP_TOKEN`
- `SENTRY_AUTH_TOKEN`

The signing identity must be a Developer ID Application identity for Manaflow. The release provisioning profile must match `com.cmuxterm.app` and include required entitlements such as WebAuthn.

### Tag And Trigger

Create and push a stable semver tag:

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
gh run watch --repo manaflow-ai/cmux
```

The public release path is tag-triggered. `workflow_dispatch` on `release.yml` is useful for dry-run artifacts, but it does not publish the public GitHub Release in the same way as a `v*` tag push.

## Release CI Pipeline

`.github/workflows/release.yml` performs the full installable build.

### 1. Guard Existing Assets

`scripts/release_asset_guard.js` checks immutable release assets:

- `cmux-macos.dmg`
- `appcast.xml`
- `cmuxd-remote-darwin-arm64`
- `cmuxd-remote-darwin-amd64`
- `cmuxd-remote-linux-arm64`
- `cmuxd-remote-linux-amd64`
- `cmuxd-remote-checksums.txt`
- `cmuxd-remote-manifest.json`

If every immutable asset already exists for the tag, CI skips rebuild/upload. If only some assets exist, CI fails and requires manual cleanup or a new tag. Do not overwrite release assets casually; a published DMG and appcast are part of the update contract.

### 2. Prepare Build Tools

CI installs or exposes required tools:

- Xcode on macOS runners
- Node/npm
- `create-dmg@8.0.0`
- Rust toolchain when needed
- Swift tooling for Sparkle key derivation

The workflow deliberately installs `create-dmg` so self-hosted runners do not need npm preinstalled.

### 3. Build Release App

The app is built as a universal Release app:

```text
build-universal/Build/Products/Release/cmux.app
```

The workflow injects Sparkle metadata into `Info.plist`:

- `SUPublicEDKey` derived from `SPARKLE_PRIVATE_KEY`
- `SUFeedURL` set to `https://github.com/manaflow-ai/cmux/releases/latest/download/appcast.xml`

The workflow also embeds release channel metadata and removes Sparkle sandbox XPC services that do not apply to this non-sandboxed app.

### 4. Embed Release Provisioning Profile

The release profile from `APPLE_RELEASE_PROVISIONING_PROFILE_BASE64` is decoded and embedded at:

```text
cmux.app/Contents/embedded.provisionprofile
```

CI validates that the profile app identifier matches:

```text
7WLXT3NR37.com.cmuxterm.app
```

### 5. Sign The App

The app is signed with:

```bash
./scripts/sign-cmux-bundle.sh "$APP_PATH" cmux.release.entitlements "$APPLE_SIGNING_IDENTITY"
```

The signing certificate is imported into an ephemeral `build.keychain`, and Apple Developer ID intermediate certificates are imported before signing.

### 6. Notarize The App

CI submits a zip of `cmux.app` to Apple notarization:

```bash
xcrun notarytool submit cmux-notary.zip --wait
```

After Apple accepts it, CI staples and validates the app:

```bash
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl -a -vv --type execute "$APP_PATH"
```

### 7. Smoke Test The App Bundle

The workflow verifies the app before packaging:

```bash
CMUX_SMOKE_ALLOW_UNSUPPORTED_GUI=1 CMUX_SMOKE_DEBUG_LOGS=1 ./scripts/smoke-launch-macos-app.sh "$APP_PATH"
CMUX_SMOKE_DIRECT_EXEC=1 CMUX_SMOKE_DEBUG_LOGS=1 ./scripts/smoke-launch-macos-app.sh "$APP_PATH"
./scripts/verify-app-bundle-channel-metadata.sh "$APP_PATH" stable
./scripts/smoke-installable-artifact.sh --channel stable "$APP_PATH"
```

`scripts/smoke-installable-artifact.sh` validates bundle identity, display name, executable presence, bundled CLI, provisioning profile, codesigning, Gatekeeper assessment, and notarization.

### 8. Create, Sign, And Notarize The DMG

CI creates the drag-to-install disk image:

```bash
create-dmg --no-code-sign "$APP_PATH" .
mv ./cmux*.dmg cmux-macos.dmg
```

Then it signs and notarizes the DMG container itself:

```bash
codesign --force --timestamp --keychain build.keychain --sign "$APPLE_SIGNING_IDENTITY" cmux-macos.dmg
codesign --verify --verbose=2 cmux-macos.dmg
xcrun notarytool submit cmux-macos.dmg --wait
xcrun stapler staple cmux-macos.dmg
xcrun stapler validate cmux-macos.dmg
```

Finally, it mounts and validates the final user artifact:

```bash
./scripts/smoke-installable-artifact.sh --channel stable cmux-macos.dmg
```

That final smoke is important: it checks what users download, not just the intermediate app bundle.

### 9. Generate Sparkle Appcast

CI generates the stable update feed:

```bash
./scripts/sparkle_generate_appcast.sh cmux-macos.dmg "$GITHUB_REF_NAME" appcast.xml
```

The appcast must reference the published DMG and must be signed with `SPARKLE_PRIVATE_KEY`.

### 10. Upload Release Assets

On a `v*` tag push, CI uploads these assets to the GitHub Release:

- `cmux-macos.dmg`
- `appcast.xml`
- remote daemon binaries
- remote daemon checksums and manifest

The README, localized READMEs, and web download code all assume the stable DMG is available at:

```text
https://github.com/manaflow-ai/cmux/releases/latest/download/cmux-macos.dmg
```

### 11. Mirror Stable Appcast To R2

If the tag is the highest semver release, CI mirrors `appcast.xml` to:

```text
https://files.cmux.com/stable/appcast.xml
```

Backport tags do not overwrite the stable R2 appcast.

### 12. Update Homebrew

After the release workflow succeeds, `.github/workflows/update-homebrew.yml` updates the `manaflow-ai/homebrew-cmux` cask. The cask points at:

```text
https://github.com/manaflow-ai/cmux/releases/download/v#{version}/cmux-macos.dmg
```

and pins the DMG SHA256.

## Multiplayer Relay Requirement

The public app is only "ready for others" if the collaboration relay is deployed and smoke-tested.

The relay lives in `workers/collaboration` and deploys through `.github/workflows/collaboration.yml`.

### Production Relay

Downloadable builds default to:

```text
https://cmux-collaboration-worker.dorsa-rohani.workers.dev
```

The macOS client converts `https://` relay URLs to `wss://` for WebSocket joins.

### Relay CI

Pull requests touching the worker run:

```bash
bun run --cwd workers/collaboration typecheck
bun run --cwd workers/collaboration test
bun run --cwd workers/collaboration check
```

Pushes to `main` deploy to Cloudflare when these secrets exist:

- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`

`wrangler deploy` applies Durable Object migrations from `wrangler.toml` atomically with the Worker upload.

### Relay Smoke

After deploy, CI runs:

```bash
bun run --cwd workers/collaboration smoke:relay
```

The smoke test performs:

- health check
- session creation
- two WebSocket peer joins
- heartbeat handling
- document frame forwarding

Manual smoke against production:

```bash
bun run --cwd workers/collaboration smoke:relay https://cmux-collaboration-worker.dorsa-rohani.workers.dev
```

Manual smoke against local Wrangler:

```bash
CMUX_COLLABORATION_RELAY_URL=http://localhost:8787 bun run --cwd workers/collaboration smoke:relay
```

## Local Manual Release Fallback

Prefer tag-triggered CI for public releases. The local fallback is:

```bash
./scripts/build-sign-upload.sh vX.Y.Z
```

It expects:

```bash
source ~/.secrets/cmuxterm.env
export SPARKLE_PRIVATE_KEY
```

and requires these tools on the local machine:

- `zig`
- `xcodebuild`
- `create-dmg`
- `xcrun`
- `codesign`
- `ditto`
- `gh`

The local script handles GhosttyKit build, Release app build, Sparkle key injection, codesigning, app notarization, DMG creation, DMG notarization, appcast generation, GitHub release upload, and Homebrew cask update.

Use the local script only when intentionally doing a maintainer-local release. CI and local release behavior are similar but not identical: CI embeds the release provisioning profile, uses `cmux.release.entitlements`, enforces release asset guarding, downloads prebuilt GhosttyKit, and runs the current artifact smoke checks.

## Nightly Installable

Nightly releases are produced by `.github/workflows/nightly.yml`.

Nightly creates:

```text
cmux-nightly-macos.dmg
```

and uploads it to the mutable `nightly` GitHub Release:

```text
https://github.com/manaflow-ai/cmux/releases/download/nightly/cmux-nightly-macos.dmg
```

Nightly uses:

- bundle ID `com.cmuxterm.app.nightly`
- app display name `cmux NIGHTLY`
- `cmux.nightly.entitlements`
- `APPLE_NIGHTLY_PROVISIONING_PROFILE_BASE64`
- Sparkle feed `https://files.cmux.com/nightly/appcast.xml`

The nightly workflow signs, notarizes, staples, validates, smoke-launches, mounts the DMG, verifies the artifact, generates appcasts, and mirrors the nightly appcast to R2.

## Local Debug Build And Run

Use a tagged Debug reload when validating source changes locally:

```bash
./scripts/reload.sh --tag run-current --launch
```

The tag creates an isolated app name, bundle ID, socket, sidebar extension point, and derived data path. For the `run-current` tag, the expected build product is:

```text
~/Library/Developer/Xcode/DerivedData/cmux-run-current/Build/Products/Debug/cmux DEV run-current.app
```

If `xcode-select -p` points at Command Line Tools, `xcodebuild` will fail with:

```text
xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance
```

Do not change global Xcode settings from an agent session. Set `DEVELOPER_DIR` only for the command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/reload.sh --tag run-current --launch
```

A successful run prints:

```text
==> reload succeeded

App path:
  /Users/dorsa/Library/Developer/Xcode/DerivedData/cmux-run-current/Build/Products/Debug/cmux DEV run-current.app
```

To share the launched app in chat, convert that `App path:` line to a `file://` URL and URL-encode spaces as `%20`:

```markdown
[run-current: file:///Users/dorsa/Library/Developer/Xcode/DerivedData/cmux-run-current/Build/Products/Debug/cmux%20DEV%20run-current.app](file:///Users/dorsa/Library/Developer/Xcode/DerivedData/cmux-run-current/Build/Products/Debug/cmux%20DEV%20run-current.app)
```

Do not hardcode the path for other tags or machines. Always use the path printed by `reload.sh`.

For tagged CLI dogfood, set `CMUX_TAG=<tag>` and use:

```bash
CMUX_TAG=<tag> scripts/cmux-debug-cli.sh list-workspaces
```

Do not use `/tmp/cmux-cli` for tagged dogfood.

## Local Debug DMG For Trusted Sharing

Use this only when a maintainer wants to hand a trusted collaborator the current tagged Debug app for quick local testing. This is not the public installable path: the DMG is unsigned and unnotarized, and macOS may still show Gatekeeper warnings on another machine.

The working shape mirrors the known-openable local `v1.dmg` style:

- DMG container: unsigned
- DMG root: exactly one `.app`
- App bundle name: keep the tagged Debug app name, for example `cmux DEV session-code-ui.app`
- No `Applications` symlink
- No copied app from an already-mounted DMG
- Source app: the freshly rebuilt DerivedData product from `reload.sh`

### Build The Source App

Always rebuild the tag from source first:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/reload.sh --tag session-code-ui --launch
```

Use the exact `App path:` printed by `reload.sh`. Do not guess it and do not package an app copied out of `/Volumes`.

### Create The DMG

Stage the rebuilt `.app` as the only root entry, then create a compressed read-only image with `hdiutil`:

```bash
TAG="session-code-ui"
APP_PATH="$HOME/Library/Developer/Xcode/DerivedData/cmux-${TAG}/Build/Products/Debug/cmux DEV ${TAG}.app"
OUT_DIR="build/local-dmg"
STAGING="$OUT_DIR/${TAG}-v1-style-staging"
DMG="$OUT_DIR/cmux-${TAG}-v1-style.dmg"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
ditto "$APP_PATH" "$STAGING/cmux DEV ${TAG}.app"
hdiutil create -volname "cmux ${TAG//-/ }" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"
shasum -a 256 "$DMG"
```

Do not run `codesign` on this local Debug DMG container. The app inside is already signed by the Xcode build; the known-compatible handoff uses an unsigned DMG container.

### Verify The DMG

Before sharing, detach any stale same-name volumes so Finder and LaunchServices cannot open an older mounted copy:

```bash
hdiutil info
hdiutil detach /dev/diskXsY
```

Mount the new DMG and validate the app inside the mounted image, not just the DerivedData source app:

```bash
hdiutil attach -readonly -nobrowse "build/local-dmg/cmux-session-code-ui-v1-style.dmg"
CMUX_INSTALLABLE_REQUIRE_NOTARIZATION=0 CMUX_INSTALLABLE_REQUIRE_SPCTL=0 \
  ./scripts/smoke-installable-artifact.sh --channel debug \
  "/Volumes/cmux session code ui/cmux DEV session-code-ui.app"
open -n "/Volumes/cmux session code ui/cmux DEV session-code-ui.app"
```

The debug artifact smoke should report:

```text
installable artifact smoke OK: bundle=com.cmuxterm.app.debug.<tag> version=<version> build=<build>
```

If Finder reports `kLSNoExecutableErr`, compare the mounted app's `Info.plist` `CFBundleExecutable` with the file in `Contents/MacOS/`, verify it is executable (`0755`), detach all stale cmux volumes, and retry with a new DMG filename and volume name.

## Verification Checklist

Before tagging a stable release:

1. `CHANGELOG.md` is updated.
2. `scripts/bump-version.sh` has been run and committed.
3. `scripts/release-pretag-guard.sh` passes.
4. Collaboration worker changes pass typecheck, tests, and Wrangler dry-run.
5. Production relay smoke passes if multiplayer changed.
6. GhosttyKit prebuilt artifact exists for the current submodule SHA.
7. No generated `dist/` or `.dmg` artifacts are being committed.

After release CI finishes:

1. GitHub Release contains `cmux-macos.dmg` and `appcast.xml`.
2. `cmux-macos.dmg` downloads from `releases/latest/download`.
3. `xcrun stapler validate cmux-macos.dmg` passes on the downloaded artifact.
4. `scripts/smoke-installable-artifact.sh --channel stable cmux-macos.dmg` passes.
5. Sparkle appcast exists and references the new DMG.
6. Homebrew cask update completes, or any intentional skip is documented.
7. Production collaboration relay create/connect smoke passes.

## Failure Handling

### Locked Debug Build Database

If a tagged local debug retry fails with a locked Xcode build database:

```text
error: unable to attach DB: error: accessing build database ".../XCBuildData/build.db": database is locked
Possibly there are two concurrent builds running in the same filesystem location.
```

Wait for any existing build using the same tag to finish:

```bash
while pgrep -f 'xcodebuild .*cmux-run-current' >/dev/null; do sleep 5; done
```

Then rerun the tagged reload command. Avoid starting a second build against the same `cmux-<tag>` derived data path while another one is active.

### Partial Release Assets

If `release_asset_guard.js` reports partial immutable assets, do not rerun blindly. Either remove the partial assets from the GitHub Release after confirming they are not in use, or create a new tag. Partial asset state can leave an appcast pointing at the wrong artifact.

### Notarization Failure

If app or DMG notarization fails, fetch the notary log with the submission ID printed by CI:

```bash
xcrun notarytool log "$SUBMISSION_ID" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD"
```

Fix the signing, entitlement, or bundle issue and release with a new tag unless the failed assets were never published.

### Missing GhosttyKit Artifact

If release CI cannot find the prebuilt GhosttyKit for the current submodule SHA, run the GhosttyKit publishing workflow for that SHA before retrying the release. Do not move the parent repo to an unpushed or temporary submodule commit.

## Hard Rules

1. Do not ship a Debug app as the public installable.
2. Do not commit `*.dmg` files.
3. Do not commit generated Worker `dist/` output.
4. Do not overwrite stable release assets unless doing a documented emergency reroll.
5. Do not use bare `xcodebuild` or untagged `cmux DEV.app` for local agent verification.
6. Do not claim multiplayer is ready unless the production relay deploy and create/connect smoke pass.
7. Do not update download URLs unless every user-facing download surface is updated consistently.
