# Localization Audit Workflow

This reference expands the localization rules for cmux.

## What counts as user-facing

Treat text as user-facing if it can appear in:

- SwiftUI views
- AppKit menus and dialogs
- alerts and confirmation sheets
- tooltips and accessibility labels
- Settings rows and descriptions
- command palette entries
- keyboard shortcut metadata
- CLI help or command output
- JSON schema descriptions shown in docs or editors
- docs pages
- web UI
- generated configuration examples shown to users

Internal debug-only labels may still deserve localization if they are visible in the Debug menu or a debug window used by contributors.

## Swift and AppKit

Use:

```swift
String(localized: "key.name", defaultValue: "English text")
```

Update `Resources/Localizable.xcstrings` for supported user-facing app strings. English is currently the only supported language.

Do not rely on `defaultValue` as the English localization. It is a fallback and development convenience, not a completed localization entry.

## Web and docs

For localized web/docs content, update:

- `web/messages/en.json`
- any data structures carrying user-facing text

Keep English message keys aligned with the code paths that read them.

## Bare English search

After changing Swift, TS, TSX, or docs files, search the changed files for newly introduced user-facing English. Useful patterns include:

```bash
git diff --name-only -- '*.swift' '*.ts' '*.tsx' '*.md'
rg 'Text\\("[A-Z][^"]+"' -- '*.swift'
rg 'Button\\("[A-Z][^"]+"' -- '*.swift'
rg 'tooltip|alert|title|description|label' -- '*.swift' '*.ts' '*.tsx'
```

These searches are not proof by themselves. They are prompts to inspect likely user-facing strings.

## Final handoff

Every UI/text-affecting final handoff should state:

- which surfaces changed
- which localization files were updated
- which audit commands or manual checks were run
- anything that could not be verified

If no user-facing strings changed, say that clearly.
