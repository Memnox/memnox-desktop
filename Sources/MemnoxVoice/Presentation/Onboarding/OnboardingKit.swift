import AppKit
import SwiftUI

/// The pieces every first run step is built from, so each step reads as the same design: a card with an icon, a
/// title and a line under it, rows with their icon on a bordered tile, a square checkbox, and one size of button.
enum Kit {
    static let cardRadius: CGFloat = 16
    static let cardPadding: CGFloat = 20
    static let tileSide: CGFloat = 38
    static let tileRadius: CGFloat = 10
    static let checkSide: CGFloat = 20
    static let checkRadius: CGFloat = 6
    /// Every button in the first run is this tall, whether it moves on or acts inside a row.
    static let buttonHeight: CGFloat = 36
    static let rowGap: CGFloat = 14
    /// Springs settle with a little give and no wobble.
    static let springDamping = 0.8
}

/// A card as voiceos draws its settings: an icon, a title and a line, then its rows, on one graphite panel.
struct KitCard<Content: View>: View {
    var symbol: String?
    var title: String?
    var detail: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Kit.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: Kit.cardPadding) {
            if let title {
                HStack(alignment: .top, spacing: Memnox.Spacing.large) {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: Memnox.TextSize.title, weight: .regular))
                            .foregroundStyle(Memnox.ink(Memnox.Ink.primary))
                            .frame(width: Memnox.Spacing.xxLarge)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                        Text(title)
                            .font(Memnox.sans(Memnox.TextSize.headline, .semibold))
                            .foregroundStyle(Memnox.Palette.ink)
                        if let detail {
                            Text(detail)
                                .font(Memnox.sans(Memnox.TextSize.body))
                                .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 0) { content() }
        }
        .padding(Kit.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Memnox.Palette.surface))
        .overlay(shape.strokeBorder(Memnox.ink(Memnox.Ink.rim), lineWidth: Memnox.Stroke.hairline))
    }
}

/// A row: its icon on a bordered tile, its title and what it means, and one control on the right. What the person has
/// to do next shows under it in the quiet ink, never in a colour of its own.
struct KitRow<Leading: View, Trailing: View>: View {
    let title: String
    var detail: String?
    var hint: String?
    let leading: Leading
    let trailing: Trailing

    init(title: String, detail: String? = nil, hint: String? = nil,
         @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.hint = hint
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: Memnox.Spacing.large) {
            leading
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                Text(title)
                    .font(Memnox.sans(Memnox.TextSize.callout, .semibold))
                    .foregroundStyle(Memnox.Palette.ink)
                if let detail {
                    Text(detail)
                        .font(Memnox.sans(Memnox.TextSize.footnote))
                        .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let hint {
                    Label(hint, systemImage: "exclamationmark.circle")
                        .font(Memnox.sans(Memnox.TextSize.footnote, .medium))
                        .foregroundStyle(Memnox.ink(Memnox.Ink.primary))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.top, Memnox.Spacing.xxSmall)
                }
            }
            Spacer(minLength: Memnox.Spacing.medium)
            // The control keeps its width and the words wrap, since a button squeezed to an ellipsis says nothing.
            trailing.fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, Memnox.Spacing.regular)
    }
}

extension KitRow where Leading == IconTile {
    init(symbol: String, title: String, detail: String? = nil, hint: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, detail: detail, hint: hint, leading: { IconTile(symbol: symbol) }, trailing: trailing)
    }
}

/// A symbol on a small rounded tile with a hairline border, as voiceos marks each action.
struct IconTile: View {
    let symbol: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Kit.tileRadius, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: Memnox.TextSize.callout, weight: .medium))
            .foregroundStyle(Memnox.ink(Memnox.Ink.primary))
            .frame(width: Kit.tileSide, height: Kit.tileSide)
            .background(shape.fill(Memnox.Palette.raised))
            .overlay(shape.strokeBorder(Memnox.ink(Memnox.Ink.edge), lineWidth: Memnox.Stroke.hairline))
            .accessibilityHidden(true)
    }
}

/// The Memnox mark on the same bordered tile, for a row about Memnox itself rather than one of its parts.
struct MemnoxTile: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Kit.tileRadius, style: .continuous)
        LogoMark(size: Kit.tileSide * 0.5)
            .frame(width: Kit.tileSide, height: Kit.tileSide)
            .background(shape.fill(Memnox.Palette.raised))
            .overlay(shape.strokeBorder(Memnox.ink(Memnox.Ink.edge), lineWidth: Memnox.Stroke.hairline))
            .accessibilityHidden(true)
    }
}

/// The hairline between two rows of one card, starting under the titles.
struct KitDivider: View {
    var body: some View {
        Rectangle()
            .fill(Memnox.ink(Memnox.Ink.faintFill))
            .frame(height: Memnox.Stroke.hairline)
            .padding(.leading, Kit.tileSide + Memnox.Spacing.large)
    }
}

/// A square checkbox: filled with the Memnox blue and ticked once done, an empty square while waiting, and an empty square with a
/// mark when it needs the person.
struct CheckBox: View {
    let state: StepState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How much of the mark its symbol fills, so the tick and the warning read at the same weight.
    private static let symbolShare: CGFloat = 0.55
    /// A circle rather than a box, so a status is never mistaken for something to tick.
    private static let waitingDash: [CGFloat] = [2.5, 2.5]

