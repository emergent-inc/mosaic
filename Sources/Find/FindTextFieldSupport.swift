import AppKit

enum FindFocusNotificationKey {
    static let selectAll = "mosaic.find.selectAll"
}

func mosaicClampedFindSelection(_ range: NSRange, in text: String) -> NSRange {
    let textLength = text.utf16.count
    guard range.location != NSNotFound else {
        return NSRange(location: textLength, length: 0)
    }
    let location = min(max(range.location, 0), textLength)
    let length = min(max(range.length, 0), textLength - location)
    return NSRange(location: location, length: length)
}

func mosaicTextFieldIsFirstResponder(_ field: NSTextField, in window: NSWindow) -> Bool {
    let firstResponder = window.firstResponder
    if firstResponder === field { return true }
    if let editor = field.currentEditor() as? NSTextView, firstResponder === editor { return true }
    return (firstResponder as? NSTextView).flatMap { mosaicFieldEditorOwnerView($0) } === field
}

private let mosaicFindSelectionChangingCommands: Set<String> = [
    "moveLeft:",
    "moveRight:",
    "moveBackward:",
    "moveForward:",
    "moveUp:",
    "moveDown:",
    "moveWordLeft:",
    "moveWordRight:",
    "moveWordBackward:",
    "moveWordForward:",
    "moveToBeginningOfLine:",
    "moveToEndOfLine:",
    "moveToBeginningOfDocument:",
    "moveToEndOfDocument:",
    "moveLeftAndModifySelection:",
    "moveRightAndModifySelection:",
    "moveBackwardAndModifySelection:",
    "moveForwardAndModifySelection:",
    "moveUpAndModifySelection:",
    "moveDownAndModifySelection:",
    "moveWordLeftAndModifySelection:",
    "moveWordRightAndModifySelection:",
    "moveWordBackwardAndModifySelection:",
    "moveWordForwardAndModifySelection:",
    "moveToBeginningOfLineAndModifySelection:",
    "moveToEndOfLineAndModifySelection:",
    "moveToBeginningOfDocumentAndModifySelection:",
    "moveToEndOfDocumentAndModifySelection:",
    "selectAll:",
]

func mosaicFindCommandMayChangeSelection(_ selector: Selector) -> Bool {
    mosaicFindSelectionChangingCommands.contains(NSStringFromSelector(selector))
}

func mosaicFindEventIsPlainEscape(_ event: NSEvent) -> Bool {
    ShortcutStroke.normalizedModifierFlags(from: event.modifierFlags).isEmpty && ShortcutStroke.isEscapeCancelEvent(event)
}

private let mosaicFindSelectionStore = NSMapTable<AnyObject, NSValue>.weakToStrongObjects()
private let mosaicFindFieldEditorOwners = NSMapTable<NSTextView, FindSelectionTrackingTextField>.weakToWeakObjects()

func mosaicStoredFindSelection(for owner: AnyObject?) -> NSRange? {
    guard let owner else { return nil }
    return mosaicFindSelectionStore.object(forKey: owner)?.rangeValue
}

func mosaicStoreFindSelection(_ range: NSRange, for owner: AnyObject?) {
    guard let owner else { return }
    mosaicFindSelectionStore.setObject(NSValue(range: range), forKey: owner)
}

func mosaicTrackedFindFieldEditorOwner(_ editor: NSTextView) -> FindSelectionTrackingTextField? {
    guard editor.isFieldEditor else { return nil }
    return mosaicFindFieldEditorOwners.object(forKey: editor)
}

func mosaicFindTextFieldOwner(for responder: NSResponder?) -> FindSelectionTrackingTextField? {
    if let field = responder as? FindSelectionTrackingTextField {
        return field
    }
    if let editor = responder as? NSTextView {
        return mosaicTrackedFindFieldEditorOwner(editor) ?? (mosaicFieldEditorOwnerView(editor) as? FindSelectionTrackingTextField)
    }
    return nil
}

