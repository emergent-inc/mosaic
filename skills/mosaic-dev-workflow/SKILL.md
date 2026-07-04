---
name: mosaic-dev-workflow
description: "Contributor workflow rules for mosaic setup, Xcode project normalization, tagged sidebar ExtensionKit development, and dev builds. Use when setting up the mosaic repo, changing Xcode project files, adding sidebar extensions, or working with tagged debug builds."
---

# mosaic Dev Workflow

## Tagged local dev

After making code changes, always run the reload script with a tag to build the Debug app:

```bash
./scripts/reload.sh --tag <short-tag>
```

By default, `reload.sh` builds but does not launch the app. Pass `--launch` only when you need to open it automatically.

Never run bare `xcodebuild` or open an untagged `Mosaic DEV.app`. Untagged builds share the default debug socket and bundle ID with other agents, causing conflicts and stealing focus.

For CLI or socket dogfood against a tagged Debug app, use the tag-bound helper and set `MOSAIC_TAG`:

```bash
MOSAIC_TAG=<tag> scripts/mosaic-debug-cli.sh list-workspaces
```

Do not use `/tmp/mosaic-cli` for tagged dogfood. That symlink points at the most recently reloaded build.

When rebuilding mosaicd for release/bundling, always use ReleaseFast:

```bash
cd mosaicd && zig build -Doptimize=ReleaseFast
```

## Initial setup

Run the setup script to initialize submodules, build GhosttyKit, and install the pbxproj normalization pre-commit hook:

```bash
./scripts/setup.sh
```

## Xcode toolchain

The team is pinned to Xcode 26.x. `.xcode-version` records the major; `mosaic.xcodeproj/project.pbxproj` carries `objectVersion = 60`, which is what Xcode 26 writes by default. (objectVersion 77 is reserved for projects that adopt synchronized folder groups, which mosaic does not use yet. Bumping to a different value requires a deliberate team decision.)

`scripts/setup.sh` installs a tracked pre-commit hook (`scripts/git-hooks/pre-commit`) that runs `scripts/normalize-pbxproj.py` on any staged `mosaic.xcodeproj/project.pbxproj`, sorting the high-churn sections so Xcode's nondeterministic reordering never reaches a commit. The hook is idempotent. CI runs `scripts/check-pbxproj.sh` to enforce both the `objectVersion` pin and normalization, so anyone who skips the hook (or never ran setup) gets a clear failure on their PR.

`.xcode-version` is the single source of truth. To bump the pin: edit `.xcode-version`, open `mosaic.xcodeproj` in the new Xcode (which rewrites `objectVersion` automatically when it touches the file), and add a case for the new Xcode major in `scripts/check-pbxproj.sh` mapping it to the `objectVersion` that major writes.

## Sidebar extension point (dev tagging)

Each tagged dev build gets its own ExtensionKit sidebar extension point so concurrent dev builds don't collide. Three build settings drive this:

- `MOSAIC_SIDEBAR_EXTENSION_POINT_ID` (default `mosaic.com.emergent.app.mosaic.sidebar`): the extension point identifier baked into Info.plist at build time.
- `MOSAIC_BUNDLE_ID_SUFFIX` (default empty): inserted into the app and appex bundle ids so a tagged extension gets a distinct identity that pkd records separately.
- `MOSAIC_DISPLAY_NAME_SUFFIX` (default empty): appended to the appex `CFBundleDisplayName`. The OS groups sidebar extensions by display name for the enable/disable + availability counts the host reads (`AppExtensionIdentity` exposes only `bundleIdentifier`, `localizedName`, `extensionPointIdentifier`, `id` — mosaic already keys its own identity off the stable `bundleIdentifier`, but the OS-level grouping is by name). Two same-named appexes installed side by side (a base build and a tagged build) are treated as one logical extension, so toggling one perturbs the other; a per-tag display name keeps them distinct.

The host resolves its point id at runtime from the Info.plist key `MosaicSidebarExtensionPointIdentifier` via `MosaicSidebarExtensionPoint.identifier(in:)`. `./scripts/reload.sh --tag <tag>` scopes the host point to `mosaic.com.emergent.app.debug.<tag>.mosaic.sidebar`. `./scripts/reload-extension.sh --tag <tag> [--host-bundle-id <id>] [--example sample|tabs|both]` builds a matching tag-scoped sample extension, passing `MOSAIC_SIDEBAR_EXTENSION_POINT_ID=<host-bundle-id>.mosaic.sidebar`, `MOSAIC_BUNDLE_ID_SUFFIX=.<tag>`, and `MOSAIC_DISPLAY_NAME_SUFFIX=" <tag>"`. It installs exactly what xcodebuild produced (xcodebuild ad-hoc signs with entitlements intact) — it does NOT re-sign, because a bare `codesign --force --sign -` strips the appex entitlements and the extension then drops its host XPC connection. pkd ingests the tagged copy because its bundle id is distinct. Verify with `pluginkit -m -p <host-bundle-id>.mosaic.sidebar`.

To author a NEW sample extension that is tag-ready:

- appex Info.plist: `EXAppExtensionAttributes:EXExtensionPointIdentifier = $(MOSAIC_SIDEBAR_EXTENSION_POINT_ID)`.
- add `MOSAIC_SIDEBAR_EXTENSION_POINT_ID` (default `mosaic.com.emergent.app.mosaic.sidebar`), `MOSAIC_BUNDLE_ID_SUFFIX` (default empty), and `MOSAIC_DISPLAY_NAME_SUFFIX` (default empty) build settings to the app and appex targets in all build configs.
- `PRODUCT_BUNDLE_IDENTIFIER` = `<appBase>$(MOSAIC_BUNDLE_ID_SUFFIX)` for the app target and `<appBase>$(MOSAIC_BUNDLE_ID_SUFFIX).<leaf>` for the appex (suffix before the appex leaf so the appex id stays prefixed by the app id).
- appex `INFOPLIST_KEY_CFBundleDisplayName` (or the `CFBundleDisplayName` Info.plist value) = `<Name>$(MOSAIC_DISPLAY_NAME_SUFFIX)`.
- it must be ad-hoc signed by xcodebuild (Info.plist bound, entitlements intact) for pkd to ingest the tagged copy; do not re-sign post-build.

## Detailed references

- Read [references/tagged-builds.md](references/tagged-builds.md) for detailed tagged reload, app link, socket, and cleanup behavior.
- Read [references/xcode-project-normalization.md](references/xcode-project-normalization.md) before touching `.xcode-version` or `mosaic.xcodeproj/project.pbxproj`.
- Read [references/sidebar-extension-tagging.md](references/sidebar-extension-tagging.md) when changing ExtensionKit sidebar extension identifiers, tagged sample extensions, or `pluginkit` verification.