    var body: some View {
        ZStack {
            switch state {
            case .done:
                Circle().fill(Memnox.Palette.primary)
                Image(systemName: "checkmark")
                    .font(.system(size: Kit.checkSide * Self.symbolShare, weight: .bold))
                    .foregroundStyle(Color.white)
            case .waiting:
                Circle().strokeBorder(Memnox.ink(Memnox.Ink.tertiary),
                                      style: StrokeStyle(lineWidth: Memnox.Stroke.emphasis, dash: Self.waitingDash))
            case .needs:
                Circle().fill(Memnox.Palette.warm)
                Image(systemName: "exclamationmark")
                    .font(.system(size: Kit.checkSide * Self.symbolShare, weight: .bold))
                    .foregroundStyle(Color.white)
            }
        }
        .frame(width: Kit.checkSide, height: Kit.checkSide)
        .animation(reduceMotion ? nil : .spring(response: Memnox.Motion.standard, dampingFraction: Kit.springDamping), value: state)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var label: String {
        switch state {
        case .done: return "Done"
        case .waiting: return "Not yet"
        case .needs(let why): return "Needs you: \(why)"
        }
    }
}

/// The one button of the first run: solid ink for the thing to do, the panel's grey for the rest, and glass over the
/// veil. One height everywhere, so a row's button and the step's button read as the same kind.
struct KitButton: ButtonStyle {
    enum Kind {
        case primary
        case secondary
        case glass
    }

    let kind: Kind
    var wide = false

    func makeBody(configuration: Configuration) -> some View {
        KitButtonFace(configuration: configuration, kind: kind, wide: wide)
    }
}

/// The button's face, a view of its own so it can know when the pointer is over it: the fill lifts, the pointer turns
/// to a hand, and a press gives a little, so every button answers before it is clicked.
private struct KitButtonFace: View {
    let configuration: ButtonStyleConfiguration
    let kind: KitButton.Kind
    let wide: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    private static let horizontalPadding: CGFloat = 18
    private static let pressedScale: CGFloat = 0.97
    private static let disabledOpacity = 0.4
    private static let glassFill = 0.1
    /// How much the face lifts under the pointer: a wash of ink over the grey ones, a little dimming of the solid one.
    private static let hoverWash = 0.08
    private static let hoverDim = 0.88

    var body: some View {
        configuration.label
            .labelStyle(KitLabel())
            .font(Memnox.sans(Memnox.TextSize.body, .semibold))
            .foregroundStyle(text)
            .lineLimit(1)
            .padding(.horizontal, Self.horizontalPadding)
            .frame(height: Kit.buttonHeight)
            .frame(maxWidth: wide ? .infinity : nil)
            .background(Capsule().fill(fill).opacity(kind == .primary && hovering ? Self.hoverDim : 1))
            .overlay(Capsule().fill(Memnox.ink(kind != .primary && hovering ? Self.hoverWash : 0)))
            .overlay(Capsule().strokeBorder(edge, lineWidth: Memnox.Stroke.hairline))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : Self.disabledOpacity)
            // With Reduce Motion on, a press only dims, since the give of the spring is movement.
            .scaleEffect(configuration.isPressed && !reduceMotion ? Self.pressedScale : 1)
            .animation(reduceMotion ? nil : .spring(response: Memnox.Motion.quick, dampingFraction: Kit.springDamping), value: configuration.isPressed)
            .animation(.easeOut(duration: Memnox.Motion.quick), value: hovering)
            .onHover { over in hovering = over && isEnabled }
            .onDisappear { hovering = false }
            .pointingHand()
    }

    private var text: Color {
        switch kind {
        case .primary: return IslandPalette.primaryText
        case .secondary: return Memnox.Palette.ink
        case .glass: return Color.white
        }
    }

    private var fill: Color {
        switch kind {
        case .primary: return IslandPalette.primaryFill
        case .secondary: return Memnox.Palette.raised
        case .glass: return Color.white.opacity(Self.glassFill)
        }
    }

    private var edge: Color {
        switch kind {
        case .primary: return .clear
        case .secondary: return Memnox.ink(Memnox.Ink.edge)
        case .glass: return Color.white.opacity(Memnox.Ink.edge * 2)
        }
    }
}

/// A picker in the shape of a field, as voiceos picks a voice: the choice on the left and a chevron on the right.
struct KitMenu<Items: View>: View {
    let current: String
    var width: CGFloat = 200
    @ViewBuilder let items: () -> Items

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Kit.tileRadius, style: .continuous)
        Menu { items() } label: {
            HStack {
                Text(current)
                    .font(Memnox.sans(Memnox.TextSize.body, .medium))
                    .foregroundStyle(Memnox.Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: Memnox.Spacing.small)
                Image(systemName: "chevron.down")
                    .font(.system(size: Memnox.TextSize.caption, weight: .semibold))
                    .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
            }
            .padding(.horizontal, Memnox.Spacing.large)
            .frame(width: width, height: Kit.buttonHeight)
            .background(shape.fill(Memnox.Palette.raised))
            .overlay(shape.strokeBorder(Memnox.ink(Memnox.Ink.edge), lineWidth: Memnox.Stroke.hairline))
            .contentShape(shape)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .pointingHand()
        .menuIndicator(.hidden)
    }
}

/// A button's icon before its word, a little smaller and at the same weight, so the two read as one label.
struct KitLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Memnox.Spacing.small) {
            configuration.icon.font(.system(size: Memnox.TextSize.footnote, weight: .semibold))
            configuration.title
        }
    }
}
