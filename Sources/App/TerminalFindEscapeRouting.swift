import AppKit
import MosaicTerminal

@MainActor
func mosaicCloseFocusedTerminalFindForEscape(event: NSEvent, appDelegate: AppDelegate) -> Bool {
    guard mosaicFindEventIsPlainEscape(event) else { return false }

    let shortcutWindow = event.window
        ?? (event.windowNumber > 0 ? NSApp.window(withWindowNumber: event.windowNumber) : nil)
        ?? NSApp.keyWindow
        ?? NSApp.mainWindow
    if shortcutWindow?.firstResponder is TextBoxInputTextView {
        return false
    }
    let terminalFindFieldOwnsResponder = mosaicFindTextFieldOwner(for: shortcutWindow?.firstResponder)?
        .identifier?.rawValue == "TerminalFindSearchTextField"
    let targetTabManager = appDelegate.synchronizeActiveMainWindowContext(preferredWindow: shortcutWindow)

    guard let panel = (targetTabManager ?? appDelegate.tabManager)?.selectedTerminalPanel,
          panel.searchState != nil,
          !browserResponderHasMarkedText(shortcutWindow?.firstResponder),
          terminalFindFieldOwnsResponder || appDelegate.allowsTerminalKeyboardFocus(
              workspaceId: panel.workspaceId,
              panelId: panel.id,
              in: shortcutWindow
          ) else {
        return false
    }

#if DEBUG
    mosaicDebugLog("find.escape.close terminal panel=\(panel.id.uuidString.prefix(5))")
#endif
    panel.hostedView.beginFindEscapeSuppression()
    panel.searchState = nil
    panel.hostedView.moveFocus()
    return true
}
