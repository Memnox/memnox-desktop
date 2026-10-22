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

/// A select's face: the choice and the up and down chevrons on a grey capsule, as Vorssaint's language menu.
struct SelectFace: View {
    let text: String
    var maximumWidth: CGFloat = .infinity
    @State private var hovering = false

    private static let chevrons = "chevron.up.chevron.down"
    /// The pointer's light over the capsule, half the row's own, since the capsule already stands out.
    private static let hoverWash = 0.5

    var body: some View {
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
/// default; given `submit`, Return sends what is typed, as the reply to a session in the notch does.
struct SearchField: View {
    let prompt: String
    @Binding var text: String
    var symbol: String = Symbol.search
    var submit: (() -> Void)?
    @FocusState private var focused: Bool

    enum Symbol {
        static let search = "magnifyingglass"
        static let clear = "xmark.circle.fill"
    }

    var body: some View {
        HStack(spacing: ControlMetrics.iconSpacing) {
            Image(systemName: symbol)
                .font(.system(size: ControlMetrics.textSize))
                .foregroundStyle(Memnox.Palette.muted)
            TextField(prompt, text: $text)
                .onSubmit { submit?() }
                .textFieldStyle(.plain)
                .font(.system(size: ControlMetrics.textSize))
                .foregroundStyle(Memnox.Palette.foreground)
                .focused($focused)
                // The capsule is the field, so macOS draws no blue ring around it on focus.
                .focusEffectDisabled()
            if !text.isEmpty {
                Button("Clear", systemImage: Symbol.clear) { text = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(Memnox.Palette.muted)
                    .help("Clear")
            }
        }
        .padding(.horizontal, ControlMetrics.horizontalPadding - ControlMetrics.fieldPadding)
        .frame(height: ControlMetrics.height)
        .background(Memnox.Palette.field, in: Capsule())
        .overlay(Capsule().strokeBorder(Memnox.Palette.fieldEdge, lineWidth: Memnox.Stroke.hairline))
        .contentShape(Capsule())
        .onTapGesture { focused = true }
    }
}

/// A checkbox as Vorssaint ticks one: a small rounded square, blue with a white tick when on, its words after it.
struct CheckboxStyle: ToggleStyle {
    private static let tick = "checkmark"

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: ControlMetrics.checkboxRadius, style: .continuous)
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: ControlMetrics.iconSpacing) {
                ZStack {
                    if configuration.isOn {
                        shape.fill(Memnox.Palette.primary)
                        Image(systemName: Self.tick)
                            .font(.system(size: ControlMetrics.checkSymbol, weight: .bold))
                            .foregroundStyle(Color.white)
                    } else {
                        shape.fill(Memnox.Palette.field)
                            .overlay(shape.strokeBorder(Memnox.Palette.rim, lineWidth: Memnox.Stroke.hairline))
                    }
                }
                .frame(width: ControlMetrics.checkboxSide, height: ControlMetrics.checkboxSide)
                configuration.label
                    .font(.system(size: ControlMetrics.textSize))
                    .foregroundStyle(Memnox.Palette.foreground)
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

    var body: some View {
        HStack(spacing: ControlMetrics.keySpacing) {
            ForEach(keys, id: \.self) { Keycap(label: $0) }
        }
        .padding(.horizontal, ControlMetrics.fieldPadding * 2)
        .frame(height: ControlMetrics.height)
        .background(Memnox.Palette.raised, in: Capsule())
        .overlay(Capsule().strokeBorder(Memnox.Palette.controlEdge, lineWidth: Memnox.Stroke.hairline))
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
