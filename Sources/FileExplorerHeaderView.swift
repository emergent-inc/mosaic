import AppKit
import MosaicAppKitSupportUI
import MosaicFoundation

/// 1px hairline matching the SwiftUI `rightSidebarChromeBottomBorder()`:
/// separator color derived from the current terminal chrome background so the
/// header bar reads as part of the same chrome stack as the Vault control bar.
final class FileExplorerChromeSeparatorView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLayer() {
        layer?.backgroundColor = WindowChromeColorResolver()
            .separatorColor(forChromeBackground: GhosttyBackgroundTheme.currentColor())
            .cgColor
    }

    func refreshSeparatorColor() {
        needsDisplay = true
    }
}

/// Pure AppKit header bar with folder icon, path label, and hidden files toggle.
final class FileExplorerHeaderView: NSView {
    private let iconView = NSImageView()
    private let pathLabel = NSTextField(labelWithString: "")
    private let bottomBorder = FileExplorerChromeSeparatorView()
    private var heightConstraint: NSLayoutConstraint?
    private var displayPath = ""
    private var quickSearchQuery: String?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentTintColor = FileExplorerAppearance.secondaryText

        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        applyFonts()
        pathLabel.textColor = FileExplorerAppearance.secondaryText
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.maximumNumberOfLines = 1
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(iconView)
        addSubview(pathLabel)

        bottomBorder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomBorder)

        let heightConstraint = heightAnchor.constraint(equalToConstant: RightSidebarChromeMetrics.secondaryBarHeight)
        self.heightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            heightConstraint,

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),

            pathLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4),
            pathLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            pathLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            bottomBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomBorder.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomBorder.heightAnchor.constraint(equalToConstant: 1),
        ])
        applyHeaderState()
    }

    /// Re-resolves the terminal-derived separator color (called when the
    /// ghostty default background changes).
    func refreshChromeColors() {
        bottomBorder.refreshSeparatorColor()
    }

    func applyFonts() {
        pathLabel.font = GlobalFontMagnification.systemFont(ofSize: 11, weight: .medium)
        heightConstraint?.constant = RightSidebarChromeMetrics.secondaryBarHeight
    }

    func update(displayPath: String) {
        guard self.displayPath != displayPath else { return }
        self.displayPath = displayPath
        applyHeaderState()
    }

    func updateQuickSearch(query: String?) {
        guard quickSearchQuery != query else { return }
        quickSearchQuery = query
        applyHeaderState()
    }

    private func applyHeaderState() {
        assert(Thread.isMainThread, "AppKit image updates must run on the main thread")
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        if let quickSearchQuery {
            iconView.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            pathLabel.stringValue = "/" + quickSearchQuery
            pathLabel.toolTip = pathLabel.stringValue
        } else {
            iconView.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            pathLabel.stringValue = displayPath
            pathLabel.toolTip = displayPath
        }
    }
}