@MainActor
func mosaicRememberFindSelectionBeforePanelFocusMove(tabManager: TabManager?, window: NSWindow?) {
    guard let editor = window?.firstResponder as? NSTextView else { return }
    let selection = mosaicClampedFindSelection(editor.selectedRange(), in: editor.string)
    if let field = mosaicTrackedFindFieldEditorOwner(editor),
       let owner = field.mosaicSelectionOwner {
        _ = field.mosaicRememberSelection(selection, in: editor.string)
        mosaicStoreFindSelection(selection, for: owner)
        return
    }
    guard let workspace = tabManager?.selectedWorkspace,
          let focusedPanelId = workspace.focusedPanelId else { return }
    let owner = (workspace.terminalPanel(for: focusedPanelId)?.searchState as AnyObject?) ?? (workspace.browserPanel(for: focusedPanelId)?.searchState as AnyObject?)
    guard let owner else { return }
    mosaicStoreFindSelection(selection, for: owner)
}

@discardableResult
func mosaicApplyFindFocusSelection(
    field: FindSelectionTrackingTextField,
    selectAll: Bool,
    alreadyFocused: Bool,
    rememberedRange: NSRange?
) -> NSRange? {
    guard let editor = field.currentEditor() as? NSTextView, !editor.hasMarkedText() else { return nil }
    if selectAll {
        let selection = field.mosaicRememberSelection(NSRange(location: 0, length: editor.string.utf16.count), in: editor.string)
        editor.setSelectedRange(selection)
        return selection
    }
    guard !alreadyFocused, let rememberedRange else { return nil }
    let selection = field.mosaicRememberSelection(rememberedRange, in: editor.string)
    editor.setSelectedRange(selection)
    return selection
}

@discardableResult
func mosaicRememberFindSelection(in root: NSView?) -> NSRange? {
    guard let root else { return nil }
    if let field = root as? FindSelectionTrackingTextField,
       let selection = field.mosaicRememberSelectionFromCurrentEditor() {
        return selection
    }
    for subview in root.subviews {
        if let selection = mosaicRememberFindSelection(in: subview) {
            return selection
        }
    }
    return nil
}

func mosaicFindResponderSnapshot() -> [String: String] {
    let responder = (NSApp.keyWindow ?? NSApp.mainWindow)?.firstResponder
    var updates: [String: String] = [
        "firstResponderType": responder.map { String(describing: type(of: $0)) } ?? "",
        "firstResponderIdentifier": (responder as? NSView)?.identifier?.rawValue ?? "",
    ]
    if let textView = responder as? NSTextView {
        updates["firstResponderSelectedRange"] = NSStringFromRange(textView.selectedRange())
        if let owner = mosaicFieldEditorOwnerView(textView) {
            updates["fieldEditorOwnerType"] = String(describing: type(of: owner))
            updates["fieldEditorOwnerIdentifier"] = owner.identifier?.rawValue ?? ""
        }
    }
    return updates
}

class FindSelectionTrackingTextField: NSTextField {
    var mosaicLastSelectedRange: NSRange?
    weak var mosaicSelectionOwner: AnyObject?
    var mosaicOnEscape: ((NSTextView) -> Bool)?
    private var mosaicSelectionObserver: NSObjectProtocol?
    private var mosaicKeyMonitor: Any?
    private weak var mosaicObservedEditor: NSTextView?
    private weak var mosaicPreviousEditorNextResponder: NSResponder?

