import SwiftUI

/// Drop-in replacement for `Button` that emits generic click-count analytics.
struct TrackedButton<Label: View>: View {
    let name: String
    let properties: [String: Any]
    let role: ButtonRole?
    let action: () -> Void
    let label: () -> Label

    init(
        _ name: String,
        properties: [String: Any] = [:],
        role: ButtonRole? = nil,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.name = name
        self.properties = properties
        self.role = role
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(role: role, action: {
            PostHogAnalytics.shared.trackButtonTap(buttonName: name, properties: properties)
            action()
        }, label: label)
    }
}

extension TrackedButton where Label == Text {
    init<S: StringProtocol>(
        _ name: String,
        _ title: S,
        properties: [String: Any] = [:],
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.init(name, properties: properties, role: role, action: action) {
            Text(String(title))
        }
    }

    init(
        _ name: String,
        _ titleKey: LocalizedStringKey,
        properties: [String: Any] = [:],
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.init(name, properties: properties, role: role, action: action) {
            Text(titleKey)
        }
    }
}
