import AppKit
import CmuxCollaboration

@MainActor
final class CollaborationInviteCodeEntryView: NSView, NSTextFieldDelegate {
    private let hiddenField = NSTextField(string: "")
    private let stack = NSStackView()
    private let slotLabels: [NSTextField]
    private let caret = NSView()
    private var model = CollaborationInviteCodeEntryModel()

    /// Called whenever the entered code changes; receives the current completeness.
    var onChange: ((Bool) -> Void)?

    /// Called when the user presses Return while the entry has focus.
    var onSubmit: (() -> Void)?

    /// Called when the user presses Escape while the entry has focus.
    var onCancel: (() -> Void)?

    var code: String {
        model.value
    }

    var isComplete: Bool {
        model.isComplete
    }

    private static let slotSize = NSSize(width: 52, height: 56)
    private static let slotSpacing: CGFloat = 10

    init(accessibilityLabel: String) {
        self.slotLabels = (0..<CollaborationInviteCodeEntryModel.codeLength).map { _ in
            Self.makeSlotLabel()
        }
        let slotCount = CGFloat(CollaborationInviteCodeEntryModel.codeLength)
        let width = Self.slotSize.width * slotCount + Self.slotSpacing * (slotCount - 1)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.slotSize.height))
        setup(accessibilityLabel: accessibilityLabel)
    }

    override var intrinsicContentSize: NSSize {
        let slotCount = CGFloat(CollaborationInviteCodeEntryModel.codeLength)
        return NSSize(
            width: Self.slotSize.width * slotCount + Self.slotSpacing * (slotCount - 1),
            height: Self.slotSize.height
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private static func makeSlotLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.cell = CenteredCodeSlotCell(textCell: "")
        label.isBordered = false
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        return label
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        window?.makeFirstResponder(hiddenField)
        return true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(hiddenField)
        super.mouseDown(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusForTextEntry()
        refreshAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    override func layout() {
        super.layout()
        positionCaret()
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            onSubmit?()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onCancel?()
            return true
        default:
            return false
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        model.replace(with: hiddenField.stringValue)
        if hiddenField.stringValue != model.value {
            hiddenField.stringValue = model.value
            if let editor = hiddenField.currentEditor() {
                editor.selectedRange = NSRange(location: model.value.count, length: 0)
            }
        }
        updateSlots()
        onChange?(model.isComplete)
    }

    func focusForTextEntry() {
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            self.window?.makeFirstResponder(self.hiddenField)
        }
    }

    private func setup(accessibilityLabel: String) {
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(accessibilityLabel)

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .gravityAreas
        stack.spacing = Self.slotSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for label in slotLabels {
            label.alignment = .center
            label.font = .monospacedSystemFont(ofSize: 22, weight: .semibold)
            label.textColor = .labelColor
            label.wantsLayer = true
            label.layer?.cornerRadius = 12
            label.layer?.borderWidth = 1
            label.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(label)
            NSLayoutConstraint.activate([
                label.widthAnchor.constraint(equalToConstant: Self.slotSize.width),
                label.heightAnchor.constraint(equalToConstant: Self.slotSize.height),
            ])
        }

        caret.wantsLayer = true
        caret.layer?.cornerRadius = 1
        addSubview(caret)

        hiddenField.delegate = self
        hiddenField.isBordered = false
        hiddenField.focusRingType = .none
        hiddenField.backgroundColor = .clear
        hiddenField.textColor = .clear
        hiddenField.alphaValue = 0.01
        hiddenField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hiddenField)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            hiddenField.leadingAnchor.constraint(equalTo: leadingAnchor),
            hiddenField.topAnchor.constraint(equalTo: topAnchor),
            hiddenField.widthAnchor.constraint(equalToConstant: 1),
            hiddenField.heightAnchor.constraint(equalToConstant: 1),
        ])

        updateSlots()
    }

    /// The slot that receives the next typed character, or `nil` when the code is complete.
    private var activeSlotIndex: Int? {
        model.isComplete ? nil : model.value.count
    }

    private func updateSlots() {
        for (label, character) in zip(slotLabels, model.displayCharacters) {
            label.stringValue = character
        }
        setAccessibilityValue(model.value)
        refreshAppearance()
        positionCaret()
    }

    private func refreshAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            applySlotStyles()
            caret.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        }
    }

    private func applySlotStyles() {
        for (index, label) in slotLabels.enumerated() {
            guard let layer = label.layer else { continue }
            let isFilled = index < model.value.count
            if index == activeSlotIndex {
                layer.borderWidth = 1.5
                layer.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
                layer.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.35).cgColor
            } else if isFilled {
                layer.borderWidth = 1
                layer.borderColor = NSColor.separatorColor.cgColor
                layer.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.35).cgColor
            } else {
                layer.borderWidth = 1
                layer.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
                layer.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.15).cgColor
            }
        }
    }

    private func positionCaret() {
        guard let activeSlotIndex else {
            caret.isHidden = true
            caret.layer?.removeAnimation(forKey: Self.caretBlinkAnimationKey)
            return
        }
        let slot = slotLabels[activeSlotIndex]
        let slotFrame = slot.convert(slot.bounds, to: self)
        let caretHeight: CGFloat = 24
        caret.frame = NSRect(
            x: (slotFrame.midX - 1).rounded(),
            y: (slotFrame.midY - caretHeight / 2).rounded(),
            width: 2,
            height: caretHeight
        )
        caret.isHidden = false
        restartCaretBlink()
    }

    private static let caretBlinkAnimationKey = "cmux.inviteCode.caretBlink"

    private func restartCaretBlink() {
        guard let layer = caret.layer else { return }
        guard layer.animation(forKey: Self.caretBlinkAnimationKey) == nil else { return }
        let blink = CABasicAnimation(keyPath: "opacity")
        blink.fromValue = 1.0
        blink.toValue = 0.0
        blink.duration = 0.55
        blink.autoreverses = true
        blink.repeatCount = .infinity
        blink.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(blink, forKey: Self.caretBlinkAnimationKey)
    }
}

private final class CenteredCodeSlotCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var drawingRect = super.drawingRect(forBounds: rect)
        let textSize = cellSize(forBounds: rect)
        drawingRect.origin.y = rect.origin.y + floor((rect.height - textSize.height) / 2)
        drawingRect.size.height = textSize.height
        return drawingRect
    }
}
