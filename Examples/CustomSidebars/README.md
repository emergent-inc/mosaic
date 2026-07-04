# Custom Sidebar Examples

These are vibe-coded mosaic sidebars that run as interpreted SwiftUI-style files.
They do not need Xcode, signing, or a build step.

The examples intentionally keep their labels inline because interpreted
sidebars do not have a localization catalog yet.

Install one by copying it into your custom sidebar directory:

```bash
mkdir -p ~/.config/mosaic/sidebars
cp Examples/CustomSidebars/status-board.swift ~/.config/mosaic/sidebars/status-board.swift
cp Examples/CustomSidebars/finder.swift ~/.config/mosaic/sidebars/finder.swift
```

Then enable **Settings -> Beta features -> Custom sidebars** and pick it from
the sidebar toggle button's right-click menu.

You can validate a copied sidebar with:

```bash
mosaic sidebar validate status-board
mosaic sidebar validate finder
```

## Included Sidebars

- `status-board.swift`: groups workspaces into urgent, review, progress,
  research, and done lanes using live PR, branch, progress, unread, and prompt
  signals.
- `finder.swift`: a macOS Finder-style workspace browser with a source list,
  selected workspace inspector, and tab list.

See `docs/custom-sidebars.md` for the full authoring contract.
