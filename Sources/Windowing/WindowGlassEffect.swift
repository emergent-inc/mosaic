import AppKit
import ObjectiveC
import SwiftUI

/// Applies NSGlassEffectView (macOS 26+) to a window, falling back to NSVisualEffectView
enum WindowGlassEffect {
    enum Style: Equatable {
        case regular
        case clear

        fileprivate var rawNSGlassEffectViewStyle: Int {
            switch self {
            case .regular: return 0
            case .clear: return 1
            }
        }
    }

    static let backgroundViewIdentifier = NSUserInterfaceItemIdentifier("cmux.windowGlassBackground")
    static let rootViewIdentifier = NSUserInterfaceItemIdentifier("cmux.windowGlassRoot")
    static let foregroundContainerIdentifier = NSUserInterfaceItemIdentifier("cmux.windowGlassForeground")

    private final class OriginalContentLayoutState: NSObject {
        let translatesAutoresizingMaskIntoConstraints: Bool
        let autoresizingMask: NSView.AutoresizingMask

        init(view: NSView) {
            translatesAutoresizingMaskIntoConstraints = view.translatesAutoresizingMaskIntoConstraints
            autoresizingMask = view.autoresizingMask
        }

        func restore(to view: NSView) {
            view.translatesAutoresizingMaskIntoConstraints = translatesAutoresizingMaskIntoConstraints
            view.autoresizingMask = autoresizingMask
        }
    }

    private final class GlassBackgroundView: NSView {
        private let effectView: NSView
        private let tintOverlay: NSView
        private let usesNativeGlass: Bool
        private var effectTopConstraint: NSLayoutConstraint!

        init(
            frame: NSRect,
            topOffset: CGFloat,
            tintColor: NSColor?,
            style: Style?,
            cornerRadius: CGFloat?,
            isKeyWindow: Bool
        ) {
            if let glassClass = NSClassFromString("NSGlassEffectView") as? NSView.Type {
                effectView = glassClass.init(frame: .zero)
                usesNativeGlass = true
            } else {
                let fallbackView = NSVisualEffectView(frame: .zero)
                fallbackView.blendingMode = .behindWindow
                fallbackView.material = .underWindowBackground
                fallbackView.state = .active
                effectView = fallbackView
                usesNativeGlass = false
            }
            tintOverlay = NSView(frame: .zero)

            super.init(frame: frame)

            identifier = WindowGlassEffect.backgroundViewIdentifier
            translatesAutoresizingMaskIntoConstraints = false
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.isOpaque = false

            effectView.translatesAutoresizingMaskIntoConstraints = false
            effectView.wantsLayer = true
            addSubview(effectView)
            effectTopConstraint = effectView.topAnchor.constraint(equalTo: topAnchor, constant: topOffset)
            NSLayoutConstraint.activate([
                effectTopConstraint,
                effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
                effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
                effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])

            tintOverlay.translatesAutoresizingMaskIntoConstraints = false
            tintOverlay.wantsLayer = true
            tintOverlay.alphaValue = 0
            addSubview(tintOverlay, positioned: .above, relativeTo: effectView)
            NSLayoutConstraint.activate([
                tintOverlay.topAnchor.constraint(equalTo: effectView.topAnchor),
                tintOverlay.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
                tintOverlay.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
                tintOverlay.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            ])

            configure(
                tintColor: tintColor,
                style: style,
                cornerRadius: cornerRadius,
                isKeyWindow: isKeyWindow
            )
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func updateTopOffset(_ offset: CGFloat) {
            effectTopConstraint.constant = offset
        }

        func configure(
            tintColor: NSColor?,
            style: Style?,
            cornerRadius: CGFloat?,
            isKeyWindow: Bool
        ) {
            effectView.layer?.cornerRadius = cornerRadius ?? 0
            if usesNativeGlass {
                updateNativeGlassConfiguration(
                    on: effectView,
                    color: tintColor,
                    style: style,
                    cornerRadius: cornerRadius
                )
                updateInactiveTintOverlay(tintColor: tintColor, isKeyWindow: isKeyWindow)
            } else if let tintColor {
                effectView.layer?.masksToBounds = cornerRadius != nil
                tintOverlay.layer?.backgroundColor = tintColor.cgColor
                tintOverlay.alphaValue = 1
            } else {
                effectView.layer?.masksToBounds = cornerRadius != nil
                tintOverlay.layer?.backgroundColor = nil
                tintOverlay.alphaValue = 0
            }
        }

        private func updateInactiveTintOverlay(tintColor: NSColor?, isKeyWindow: Bool) {
            guard let tintColor else {
                tintOverlay.layer?.backgroundColor = nil
                tintOverlay.alphaValue = 0
                return
            }

            tintOverlay.layer?.backgroundColor = tintColor.adjustingSaturation(by: 1.2).cgColor
            tintOverlay.alphaValue = isKeyWindow ? 0 : (tintColor.isLightColor ? 0.35 : 0.85)
        }
    }

