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

// MARK: - Accent (yellow) control styles

/// A prominent button style that fills with the app's yellow accent color and
/// draws its label in black. The system default for accent/default-action
/// buttons uses white text, which is hard to read on the yellow accent — any
/// button whose primary background is the yellow accent should use this so the
/// text stays legible.
struct MosaicAccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

extension ButtonStyle where Self == MosaicAccentButtonStyle {
    /// Yellow-accent prominent button with black (not white) label text.
    static var mosaicAccent: MosaicAccentButtonStyle { MosaicAccentButtonStyle() }
}

/// A checkbox toggle style that fills the box with the yellow accent when on and
/// draws the checkmark in black, so the glyph stays legible on the yellow
/// primary background (the native `.checkbox` style uses a white checkmark).
struct MosaicAccentCheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(configuration.isOn ? Color.accentColor : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(
                                    configuration.isOn ? Color.clear : Color.primary.opacity(0.35),
                                    lineWidth: 1
                                )
                        )
                        .frame(width: 14, height: 14)
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.black)
                    }
                }
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension ToggleStyle where Self == MosaicAccentCheckboxToggleStyle {
    /// Yellow-accent checkbox with a black (not white) checkmark.
    static var mosaicAccentCheckbox: MosaicAccentCheckboxToggleStyle { MosaicAccentCheckboxToggleStyle() }
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
