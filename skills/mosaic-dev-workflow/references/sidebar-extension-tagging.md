# Sidebar Extension Tagging

Tagged dev builds need distinct ExtensionKit sidebar extension points so concurrent dev builds do not collide.

## Build settings

Three build settings drive the tagging model:

- `MOSAIC_SIDEBAR_EXTENSION_POINT_ID`
- `MOSAIC_BUNDLE_ID_SUFFIX`
- `MOSAIC_DISPLAY_NAME_SUFFIX`

The default extension point is:

```text
mosaic.com.emergent.app.mosaic.sidebar
```

Tagged host builds scope it to:

```text
mosaic.com.emergent.app.debug.<tag>.mosaic.sidebar
```

## Why display name matters

`AppExtensionIdentity` exposes stable fields such as bundle identifier, localized name, extension point identifier, and id. mosaic keys its identity off the stable bundle identifier, but OS-level enable/disable and availability grouping uses display name.

Two same-named appexes installed side by side can be treated as one logical extension. Per-tag display names keep tagged sample extensions distinct.

## Tagged sample extensions

`./scripts/reload-extension.sh --tag <tag> [--host-bundle-id <id>] [--example sample|tabs|both]` builds a matching tag-scoped sample extension.

It passes:

- `MOSAIC_SIDEBAR_EXTENSION_POINT_ID=<host-bundle-id>.mosaic.sidebar`
- `MOSAIC_BUNDLE_ID_SUFFIX=.<tag>`
- `MOSAIC_DISPLAY_NAME_SUFFIX=" <tag>"`

It installs exactly what xcodebuild produced. It does not re-sign. A bare `codesign --force --sign -` strips appex entitlements and the extension drops its host XPC connection.

## New sample extension checklist

For a new tag-ready sample extension:

- appex Info.plist has `EXAppExtensionAttributes:EXExtensionPointIdentifier = $(MOSAIC_SIDEBAR_EXTENSION_POINT_ID)`
- app and appex targets define `MOSAIC_SIDEBAR_EXTENSION_POINT_ID`
- app and appex targets define `MOSAIC_BUNDLE_ID_SUFFIX`
- app and appex targets define `MOSAIC_DISPLAY_NAME_SUFFIX`
- app `PRODUCT_BUNDLE_IDENTIFIER` uses `<appBase>$(MOSAIC_BUNDLE_ID_SUFFIX)`
- appex `PRODUCT_BUNDLE_IDENTIFIER` uses `<appBase>$(MOSAIC_BUNDLE_ID_SUFFIX).<leaf>`
- appex display name appends `$(MOSAIC_DISPLAY_NAME_SUFFIX)`
- xcodebuild ad-hoc signs the appex with entitlements intact

Verify with:

```bash
pluginkit -m -p <host-bundle-id>.mosaic.sidebar
```