    private final class GlassRootView: NSView {
        let foregroundContainer = NSView(frame: .zero)
        weak var originalContentView: NSView?

        private let backgroundView: GlassBackgroundView

        override var isOpaque: Bool { false }

        init(
            frame: NSRect,
            topOffset: CGFloat,
            tintColor: NSColor?,
            style: Style?,
            cornerRadius: CGFloat?,
            isKeyWindow: Bool
        ) {
            backgroundView = GlassBackgroundView(
                frame: frame,
                topOffset: topOffset,
                tintColor: tintColor,
                style: style,
                cornerRadius: cornerRadius,
                isKeyWindow: isKeyWindow
            )

            super.init(frame: frame)

            identifier = WindowGlassEffect.rootViewIdentifier
            autoresizingMask = [.width, .height]
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.isOpaque = false

            backgroundView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(backgroundView)

            foregroundContainer.identifier = WindowGlassEffect.foregroundContainerIdentifier
            foregroundContainer.frame = bounds
            foregroundContainer.translatesAutoresizingMaskIntoConstraints = false
            foregroundContainer.wantsLayer = true
            foregroundContainer.layer?.backgroundColor = NSColor.clear.cgColor
            foregroundContainer.layer?.isOpaque = false
            addSubview(foregroundContainer, positioned: .above, relativeTo: backgroundView)

            NSLayoutConstraint.activate([
                backgroundView.topAnchor.constraint(equalTo: topAnchor),
                backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
                backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
                backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),

                foregroundContainer.topAnchor.constraint(equalTo: topAnchor),
                foregroundContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
                foregroundContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
                foregroundContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func attachOriginalContentView(_ contentView: NSView) {
            originalContentView = contentView
            contentView.removeFromSuperview()
            contentView.frame = foregroundContainer.bounds
            contentView.translatesAutoresizingMaskIntoConstraints = true
            contentView.autoresizingMask = [.width, .height]
            foregroundContainer.addSubview(contentView, positioned: .below, relativeTo: nil)
        }

        func configure(
            topOffset: CGFloat,
            tintColor: NSColor?,
            style: Style?,
            cornerRadius: CGFloat?,
            isKeyWindow: Bool
        ) {
            backgroundView.updateTopOffset(topOffset)
            backgroundView.configure(
                tintColor: tintColor,
                style: style,
                cornerRadius: cornerRadius,
                isKeyWindow: isKeyWindow
            )
        }
    }

    private static var glassRootViewKey: UInt8 = 0
    private static var originalContentViewKey: UInt8 = 0
    private static var originalContentLayoutStateKey: UInt8 = 0

    static var isAvailable: Bool {
        NSClassFromString("NSGlassEffectView") != nil
    }

    @discardableResult
    static func apply(to window: NSWindow, tintColor: NSColor? = nil, style: Style? = nil) -> Bool {
        guard let currentContentView = window.contentView else { return false }
        let topOffset = glassTopOffset(for: window, contentView: currentContentView)
        let cornerRadius = windowCornerRadius(for: window)

        if let rootView = activeRootView(for: window) {
            rootView.configure(
                topOffset: topOffset,
                tintColor: tintColor,
                style: style,
                cornerRadius: cornerRadius,
                isKeyWindow: window.isKeyWindow
            )
            return false
        }

        let originalContentView = currentContentView
        let layoutState = OriginalContentLayoutState(view: originalContentView)
        let rootView = GlassRootView(
            frame: originalContentView.frame,
            topOffset: topOffset,
            tintColor: tintColor,
            style: style,
            cornerRadius: cornerRadius,
            isKeyWindow: window.isKeyWindow
        )
        window.contentView = rootView
        rootView.attachOriginalContentView(originalContentView)

        objc_setAssociatedObject(window, &glassRootViewKey, rootView, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(window, &originalContentViewKey, originalContentView, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(window, &originalContentLayoutStateKey, layoutState, .OBJC_ASSOCIATION_RETAIN)
        return true
    }

    /// Update the tint color on an existing glass effect
    static func updateTint(to window: NSWindow, color: NSColor?) {
        guard let rootView = activeRootView(for: window) else { return }
        rootView.configure(
            topOffset: glassTopOffset(for: window, contentView: window.contentView),
            tintColor: color,
            style: nil,
            cornerRadius: windowCornerRadius(for: window),
            isKeyWindow: window.isKeyWindow
        )
    }

    private static func updateNativeGlassConfiguration(
        on glassView: NSView,
        color: NSColor?,
        style: Style?,
        cornerRadius: CGFloat?
    ) {
        let tintSelector = NSSelectorFromString("setTintColor:")
        if glassView.responds(to: tintSelector) {
            glassView.perform(tintSelector, with: color)
        }

        if let cornerRadius {
            let cornerRadiusSelector = NSSelectorFromString("setCornerRadius:")
            if glassView.responds(to: cornerRadiusSelector) {
                typealias CornerRadiusSetter = @convention(c) (AnyObject, Selector, CGFloat) -> Void
                let implementation = glassView.method(for: cornerRadiusSelector)
                let setter = unsafeBitCast(implementation, to: CornerRadiusSetter.self)
                setter(glassView, cornerRadiusSelector, cornerRadius)
            }
        }

        if let style {
            let styleSelector = NSSelectorFromString("setStyle:")
            guard glassView.responds(to: styleSelector) else { return }
            typealias StyleSetter = @convention(c) (AnyObject, Selector, Int) -> Void
            let implementation = glassView.method(for: styleSelector)
            let setter = unsafeBitCast(implementation, to: StyleSetter.self)
            setter(glassView, styleSelector, style.rawNSGlassEffectViewStyle)
        }
    }

    static func foregroundContainer(for window: NSWindow) -> NSView? {
        activeRootView(for: window)?.foregroundContainer
    }

    static func originalContentView(for window: NSWindow) -> NSView? {
        if let rootView = activeRootView(for: window),
           let originalContentView = rootView.originalContentView {
            return originalContentView
        }
        return objc_getAssociatedObject(window, &originalContentViewKey) as? NSView
    }

    static func portalInstallationTarget(for window: NSWindow) -> (container: NSView, reference: NSView)? {
        guard let rootView = activeRootView(for: window),
              let originalContentView = originalContentView(for: window),
              originalContentView.superview === rootView.foregroundContainer else {
            return nil
        }
        return (rootView.foregroundContainer, originalContentView)
    }

    private static func activeRootView(for window: NSWindow) -> GlassRootView? {
        if let rootView = window.contentView as? GlassRootView {
            return rootView
        }
        guard let rootView = objc_getAssociatedObject(window, &glassRootViewKey) as? GlassRootView,
              window.contentView === rootView else {
            return nil
        }
        return rootView
    }

    private static func glassTopOffset(for window: NSWindow, contentView: NSView?) -> CGFloat {
        guard let themeFrame = contentView?.superview ?? window.contentView?.superview else {
            return 0
        }
        return -max(0, themeFrame.safeAreaInsets.top)
    }

    private static func windowCornerRadius(for window: NSWindow) -> CGFloat? {
        guard window.responds(to: Selector(("_cornerRadius"))) else {
            return nil
        }
        return window.value(forKey: "_cornerRadius") as? CGFloat
    }

    @discardableResult
    static func remove(from window: NSWindow) -> Bool {
        guard let rootView = activeRootView(for: window) else {
            return false
        }

        if let originalContentView = originalContentView(for: window) {
            originalContentView.removeFromSuperview()
            originalContentView.frame = rootView.bounds
            if let layoutState = objc_getAssociatedObject(
                window,
                &originalContentLayoutStateKey
            ) as? OriginalContentLayoutState {
                layoutState.restore(to: originalContentView)
            }
            window.contentView = originalContentView
        }

        objc_setAssociatedObject(window, &glassRootViewKey, nil, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(window, &originalContentViewKey, nil, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(window, &originalContentLayoutStateKey, nil, .OBJC_ASSOCIATION_RETAIN)
        return true
    }
}

private extension NSColor {
    func adjustingSaturation(by factor: CGFloat) -> NSColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        let color = usingColorSpace(.sRGB) ?? self
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(
            hue: hue,
            saturation: min(max(saturation * factor, 0), 1),
            brightness: brightness,
            alpha: alpha
        )
    }
}
