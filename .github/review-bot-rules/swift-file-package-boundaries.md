# Swift File And Package Boundaries

Flag Swift changes that add too much unrelated responsibility to one file or keep independently testable feature logic inside the app target when it should be isolated behind a SwiftPM package boundary.

Report a failure when the diff introduces or materially expands:

- A new production Swift file over 400 lines without a clear single responsibility, or over 800 lines even when the responsibility is mostly coherent.
- More than 250 lines added to an existing production Swift file that is already over 800 lines, unless the PR is actively extracting code out of that file.
- A file that mixes UI rendering, state ownership, persistence, networking, parsing, subprocess/socket protocol, and platform bridge code in one place.
- A feature implemented directly in `Sources/` when its core logic is independent of cmux app lifecycle and can compile/test without AppKit, SwiftUI view state, Ghostty globals, or process-wide singletons.
- Reusable domain logic used by more than one surface (Mac app, CLI, daemon, tests, previews, debug tooling, future iOS/shared code) without a small SwiftPM package target.
- Provider, auth, protocol, parsing, persistence, logging, or workstream logic that needs isolated fakes, fixtures, or unit tests but is hidden behind app-target globals.

Package-boundary signals:

- The code has a stable domain noun and public API that can be expressed without view types.
- The code needs tests that should run without launching cmux or constructing app UI.
- The code owns data formats, network/provider contracts, socket messages, credentials, persistence schemas, or cross-surface state transitions.
- The feature would be safer if callers depended on a small protocol or value API instead of a concrete app singleton.

Allowed cases:

- Existing oversized files that the PR only touches incidentally.
- Small UI-only views, AppKit bridges, app delegates, menu wiring, and Ghostty integration glue that are inherently app-target code.
- Focused bug fixes that add a small amount of code to a large file while preserving a clear extraction path.
- Generated files, vendored code, prototypes, and test fixtures.
- New package creation that starts small and intentionally leaves app-specific UI composition in `Sources/`.

When reporting, include the file or feature boundary, the approximate line-count pressure, the responsibilities being mixed, and the smallest extraction cut. If a package is the right shape, name the proposed package target and the first public type or protocol it should expose.