    deinit {
        mosaicDetachSelectionObserver()
        mosaicRemoveKeyMonitor()
    }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        mosaicAttachSelectionObserverIfNeeded()
        mosaicRestoreRememberedSelection()
        return true
    }

    override func textDidBeginEditing(_ notification: Notification) {
        super.textDidBeginEditing(notification)
        mosaicAttachSelectionObserverIfNeeded()
        mosaicInstallKeyMonitorIfNeeded()
        if mosaicLastSelectedRange == nil, mosaicStoredFindSelection(for: mosaicSelectionOwner) == nil {
            _ = mosaicRememberSelectionFromCurrentEditor()
        }
    }

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        _ = mosaicRememberSelectionFromCurrentEditor()
    }

    override func textDidEndEditing(_ notification: Notification) {
        _ = mosaicRememberSelectionFromCurrentEditor()
        mosaicRemoveKeyMonitor()
        mosaicDetachSelectionObserver()
        super.textDidEndEditing(notification)
    }

    override func cancelOperation(_ sender: Any?) {
        if let editor = currentEditor() as? NSTextView, !editor.hasMarkedText(), mosaicOnEscape?(editor) == true {
            return
        }
        super.cancelOperation(sender)
    }

    func mosaicRememberSelection(_ range: NSRange, in text: String) -> NSRange {
        let selection = mosaicClampedFindSelection(range, in: text)
        mosaicLastSelectedRange = selection
        mosaicStoreFindSelection(selection, for: mosaicSelectionOwner)
        return selection
    }

    func mosaicRememberSelection(from textView: NSTextView) -> NSRange {
        mosaicRememberSelection(textView.selectedRange(), in: textView.string)
    }

    func mosaicRememberSelectionFromCurrentEditor() -> NSRange? {
        guard let editor = currentEditor() as? NSTextView else { return nil }
        return mosaicRememberSelection(from: editor)
    }

    private func mosaicAttachSelectionObserverIfNeeded() {
        guard let editor = currentEditor() as? NSTextView else { return }
        if let mosaicObservedEditor, mosaicObservedEditor !== editor {
            mosaicDetachSelectionObserver()
        }
        mosaicAdoptFieldEditor(editor)
        guard mosaicSelectionObserver == nil else { return }
        mosaicSelectionObserver = NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeSelectionNotification,
            object: editor,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let textView = notification.object as? NSTextView else { return }
            _ = self.mosaicRememberSelection(from: textView)
        }
    }

    private func mosaicDetachSelectionObserver() {
        if let mosaicSelectionObserver {
            NotificationCenter.default.removeObserver(mosaicSelectionObserver)
            self.mosaicSelectionObserver = nil
        }
        if let editor = mosaicObservedEditor {
            if editor.nextResponder === self {
                editor.nextResponder = mosaicPreviousEditorNextResponder
            }
            if mosaicTrackedFindFieldEditorOwner(editor) === self {
                mosaicFindFieldEditorOwners.removeObject(forKey: editor)
            }
        }
        mosaicPreviousEditorNextResponder = nil
        mosaicObservedEditor = nil
    }

    private func mosaicAdoptFieldEditor(_ editor: NSTextView) {
        mosaicObservedEditor = editor
        mosaicFindFieldEditorOwners.setObject(self, forKey: editor)
        if editor.nextResponder !== self {
            mosaicPreviousEditorNextResponder = editor.nextResponder
            editor.nextResponder = self
        }
        mosaicInstallKeyMonitorIfNeeded()
    }

    private func mosaicInstallKeyMonitorIfNeeded() {
        guard mosaicKeyMonitor == nil else { return }
        mosaicKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let eventWindow = event.window ?? (event.windowNumber > 0 ? NSApp.window(withWindowNumber: event.windowNumber) : nil)
            guard let self,
                  eventWindow == nil || eventWindow === self.window,
                  let editor = self.currentEditor() as? NSTextView,
                  self.window?.firstResponder === editor else { return event }
            if mosaicFindEventIsPlainEscape(event), !editor.hasMarkedText(), self.mosaicOnEscape?(editor) == true { return nil }
            DispatchQueue.main.async { [weak self, weak editor] in
                guard let self, let editor else { return }
                _ = self.mosaicRememberSelection(from: editor)
            }
            return event
        }
    }

    private func mosaicRemoveKeyMonitor() {
        if let mosaicKeyMonitor {
            NSEvent.removeMonitor(mosaicKeyMonitor)
            self.mosaicKeyMonitor = nil
        }
    }

    private func mosaicRestoreRememberedSelection() {
        guard let rememberedSelection = mosaicStoredFindSelection(for: mosaicSelectionOwner) ?? mosaicLastSelectedRange else { return }
        if let editor = currentEditor() as? NSTextView, !editor.hasMarkedText() {
            let selection = mosaicRememberSelection(rememberedSelection, in: editor.string)
            editor.setSelectedRange(selection)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let editor = self.currentEditor() as? NSTextView,
                  !editor.hasMarkedText() else { return }
            let selection = self.mosaicRememberSelection(rememberedSelection, in: editor.string)
            editor.setSelectedRange(selection)
        }
    }
}
