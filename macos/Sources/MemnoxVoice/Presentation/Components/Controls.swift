import SwiftUI

/// The measures Vorssaint's controls share: every button, select and field is one capsule height, in body text.
enum ControlMetrics {
    static let height: CGFloat = 28
    static let horizontalPadding: CGFloat = 14
    static let textSize: CGFloat = 13
    static let symbolSize: CGFloat = 9
    static let iconSpacing: CGFloat = 6
    /// A control that cannot be used yet keeps a faint fill, so its place on the row still shows.
    static let disabledFill = 0.5
    static let checkboxSide: CGFloat = 14
    static let checkboxRadius: CGFloat = 4
    static let checkSymbol: CGFloat = 9
    static let keySpacing: CGFloat = 3
    static let fieldPadding: CGFloat = 5
}

/// A select's face: the choice and the up and down chevrons on a grey capsule, as Vorssaint's language menu. In the
/// Memnox window it is the console's select: a bordered field at radius 6 with one chevron down.
struct SelectFace: View {
    let text: String
    var maximumWidth: CGFloat = .infinity
    @State private var hovering = false
    @Environment(\.look) private var look

    private static let chevrons = "chevron.up.chevron.down"
    private static let chevron = "chevron.down"
    private static let consolePadding: CGFloat = 12
    /// The pointer's light over the capsule, half the row's own, since the capsule already stands out.
    private static let hoverWash = 0.5

    var body: some View {
        if look == .console { console } else { mac }
    }

    private var console: some View {
        let shape = RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous)
        return HStack(spacing: Memnox.Spacing.medium) {
            Text(text)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
                .foregroundStyle(Memnox.Console.foreground)
                .lineLimit(1)
            Image(systemName: Self.chevron)
                .font(.system(size: Memnox.TextSize.caption, weight: .medium))
                .foregroundStyle(Memnox.Console.muted)
        }
        .padding(.horizontal, Self.consolePadding)
        .frame(height: Memnox.Console.controlHeight)
        .frame(maxWidth: maximumWidth)
        .fixedSize(horizontal: maximumWidth == .infinity, vertical: false)
        .background(shape.fill(hovering ? Memnox.Console.hover : Memnox.Console.field))
        .overlay(shape.strokeBorder(Memnox.Console.controlEdge, lineWidth: Memnox.Stroke.hairline))
        .contentShape(shape)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: Memnox.Motion.quick), value: hovering)
    }

    private var mac: some View {
        HStack(spacing: ControlMetrics.iconSpacing) {
            Text(text)
                .font(.system(size: ControlMetrics.textSize))
                .foregroundStyle(Memnox.Palette.foreground)
                .lineLimit(1)
            Image(systemName: Self.chevrons)
                .font(.system(size: ControlMetrics.symbolSize, weight: .semibold))
                .foregroundStyle(Memnox.Palette.muted)
        }
        .padding(.horizontal, ControlMetrics.horizontalPadding)
        .frame(height: ControlMetrics.height)
        .frame(maxWidth: maximumWidth)
        .fixedSize(horizontal: maximumWidth == .infinity, vertical: false)
        .background(Memnox.Palette.secondary, in: Capsule())
        .overlay(Capsule().strokeBorder(Memnox.Palette.controlEdge, lineWidth: Memnox.Stroke.hairline))
        .overlay(Capsule().fill(Memnox.Palette.hover.opacity(hovering ? Self.hoverWash : 0)).allowsHitTesting(false))
        .contentShape(Capsule())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: Memnox.Motion.quick), value: hovering)
    }
}

/// A select over a set of values, as Vorssaint picks one in a row.
struct SelectMenu<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button(option.label) { selection = option.value }
            }
        } label: {
            SelectFace(text: options.first { $0.value == selection }?.label ?? "")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .pointingHand()
    }
}

/// The app's one text field: a symbol and the words on a grey capsule, as Vorssaint's sidebar search. A magnifier by
/// default; given `submit`, Return sends what is typed, as the reply to a session in the notch does. In the Memnox window
/// it is the console's search: a bordered field at radius 6 whose border turns blue, with a soft ring, while it is typed in.
struct SearchField: View {
    let prompt: String
    @Binding var text: String
    var symbol: String = Symbol.search
    var submit: (() -> Void)?
    @FocusState private var focused: Bool
    @Environment(\.look) private var look

    enum Symbol {
        static let search = "magnifyingglass"
        static let clear = "xmark.circle.fill"
    }

    private static let consolePadding: CGFloat = 12

