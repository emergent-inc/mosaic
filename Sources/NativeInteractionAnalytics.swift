import AppKit
import Foundation

@MainActor
final class NativeInteractionAnalytics {
    static let shared = NativeInteractionAnalytics()

    private var eventMonitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var isInstalled = false

    private init() {}

    func installIfNeeded() {
        guard !isInstalled else { return }
        guard TelemetrySettings.enabledForCurrentLaunch else { return }
        guard ProcessInfo.processInfo.environment["CMUX_POSTHOG_NATIVE_INTERACTIONS"] != "0" else { return }

        isInstalled = true
        installEventMonitors()
        installNotificationObservers()
    }

    private func installEventMonitors() {
        let mouseMask: NSEvent.EventTypeMask = [
            .leftMouseDown,
            .leftMouseUp,
            .rightMouseDown,
            .otherMouseDown,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .scrollWheel,
        ]
        let mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseMask) { [weak self] event in
            self?.track(event)
            return event
        }
        if let mouseMonitor {
            eventMonitors.append(mouseMonitor)
        }
    }

    private func installNotificationObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSMenu.didSendActionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.trackMenuAction(notification)
            }
        })
        observers.append(center.addObserver(
            forName: NSControl.textDidBeginEditingNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.trackTextEditing(notification, phase: "begin")
            }
        })
        observers.append(center.addObserver(
            forName: NSControl.textDidEndEditingNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.trackTextEditing(notification, phase: "end")
            }
        })
        observers.append(center.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.trackWindowFocus(notification, phase: "become_key")
            }
        })
        observers.append(center.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.trackWindowFocus(notification, phase: "resign_key")
            }
        })
    }

    private func track(_ event: NSEvent) {
        guard let properties = Self.properties(for: event) else { return }
        PostHogAnalytics.shared.capture(.uiInteraction, properties: properties)
        if let buttonProperties = Self.buttonTapProperties(for: event) {
            PostHogAnalytics.shared.capture("button_tapped", properties: buttonProperties)
        }
    }

    private func trackMenuAction(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        var properties: [String: Any] = [
            "interaction_type": "menu_action",
            "surface": "menu",
            "view_class": Self.safeClassName(menu),
        ]
        if let item = menu.highlightedItem {
            if let identifier = item.identifier?.rawValue, !identifier.isEmpty {
                properties["control_id"] = "menu.\(identifier)"
            } else if let action = item.action {
                properties["control_id"] = "menu.action.\(NSStringFromSelector(action))"
                properties["action_id"] = NSStringFromSelector(action)
            }
            properties["is_enabled"] = item.isEnabled
        }
        PostHogAnalytics.shared.capture(.uiInteraction, properties: properties)
        if let buttonProperties = Self.menuButtonTapProperties(from: menu) {
            PostHogAnalytics.shared.trackButtonTap(
                buttonName: buttonProperties.buttonName,
                properties: buttonProperties.properties
            )
        }
    }

    private func trackTextEditing(_ notification: Notification, phase: String) {
        guard let control = notification.object as? NSControl else { return }
        var properties = Self.viewProperties(for: control)
        properties["interaction_type"] = "text_editing"
        properties["phase"] = phase
        PostHogAnalytics.shared.capture(.uiInteraction, properties: properties)
    }

    private func trackWindowFocus(_ notification: Notification, phase: String) {
        guard let window = notification.object as? NSWindow else { return }
        var properties: [String: Any] = [
            "interaction_type": "window_focus",
            "phase": phase,
            "surface": Self.surfaceName(for: window.contentView),
            "view_class": Self.safeClassName(window.contentView),
            "window_class": Self.safeClassName(window),
            "window_level": Int(window.level.rawValue),
        ]
        PostHogAnalytics.shared.capture(.uiInteraction, properties: properties)
    }

    nonisolated static func properties(for event: NSEvent) -> [String: Any]? {
        guard let window = event.window else { return nil }

        var view: NSView?
        if let contentView = window.contentView {
            let point = contentView.convert(event.locationInWindow, from: nil)
            view = contentView.hitTest(point)
        }

        var properties = viewProperties(for: view)
        properties["interaction_type"] = interactionType(for: event.type)
        properties["event_type"] = eventTypeName(event.type)
        properties["button_number"] = event.buttonNumber
        properties["click_count"] = event.clickCount
        properties["modifier_flags"] = Int(event.modifierFlags.rawValue)
        properties["window_class"] = safeClassName(window)
        properties["window_level"] = Int(window.level.rawValue)

        if event.type == .scrollWheel {
            properties["scroll_x"] = Self.scrollDirection(event.scrollingDeltaX)
            properties["scroll_y"] = Self.scrollDirection(event.scrollingDeltaY)
            properties["has_precise_scrolling"] = event.hasPreciseScrollingDeltas
        }

        return properties
    }

    nonisolated static func buttonTapProperties(for event: NSEvent) -> [String: Any]? {
        guard event.type == .leftMouseUp, let window = event.window else { return nil }
        guard let view = viewHitBy(event, in: window) else { return nil }
        guard let buttonContext = nearestButtonContext(from: view) else { return nil }
        var properties = viewProperties(for: view)
        properties["button_name"] = buttonContext.name
        properties["is_enabled"] = buttonContext.isEnabled
        return properties
    }

    nonisolated static func viewProperties(for view: NSView?) -> [String: Any] {
        var properties: [String: Any] = [
            "surface": surfaceName(for: view),
        ]
        guard let view else {
            properties["view_class"] = "none"
            return properties
        }

        properties["view_class"] = safeClassName(view)
        if let role = view.accessibilityRole()?.rawValue, !role.isEmpty {
            properties["accessibility_role"] = role
        }
        if let control = nearestControl(from: view) {
            properties["control_class"] = safeClassName(control)
            properties["is_enabled"] = control.isEnabled
        }
        if let identifier = nearestAccessibilityIdentifier(from: view) {
            properties["control_id"] = identifier
        }
        return properties
    }

    nonisolated private static func viewHitBy(_ event: NSEvent, in window: NSWindow) -> NSView? {
        guard let contentView = window.contentView else { return nil }
        let point = contentView.convert(event.locationInWindow, from: nil)
        return contentView.hitTest(point)
    }

    nonisolated private static func nearestButtonContext(from view: NSView?) -> (name: String, isEnabled: Bool)? {
        var current = view
        var depth = 0
        while let candidate = current, depth < 10 {
            if let control = candidate as? NSControl,
               isButtonLike(control) {
                return (buttonName(for: control), control.isEnabled)
            }
            if let role = candidate.accessibilityRole()?.rawValue,
               role.localizedCaseInsensitiveContains("button") {
                return (buttonName(for: candidate), true)
            }
            current = candidate.superview
            depth += 1
        }
        return nil
    }

    nonisolated private static func isButtonLike(_ control: NSControl) -> Bool {
        if control is NSButton { return true }
        let className = safeClassName(control).lowercased()
        return className.contains("button")
    }

    nonisolated private static func buttonName(for view: NSView) -> String {
        if let identifier = nearestAccessibilityIdentifier(from: view) {
            return snakeCase(identifier)
        }
        if let control = view as? NSControl, let action = control.action {
            return snakeCase(NSStringFromSelector(action))
        }
        return snakeCase(safeClassName(view))
    }

    nonisolated private static func menuButtonTapProperties(
        from menu: NSMenu
    ) -> (buttonName: String, properties: [String: Any])? {
        guard let item = menu.highlightedItem else { return nil }
        var properties: [String: Any] = [
            "surface": "menu",
            "interaction_type": "menu_action",
            "view_class": safeClassName(menu),
            "is_enabled": item.isEnabled,
        ]
        if let identifier = item.identifier?.rawValue, !identifier.isEmpty {
            properties["control_id"] = "menu.\(identifier)"
            return (snakeCase(identifier), properties)
        }
        if let action = item.action {
            let actionID = NSStringFromSelector(action)
            properties["action_id"] = actionID
            properties["control_id"] = "menu.action.\(actionID)"
            return (snakeCase(actionID), properties)
        }
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return ("menu_item", properties) }
        properties["menu_title_length"] = title.count
        return (snakeCase(title), properties)
    }

    nonisolated static func nearestAccessibilityIdentifier(from view: NSView?) -> String? {
        var current = view
        var depth = 0
        while let candidate = current, depth < 10 {
            let identifier = candidate.accessibilityIdentifier()
            if !identifier.isEmpty {
                return Self.sanitizedIdentifier(identifier)
            }
            current = candidate.superview
            depth += 1
        }
        return nil
    }

    nonisolated static func nearestControl(from view: NSView?) -> NSControl? {
        var current = view
        var depth = 0
        while let candidate = current, depth < 10 {
            if let control = candidate as? NSControl {
                return control
            }
            current = candidate.superview
            depth += 1
        }
        return nil
    }

    nonisolated static func surfaceName(for view: NSView?) -> String {
        var current = view
        var depth = 0
        while let candidate = current, depth < 12 {
            let className = safeClassName(candidate).lowercased()
            let identifier = candidate.accessibilityIdentifier().lowercased()
            if className.contains("terminal") || identifier.contains("terminal") {
                return "terminal"
            }
            if className.contains("sidebar") || identifier.contains("sidebar") {
                return "sidebar"
            }
            if className.contains("browser") || identifier.contains("browser") {
                return "browser"
            }
            if className.contains("commandpalette") || identifier.contains("commandpalette") {
                return "command_palette"
            }
            if className.contains("settings") || identifier.contains("settings") {
                return "settings"
            }
            current = candidate.superview
            depth += 1
        }
        return "app"
    }

    nonisolated static func interactionType(for eventType: NSEvent.EventType) -> String {
        switch eventType {
        case .leftMouseDown:
            "click"
        case .rightMouseDown:
            "right_click"
        case .otherMouseDown:
            "other_click"
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            "drag"
        case .scrollWheel:
            "scroll"
        default:
            "other"
        }
    }

    nonisolated static func eventTypeName(_ eventType: NSEvent.EventType) -> String {
        switch eventType {
        case .leftMouseDown:
            "left_mouse_down"
        case .leftMouseUp:
            "left_mouse_up"
        case .rightMouseDown:
            "right_mouse_down"
        case .otherMouseDown:
            "other_mouse_down"
        case .leftMouseDragged:
            "left_mouse_dragged"
        case .rightMouseDragged:
            "right_mouse_dragged"
        case .otherMouseDragged:
            "other_mouse_dragged"
        case .scrollWheel:
            "scroll_wheel"
        default:
            "other"
        }
    }

    nonisolated static func scrollDirection(_ value: CGFloat) -> String {
        if value > 0 { return "positive" }
        if value < 0 { return "negative" }
        return "none"
    }

    nonisolated static func safeClassName(_ object: Any?) -> String {
        guard let object else { return "none" }
        return String(describing: type(of: object))
            .prefix(80)
            .filter { character in
                character.isLetter || character.isNumber || character == "_" || character == "."
            }
            .map(String.init)
            .joined()
    }

    nonisolated static func sanitizedIdentifier(_ identifier: String) -> String {
        let allowed = identifier.prefix(120).filter { character in
            character.isLetter || character.isNumber || character == "_" || character == "." || character == "-"
        }
        let output = String(allowed)
        return output.isEmpty ? "unknown" : output
    }

    nonisolated private static func snakeCase(_ value: String) -> String {
        let scalars = value.unicodeScalars
        var output = ""
        var previousWasSeparator = true
        for scalar in scalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                let string = String(scalar)
                if scalar.properties.isUppercase, !previousWasSeparator, !output.hasSuffix("_") {
                    output.append("_")
                }
                output.append(string.lowercased())
                previousWasSeparator = false
            } else if !previousWasSeparator {
                output.append("_")
                previousWasSeparator = true
            }
            if output.count >= 96 { break }
        }
        let trimmed = output.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return trimmed.isEmpty ? "unknown_button" : trimmed
    }
}
