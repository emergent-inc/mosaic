export type LocalizedText = {
  en: string;
};

export function localizedShortcutText(text: LocalizedText, _locale: string) {
  return text.en;
}

export type Shortcut = {
  id: string;
  combos: string[][];
  description: LocalizedText;
  note?: LocalizedText;
  configValue?: string;
};

export type ShortcutCategory = {
  id: string;
  titleKey: string;
  blurbKey?: string;
  shortcuts: Shortcut[];
};

export const shortcutCategories: ShortcutCategory[] = [
  {
    id: "app",
    titleKey: "app",
    blurbKey: "appBlurb",
    shortcuts: [
      { id: "openSettings", combos: [["⌘", ","]], description: { en: "Settings" } },
      { id: "reloadConfiguration", combos: [["⌘", "⇧", ","]], description: { en: "Reload configuration" } },
      {
        id: "showHideAllWindows",
        combos: [["⌃", "⌥", "⌘", "."]],
        description: { en: "Show/hide all cmux windows" },
        note: { en: "system-wide hotkey" },
      },
      {
        id: "globalSearch",
        combos: [["⌥", "⌘", "F"]],
        description: { en: "Global search" },
        note: { en: "system-wide hotkey" },
      },
      { id: "commandPalette", combos: [["⌘", "⇧", "P"]], description: { en: "Command palette" } },
      {
        id: "commandPaletteNext",
        combos: [["⌃", "N"]],
        description: { en: "Command palette next result" },
        note: { en: "when the command palette is open" },
      },
      {
        id: "commandPalettePrevious",
        combos: [["⌃", "P"]],
        description: { en: "Command palette previous result" },
        note: { en: "when the command palette is open" },
      },
      { id: "newWindow", combos: [["⌘", "⇧", "N"]], description: { en: "New window" } },
      { id: "closeWindow", combos: [["⌃", "⌘", "W"]], description: { en: "Close window" } },
      { id: "toggleFullScreen", combos: [["⌃", "⌘", "F"]], description: { en: "Toggle full screen" } },
      {
        id: "sendFeedback",
        combos: [],
        description: { en: "Send feedback" },
        note: { en: "unbound by default" },
      },
      {
        id: "reopenPreviousSession",
        combos: [["⌘", "⇧", "O"]],
        description: { en: "Reopen previous session" },
      },
      { id: "quit", combos: [["⌘", "Q"]], description: { en: "Quit cmux" } },
    ],
  },
  {
    id: "workspaces",
    titleKey: "workspaces",
    blurbKey: "workspacesBlurb",
    shortcuts: [
      { id: "toggleSidebar", combos: [["⌘", "B"]], description: { en: "Toggle left sidebar" } },
      { id: "toggleFileExplorer", combos: [["⌘", "⌥", "B"]], description: { en: "Toggle right sidebar" } },
      { id: "newTab", combos: [["⌘", "N"]], description: { en: "New workspace" } },
      {
        id: "newBrowserWorkspace",
        combos: [["⌥", "⌘", "N"]],
        description: { en: "New browser workspace" },
        note: {
          en: "like New Workspace, but the first surface is a browser pane with the address bar focused",
        },
      },
      { id: "openFolder", combos: [["⌘", "O"]], description: { en: "Open folder" } },
      {
        id: "goToWorkspace",
        combos: [["⌘", "P"]],
        description: { en: "Go to workspace" },
        note: { en: "workspace switcher" },
      },
      { id: "nextSidebarTab", combos: [["⌃", "⌘", "]"]], description: { en: "Next workspace" } },
      { id: "prevSidebarTab", combos: [["⌃", "⌘", "["]], description: { en: "Previous workspace" } },
      {
        id: "focusHistoryBack",
        combos: [["⌘", "["]],
        description: { en: "Focus back" },
        note: {
          en: "cmux uses Cmd+[ and Cmd+] for focus history by default. Unbind Focus Back/Forward in Settings to let browser or terminal shortcuts handle those keys.",
        },
      },
      {
        id: "focusHistoryForward",
        combos: [["⌘", "]"]],
        description: { en: "Focus forward" },
        note: {
          en: "cmux uses Cmd+[ and Cmd+] for focus history by default. Unbind Focus Back/Forward in Settings to let browser or terminal shortcuts handle those keys.",
        },
      },
      { id: "selectWorkspaceByNumber", combos: [["⌘", "1…9"]], description: { en: "Select workspace 1…9" } },
      { id: "renameWorkspace", combos: [["⌘", "⇧", "R"]], description: { en: "Rename workspace" } },
      { id: "editWorkspaceDescription", combos: [["⌥", "⌘", "E"]], description: { en: "Edit workspace description" } },
      { id: "newWorkspaceGroup", combos: [["⌃", "⌘", "G"]], description: { en: "New empty workspace group" } },
      { id: "groupSelectedWorkspaces", combos: [["⌘", "⇧", "G"]], description: { en: "Group selected workspaces" } },
      {
        id: "toggleFocusedWorkspaceGroupCollapsed",
        combos: [["⌃", "⌘", "."]],
        description: { en: "Collapse or expand focused workspace group" },
      },
      { id: "focusRightSidebar", combos: [["⌘", "⇧", "E"]], description: { en: "Toggle right-sidebar focus" } },
      {
        id: "navigateRightSidebarRows",
        combos: [["J / K"], ["⌃", "N / P"], ["H / L"]],
        description: { en: "Navigate focused sidebar rows" },
        note: {
          en: "In Files, H/L collapse and expand folders. Search starts with /.",
        },
      },
      {
        id: "fileExplorerOpenSelection",
        combos: [["↩"]],
        description: {
          en: "Open selected file or toggle folder",
        },
        note: {
          en: "focused file explorer",
        },
      },
      {
        id: "fileExplorerOpenSelectionFinderAlias",
        combos: [["⌘", "↓"]],
        description: {
          en: "Open selected file or toggle folder",
        },
        note: {
          en: "Finder-style alias for the focused file explorer",
        },
      },
      { id: "closeWorkspace", combos: [["⌘", "⇧", "W"]], description: { en: "Close workspace" } },
    ],
  },
  {
    id: "surfaces",
    titleKey: "surfaces",
    blurbKey: "surfacesBlurb",
    shortcuts: [
      { id: "newSurface", combos: [["⌘", "T"]], description: { en: "New surface" } },
      { id: "nextSurface", combos: [["⌘", "⇧", "]"]], description: { en: "Next surface" } },
      { id: "prevSurface", combos: [["⌘", "⇧", "["]], description: { en: "Previous surface" } },
      { id: "selectSurfaceByNumber", combos: [["⌃", "1…9"]], description: { en: "Select surface 1…9" } },
      { id: "renameTab", combos: [["⌘", "R"]], description: { en: "Rename tab" } },
      { id: "closeTab", combos: [["⌘", "W"]], description: { en: "Close tab" } },
      { id: "closeOtherTabsInPane", combos: [["⌥", "⌘", "T"]], description: { en: "Close other tabs in pane" } },
      { id: "reopenClosedBrowserPanel", combos: [["⌘", "⇧", "T"]], description: { en: "Reopen last closed" } },
      { id: "toggleTerminalCopyMode", combos: [["⌘", "⇧", "M"]], description: { en: "Toggle terminal copy mode" } },
      { id: "clearScreenKeepScrollback", combos: [["⌘", "⇧", "K"]], description: { en: "Clear screen (keep scrollback)" } },
      { id: "focusTextBoxInput", combos: [["⌘", "⇧", "A"]], description: { en: "Switch focus between terminal and TextBox input" } },
      { id: "attachTextBoxFile", combos: [["⌥", "⌘", "⇧", "A"]], description: { en: "Attach file to TextBox input" } },
      {
        id: "sendCtrlFToTerminal",
        combos: [],
        description: { en: "Send Ctrl-F to terminal" },
        note: {
          en: "unbound by default; forwards Ctrl-F to the focused terminal (Claude Code: invoke twice to force-stop hung background agents)",
        },
      },
      {
        id: "saveFilePreview",
        combos: [["⌘", "S"]],
        description: { en: "Save file preview" },
        note: { en: "focused text preview" },
      },
    ],
  },
  {
    id: "split-panes",
    titleKey: "splitPanes",
    shortcuts: [
      { id: "focusLeft", combos: [["⌥", "⌘", "←"]], description: { en: "Focus pane left" } },
      { id: "focusRight", combos: [["⌥", "⌘", "→"]], description: { en: "Focus pane right" } },
      { id: "focusUp", combos: [["⌥", "⌘", "↑"]], description: { en: "Focus pane up" } },
      { id: "focusDown", combos: [["⌥", "⌘", "↓"]], description: { en: "Focus pane down" } },
      { id: "splitRight", combos: [["⌘", "D"]], description: { en: "Split right" } },
      { id: "splitDown", combos: [["⌘", "⇧", "D"]], description: { en: "Split down" } },
      { id: "splitBrowserRight", combos: [["⌥", "⌘", "D"]], description: { en: "Split browser right" } },
      { id: "splitBrowserDown", combos: [["⌥", "⌘", "⇧", "D"]], description: { en: "Split browser down" } },
      { id: "toggleSplitZoom", combos: [["⌘", "⇧", "↩"]], description: { en: "Toggle pane zoom" } },
      { id: "equalizeSplits", combos: [["⌃", "⌘", "="]], description: { en: "Equalize split sizes" } },
    ],
  },
  {
    id: "canvas",
    titleKey: "canvas",
    blurbKey: "canvasBlurb",
    shortcuts: [
      { id: "toggleCanvasLayout", combos: [["⌃", "⌘", "C"]], description: { en: "Toggle canvas layout" } },
      { id: "canvasRevealFocusedPane", combos: [["⌃", "⌘", "R"]], description: { en: "Reveal focused pane" } },
      { id: "canvasOverview", combos: [["⌃", "⌘", "O"]], description: { en: "Toggle overview zoom" } },
      { id: "canvasZoomIn", combos: [["⌥", "⌘", "="]], description: { en: "Zoom in" } },
      { id: "canvasZoomOut", combos: [["⌥", "⌘", "-"]], description: { en: "Zoom out" } },
      { id: "canvasZoomReset", combos: [["⌘", "0"]], description: { en: "Actual size" } },
      { id: "canvasTidy", combos: [["⌃", "⌘", "T"]], description: { en: "Tidy panes into a grid" } },
    ],
  },
  {
    id: "browser",
    titleKey: "browser",
    shortcuts: [
      { id: "openBrowser", combos: [["⌘", "⇧", "L"]], description: { en: "Open browser" } },
      { id: "focusBrowserAddressBar", combos: [["⌘", "L"]], description: { en: "Focus address bar" } },
      { id: "browserBack", combos: [["⌘", "["]], description: { en: "Back" } },
      { id: "browserForward", combos: [["⌘", "]"]], description: { en: "Forward" } },
      {
        id: "browserReload",
        combos: [["⌘", "R"]],
        description: { en: "Reload page" },
        note: { en: "focused browser" },
      },
      {
        id: "browserHardReload",
        combos: [["⌘", "⇧", "R"]],
        description: {
          en: "Hard refresh page",
        },
        note: {
          en: "focused browser",
        },
      },
      { id: "browserZoomIn", combos: [["⌘", "="]], description: { en: "Zoom in" } },
      { id: "browserZoomOut", combos: [["⌘", "-"]], description: { en: "Zoom out" } },
      { id: "browserZoomReset", combos: [["⌘", "0"]], description: { en: "Actual size" } },
      {
        id: "markdownZoomIn",
        combos: [["⌘", "="]],
        description: { en: "Markdown viewer: zoom in" },
        note: { en: "focused markdown viewer" },
      },
      {
        id: "markdownZoomOut",
        combos: [["⌘", "-"]],
        description: { en: "Markdown viewer: zoom out" },
        note: { en: "focused markdown viewer" },
      },
      {
        id: "markdownZoomReset",
        combos: [["⌘", "0"]],
        description: { en: "Markdown viewer: actual size" },
        note: { en: "focused markdown viewer" },
      },
      { id: "toggleBrowserDeveloperTools", combos: [["⌥", "⌘", "I"]], description: { en: "Toggle browser developer tools" } },
      { id: "showBrowserJavaScriptConsole", combos: [["⌥", "⌘", "C"]], description: { en: "Show browser JavaScript console" } },
      {
        id: "toggleBrowserFocusMode",
        combos: [["⌥", "⌘", "↩"]],
        description: { en: "Enter browser focus mode" },
        note: { en: "Gives the focused web page first claim on shortcuts. Press Esc twice to exit." },
      },
      {
        id: "toggleReactGrab",
        combos: [["⌘", "⇧", "G"]],
        description: { en: "Toggle React Grab" },
        note: {
          en: "focused browser, or the only browser pane when a terminal is focused",
        },
      },
    ],
  },
  {
    id: "diff-viewer",
    titleKey: "diffViewer",
    shortcuts: [
      {
        id: "openDiffViewer",
        combos: [["⌃", "⌘", "⇧", "D"]],
        description: { en: "Open diff viewer" },
      },
      {
        id: "diffViewerScrollDown",
        combos: [["J"]],
        description: { en: "Scroll diff down" },
        note: { en: "focused diff viewer" },
      },
      {
        id: "diffViewerScrollUp",
        combos: [["K"]],
        description: { en: "Scroll diff up" },
        note: { en: "focused diff viewer" },
      },
      {
        id: "diffViewerScrollToBottom",
        combos: [["⇧", "G"]],
        description: { en: "Scroll diff to bottom" },
        note: { en: "focused diff viewer" },
      },
      {
        id: "diffViewerScrollToTop",
        combos: [["G", "G"]],
        description: { en: "Scroll diff to top" },
        note: { en: "focused diff viewer" },
        configValue: '["g", "g"]',
      },
      {
        id: "diffViewerOpenFileSearch",
        combos: [["/"]],
        description: { en: "Open diff file search" },
        note: { en: "focused diff viewer" },
      },
    ],
  },
  {
    id: "find",
    titleKey: "find",
    shortcuts: [
      { id: "find", combos: [["⌘", "F"]], description: { en: "Find" } },
      { id: "findInDirectory", combos: [["⌘", "⇧", "F"]], description: { en: "Find in directory" } },
      { id: "findNext", combos: [["⌘", "G"]], description: { en: "Find next" } },
      { id: "findPrevious", combos: [["⌥", "⌘", "G"]], description: { en: "Find previous" } },
      { id: "hideFind", combos: [["⌥", "⌘", "⇧", "F"]], description: { en: "Hide find bar" } },
      { id: "useSelectionForFind", combos: [["⌘", "E"]], description: { en: "Use selection for find" } },
    ],
  },
  {
    id: "notifications",
    titleKey: "notifications",
    shortcuts: [
      { id: "showNotifications", combos: [["⌘", "I"]], description: { en: "Show notifications" } },
      { id: "jumpToUnread", combos: [["⌘", "⇧", "U"]], description: { en: "Jump to latest unread" } },
      { id: "toggleUnread", combos: [["⌥", "⌘", "U"]], description: { en: "Toggle current item unread state" } },
      { id: "markOldestUnreadAndJumpNext", combos: [["⌃", "⌘", "U"]], description: { en: "Mark current item as oldest unread and jump to the next latest unread" } },
      { id: "triggerFlash", combos: [["⌘", "⇧", "H"]], description: { en: "Flash focused panel" } },
    ],
  },
];