    var body: some View {
        let console = look == .console
        let tokens = look.tokens
        let shape = RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous)
        let face = HStack(spacing: console ? Memnox.Spacing.medium : ControlMetrics.iconSpacing) {
            Image(systemName: symbol)
                .font(.system(size: console ? Memnox.TextSize.callout : ControlMetrics.textSize))
                .foregroundStyle(tokens.muted)
            TextField(prompt, text: $text)
                .onSubmit { submit?() }
                .textFieldStyle(.plain)
                .font(look.sans(ControlMetrics.textSize))
                .foregroundStyle(tokens.foreground)
                .focused($focused)
                // The capsule is the field, so macOS draws no blue ring around it on focus.
                .focusEffectDisabled()
            if !text.isEmpty {
                Button("Clear", systemImage: Symbol.clear) { text = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(tokens.muted)
                    .help("Clear")
            }
        }
        .padding(.horizontal, console ? Self.consolePadding : ControlMetrics.horizontalPadding - ControlMetrics.fieldPadding)
        .frame(height: console ? Memnox.Console.fieldHeight : ControlMetrics.height)
        .onTapGesture { focused = true }
        if console {
            face
                .background(shape.fill(tokens.field))
                .overlay(shape.strokeBorder(focused ? tokens.primary : tokens.fieldEdge, lineWidth: Memnox.Stroke.hairline))
                .background(shape.stroke(focused ? Memnox.Console.ring : Color.clear, lineWidth: Memnox.Console.ringWidth * 2))
                .contentShape(shape)
                .animation(.easeOut(duration: Memnox.Motion.quick), value: focused)
        } else {
            face
                .background(tokens.field, in: Capsule())
                .overlay(Capsule().strokeBorder(tokens.fieldEdge, lineWidth: Memnox.Stroke.hairline))
                .contentShape(Capsule())
        }
    }
}

/// A checkbox as Vorssaint ticks one: a small rounded square, blue with a white tick when on, its words after it.
struct CheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        CheckboxFace(configuration: configuration)
    }
}

/// The checkbox drawn in the look of the window it sits in.
private struct CheckboxFace: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.look) private var look

    private static let tick = "checkmark"

    var body: some View {
        let tokens = look.tokens
        let shape = RoundedRectangle(cornerRadius: ControlMetrics.checkboxRadius, style: .continuous)
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: ControlMetrics.iconSpacing) {
                ZStack {
                    if configuration.isOn {
                        shape.fill(tokens.primary)
                        Image(systemName: Self.tick)
                            .font(.system(size: ControlMetrics.checkSymbol, weight: .bold))
                            .foregroundStyle(Color.white)
                    } else {
                        shape.fill(tokens.field)
                            .overlay(shape.strokeBorder(tokens.rim, lineWidth: Memnox.Stroke.hairline))
                    }
                }
                .frame(width: ControlMetrics.checkboxSide, height: ControlMetrics.checkboxSide)
                configuration.label
                    .font(look.sans(ControlMetrics.textSize))
                    .foregroundStyle(tokens.foreground)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHand()
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

/// A shortcut as Vorssaint shows one: each key printed on its own cap, inside a grey capsule.
struct ShortcutField: View {
    let keys: [String]
    @Environment(\.look) private var look

    var body: some View {
        let tokens = look.tokens
        HStack(spacing: ControlMetrics.keySpacing) {
            ForEach(keys, id: \.self) { Keycap(label: $0) }
        }
        .padding(.horizontal, ControlMetrics.fieldPadding * 2)
        .frame(height: ControlMetrics.height)
        .background(tokens.raised, in: Capsule())
        .overlay(Capsule().strokeBorder(tokens.controlEdge, lineWidth: Memnox.Stroke.hairline))
        .accessibilityElement(children: .combine)
    }
}

/// Back and Forward in one bordered capsule beside the page's title, as Vorssaint heads its pages.
struct NavigationCapsule: View {
    let canGoBack: Bool
    let canGoForward: Bool
    let back: () -> Void
    let forward: () -> Void

    private enum Layout {
        static let width: CGFloat = 69
        static let height: CGFloat = 32
        static let symbolSize: CGFloat = 13
        /// The faint lift Vorssaint's capsule has off the page.
        static let shadow = 0.06
        static let shadowRadius: CGFloat = 2
        static let shadowDrop: CGFloat = 1
    }

    private enum Symbol {
        static let back = "chevron.backward"
        static let forward = "chevron.forward"
    }

    var body: some View {
        HStack(spacing: 0) {
            arrow(Symbol.back, "Back", enabled: canGoBack, action: back)
            arrow(Symbol.forward, "Forward", enabled: canGoForward, action: forward)
        }
        .frame(width: Layout.width, height: Layout.height)
        .background(Memnox.Palette.capsule, in: Capsule())
        .overlay(Capsule().strokeBorder(Memnox.Palette.capsuleEdge, lineWidth: Memnox.Stroke.hairline))
        .shadow(color: .black.opacity(Layout.shadow), radius: Layout.shadowRadius, y: Layout.shadowDrop)
    }

    private func arrow(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: Layout.symbolSize, weight: .semibold))
                .foregroundStyle(enabled ? Memnox.Palette.foreground : Memnox.Palette.faint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHand()
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }
}
