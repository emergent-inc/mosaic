public import AppKit
import MosaicFoundation

/// Shared AppKit foreground and button styling for mosaic macOS surfaces.
public enum MosaicAppKitTheme {
    public static let textColor = NSColor.white
    public static let buttonBackgroundHex = "#2170FF"
    public static let buttonBackgroundColor = NSColor(hex: buttonBackgroundHex) ?? .systemBlue

    public static func applyTextStyle(to textField: NSTextField) {
        guard !shouldPreserveExistingTextColor(textField.textColor) else { return }
        textField.textColor = textColor
    }

    public static func applyTextStyle(to textView: NSTextView) {
        guard !shouldPreserveExistingTextColor(textView.textColor) else { return }
        textView.textColor = textColor
    }

    public static func applyTextStyle(to popupButton: NSPopUpButton) {
        for item in popupButton.itemArray {
            let title = item.title
            item.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.foregroundColor: textColor]
            )
        }
    }

    public static func applyTextStyle(to secureTextField: NSSecureTextField) {
        applyTextStyle(to: secureTextField as NSTextField)
    }

    public static func applyButtonStyle(to button: NSButton) {
        if !button.isBordered || button.isTransparent {
            button.isBordered = true
            button.isTransparent = false
        }

        button.bezelColor = buttonBackgroundColor
        button.contentTintColor = textColor

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = button.alignment
        let resolvedFont = button.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let title = NSAttributedString(
            string: button.title,
            attributes: [
                .foregroundColor: textColor,
                .paragraphStyle: paragraph,
                .font: resolvedFont,
            ]
        )
        button.font = resolvedFont
        button.attributedTitle = title
        button.attributedAlternateTitle = title
        if let cell = button.cell as? NSButtonCell {
            cell.attributedTitle = title
            cell.attributedAlternateTitle = title
        }
    }

    public static func applyRecursively(to view: NSView) {
        if let popupButton = view as? NSPopUpButton {
            applyTextStyle(to: popupButton)
            applyButtonStyle(to: popupButton)
        } else if let secureTextField = view as? NSSecureTextField {
            applyTextStyle(to: secureTextField)
        } else if let textField = view as? NSTextField, !(view is NSButton) {
            applyTextStyle(to: textField)
        } else if let textView = view as? NSTextView {
            applyTextStyle(to: textView)
        } else if let button = view as? NSButton {
            applyButtonStyle(to: button)
        }

        for subview in view.subviews {
            applyRecursively(to: subview)
        }
    }

    private static func shouldPreserveExistingTextColor(_ color: NSColor?) -> Bool {
        guard let color else { return false }
        return color == .clear
    }
}
