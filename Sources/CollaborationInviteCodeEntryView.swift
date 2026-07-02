import AppKit
import CmuxCollaboration

@MainActor
final class CollaborationInviteCodeEntryView: NSView, NSTextFieldDelegate {
    private let hiddenField = NSTextField(string: "")
    private let stack = NSStackView()
    private let slotLabels: [NSTextField]
    private var model = CollaborationInviteCodeEntryModel()

    var code: String {
        model.value
    }

    var isComplete: Bool {
        model.isComplete
    }

    init(accessibilityLabel: String) {
        self.slotLabels = (0..<CollaborationInviteCodeEntryModel.codeLength).map { _ in
            NSTextField(labelWithString: "")
        }
        super.init(frame: NSRect(x: 0, y: 0, width: 228, height: 44))
        setup(accessibilityLabel: accessibilityLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
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
        window?.makeFirstResponder(hiddenField)
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
    }

    private func setup(accessibilityLabel: String) {
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(accessibilityLabel)

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fillEqually
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for label in slotLabels {
            label.alignment = .center
            label.font = .monospacedSystemFont(ofSize: 18, weight: .semibold)
            label.textColor = .labelColor
            label.wantsLayer = true
            label.layer?.cornerRadius = 9
            label.layer?.borderWidth = 1
            label.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
            label.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.28).cgColor
            label.translatesAutoresizingMaskIntoConstraints = false
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            stack.addArrangedSubview(label)
            NSLayoutConstraint.activate([
                label.widthAnchor.constraint(equalToConstant: 45),
                label.heightAnchor.constraint(equalToConstant: 40),
            ])
        }

        hiddenField.delegate = self
        hiddenField.isBordered = false
        hiddenField.focusRingType = .none
        hiddenField.backgroundColor = .clear
        hiddenField.textColor = .clear
        hiddenField.alphaValue = 0.01
        hiddenField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hiddenField)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            hiddenField.leadingAnchor.constraint(equalTo: leadingAnchor),
            hiddenField.topAnchor.constraint(equalTo: topAnchor),
            hiddenField.widthAnchor.constraint(equalToConstant: 1),
            hiddenField.heightAnchor.constraint(equalToConstant: 1),
        ])

        updateSlots()
    }

    private func updateSlots() {
        for (label, character) in zip(slotLabels, model.displayCharacters) {
            label.stringValue = character
        }
    }
}
