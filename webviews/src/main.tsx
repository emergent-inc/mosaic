type WebviewKind = "agent-session" | "diff";

function resolveWebviewKind(): WebviewKind {
  if (
    document.documentElement.dataset.mosaicWebviewKind === "agent-session" ||
    document.body.dataset.mosaicWebviewKind === "agent-session" ||
    document.getElementById("mosaic-agent-session-config")
  ) {
    return "agent-session";
  }
  return "diff";
}

const rootElement = document.getElementById("root");
if (!rootElement) {
  throw new Error("Missing mosaic webview root");
}

// Load only the active surface so each one ships as its own chunk: the diff
// viewer pulls in `@pierre/diffs`, the agent session pulls in its editor UI,
// and neither pays for the other. Shared vendor code (React, the router) is
// hoisted by Rollup into chunks both surfaces reuse.
if (resolveWebviewKind() === "agent-session") {
  void import("./surfaces/agentSessionSurface").then((surface) => {
    surface.mountAgentSessionSurface(rootElement);
  });
} else {
  void import("./surfaces/diffSurface").then((surface) => {
    surface.mountDiffSurface(rootElement);
  });
}
