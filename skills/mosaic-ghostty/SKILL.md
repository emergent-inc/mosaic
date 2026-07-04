---
name: mosaic-ghostty
description: "Ghostty submodule and GhosttyKit workflow rules for mosaic. Use when modifying the ghostty submodule, rebuilding GhosttyKit.xcframework, updating the parent submodule pointer, or documenting fork conflict notes."
---

# mosaic Ghostty

## GhosttyKit builds

When rebuilding GhosttyKit.xcframework, always use Release optimizations:

```bash
cd ghostty && zig build -Demit-xcframework=true -Dxcframework-target=universal -Doptimize=ReleaseFast
```

## Submodule workflow

Ghostty changes must be committed in the `ghostty` submodule and pushed to the `emergent-inc/ghostty` fork. Keep `docs/ghostty-fork.md` up to date with any fork changes and conflict notes.

```bash
cd ghostty
git remote -v  # origin = upstream, emergent.inc = fork
git checkout -b <branch>
git add <files>
git commit -m "..."
git push emergent.inc <branch>
```

To keep the fork up to date with upstream:

```bash
cd ghostty
git fetch origin
git checkout main
git merge origin/main
git push emergent.inc main
```

Then update the parent repo with the new submodule SHA:

```bash
cd ..
git add ghostty
git commit -m "Update ghostty submodule"
```

## Submodule safety

When modifying a submodule, always push the submodule commit to its remote `main` branch before committing the updated pointer in the parent repo. Never commit on a detached HEAD or temporary branch; the commit can be orphaned and lost.

Verify with:

```bash
cd <submodule> && git merge-base --is-ancestor HEAD origin/main
```

## Detailed reference

- Read [references/submodule-safety.md](references/submodule-safety.md) before committing submodule pointer updates or resolving Ghostty fork conflicts.
