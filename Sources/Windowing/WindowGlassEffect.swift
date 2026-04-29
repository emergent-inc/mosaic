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

    private static var glassViewKey: UInt8 = 0
    private static var originalContentViewKey: UInt8 = 0

    static var isAvailable: Bool {
        NSClassFromString("NSGlassEffectView") != nil
    }

    static func apply(to window: NSWindow, tintColor: NSColor? = nil, style: Style? = nil) {
        guard let originalContentView = window.contentView else { return }
        let target = installationTarget(for: originalContentView)
        let topOffset = glassTopOffset(for: window, contentView: originalContentView)
        let cornerRadius = windowCornerRadius(for: window)

        // Check if we already applied glass (avoid re-wrapping)
        if let existingGlass = objc_getAssociatedObject(window, &glassViewKey) as? GlassBackgroundView {
            if existingGlass.superview === target.container {
                existingGlass.updateTopOffset(topOffset)
                existingGlass.configure(
                    tintColor: tintColor,
                    style: style,
                    cornerRadius: cornerRadius,
                    isKeyWindow: window.isKeyWindow
                )
                return
            }
            existingGlass.removeFromSuperview()
        }

        if let staleGlass = objc_getAssociatedObject(window, &glassViewKey) as? NSView {
            staleGlass.removeFromSuperview()
        }

        let glassView = GlassBackgroundView(
            frame: target.reference.bounds,
            topOffset: topOffset,
            tintColor: tintColor,
            style: style,
            cornerRadius: cornerRadius,
            isKeyWindow: window.isKeyWindow
        )
        if target.container === target.reference {
            target.container.addSubview(glassView, positioned: .below, relativeTo: nil)
        } else {
            target.container.addSubview(glassView, positioned: .below, relativeTo: target.reference)
        }
        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: target.reference.topAnchor),
            glassView.bottomAnchor.constraint(equalTo: target.reference.bottomAnchor),
            glassView.leadingAnchor.constraint(equalTo: target.reference.leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: target.reference.trailingAnchor)
        ])

        // Store reference
        objc_setAssociatedObject(window, &glassViewKey, glassView, .OBJC_ASSOCIATION_RETAIN)
    }

    /// Update the tint color on an existing glass effect
    static func updateTint(to window: NSWindow, color: NSColor?) {
        guard let glassView = objc_getAssociatedObject(window, &glassViewKey) as? GlassBackgroundView else { return }
        glassView.updateTopOffset(glassTopOffset(for: window, contentView: window.contentView))
        glassView.configure(
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

    private static func installationTarget(for contentView: NSView) -> (container: NSView, reference: NSView) {
        guard let themeFrame = contentView.superview else {
            return (contentView, contentView)
        }
        return (themeFrame, contentView)
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

    static func remove(from window: NSWindow) {
        guard let glassView = objc_getAssociatedObject(window, &glassViewKey) as? NSView else {
            return
        }

        if glassView.className == "NSGlassEffectView",
           window.contentView === glassView {
            if let originalContentView = objc_getAssociatedObject(window, &originalContentViewKey) as? NSView {
                originalContentView.removeFromSuperview()
                originalContentView.translatesAutoresizingMaskIntoConstraints = true
                originalContentView.autoresizingMask = [.width, .height]
                originalContentView.frame = glassView.bounds
                window.contentView = originalContentView
            }
        } else {
            glassView.removeFromSuperview()
        }

        objc_setAssociatedObject(window, &glassViewKey, nil, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(window, &originalContentViewKey, nil, .OBJC_ASSOCIATION_RETAIN)
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
