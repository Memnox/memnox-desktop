import AppKit
import MemnoxVoiceCore
import SwiftUI

/// Green, amber, red and grey, each always beside a word, since colour alone says nothing to many people.
enum Tone {
    case good
    case attention
    case bad
    case quiet

    var color: Color {
        switch self {
        case .good: Memnox.Console.success
        case .attention: Memnox.Console.warm
        case .bad: Memnox.Console.destructive
        case .quiet: Memnox.Console.muted
        }
    }

    var dot: Color { self == .quiet ? Memnox.Console.faint : color }

    /// The console's pill under the word: its own colour at 12 to 14 percent, grey words on the hover fill when quiet.
    var pill: Color {
        switch self {
        case .good: Memnox.Console.success.opacity(ToneTint.soft)
        case .attention: Memnox.Console.warm.opacity(ToneTint.warm)
        case .bad: Memnox.Console.destructive.opacity(ToneTint.soft)
        case .quiet: Memnox.Console.hover
        }
    }

    /// How a session's status reads: red paused, amber waiting on the person, green busy, grey otherwise.
    init(_ status: SessionStatus) {
        switch status {
        case .paused: self = .bad
        case .needsYou, .waitingOnYou: self = .attention
        case .working, .thinking: self = .good
        case .ended, .quiet: self = .quiet
        }
    }
}

/// How strongly a status colour washes its pill, as the console mixes them.
private enum ToneTint {
    static let soft = 0.12
    static let warm = 0.14
}

/// The measures the window's own pieces share, apart from the Settings pages' column.
enum ShellMetrics {
    /// The widest a page's content grows, centred in a wider window, as the console caps its own.
    static let pageWidth: CGFloat = 1216
    static let pagePadding: CGFloat = 20
    /// From the console's widest breakpoint the page breathes a little more at its sides.
    static let widePadding: CGFloat = 28
    static let compactPadding: CGFloat = 14
    static let pageTop: CGFloat = 24
    static let pageBottom: CGFloat = 40
    static let sectionSpacing: CGFloat = 24
    static let rowPaddingH: CGFloat = 16
    static let rowPaddingV: CGFloat = 12
    static let radius: CGFloat = Memnox.Console.cardRadius
    static let dot: CGFloat = 6
    /// As tall as the sidebar's head, so the two rules meet at the corner as the console's do.
    static let barHeight: CGFloat = 56
}

/// A status in its colour, with the dot beside the word rather than in place of it.
struct StatusWord: View {
    let tone: Tone
    let text: String

    init(_ tone: Tone, _ text: String) {
        self.tone = tone
        self.text = text
    }

    private static let padH: CGFloat = 10
    private static let padV: CGFloat = 2

    var body: some View {
        // A state worn as the console's pill, its colour always beside the word.
        Text(text)
            .font(Memnox.Console.sans(Memnox.Console.TextSize.meta, .medium))
            .foregroundStyle(tone.color)
            .lineLimit(1)
            .padding(.horizontal, Self.padH)
            .padding(.vertical, Self.padV)
            .background(tone.pill, in: Capsule())
            .fixedSize()
            .accessibilityElement(children: .combine)
    }
}

/// Whose an item is, grey and always with its word, so the scope is never told by colour alone.
struct ScopeChip: View {
    let kind: ScopeKind

    init(_ kind: ScopeKind) {
        self.kind = kind
    }

    var body: some View {
        Text(kind.word)
            .font(Memnox.Console.sans(Memnox.Console.TextSize.label, .medium))
            .foregroundStyle(Memnox.Console.muted)
            .lineLimit(1)
            .padding(.horizontal, Memnox.Spacing.medium)
            .padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
            .fixedSize()
            .accessibilityLabel(kind.label)
    }
}

/// A list in one rounded panel, rows divided by hairlines the caller draws between them.
struct ShellPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Memnox.Console.card, in: RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
                .strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
            .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous))
    }
}

/// The hairline between two rows of a panel.
struct ShellDivider: View {
    var body: some View {
        Rectangle().fill(Memnox.Console.panelEdge).frame(height: Memnox.Stroke.hairline)
    }
}

/// One row of a panel: something at its start, a title with a line under it, and whatever belongs at its end. A row
/// with an action is a button and lights under the pointer.
struct ShellRow<Leading: View, Trailing: View>: View {
    let title: String
    var caption: String?
    var chosen = false
    var action: (() -> Void)?
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        if let action {
            Button(action: action) { face.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .hoverLight(radius: 0, inset: 0)
                .accessibilityAddTraits(chosen ? .isSelected : [])
        } else {
            face
        }
    }

    private var face: some View {
        HStack(spacing: Memnox.Spacing.large) {
            leading
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                Text(title)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                    .foregroundStyle(Memnox.Console.foreground)
                    .lineLimit(1)
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                        .foregroundStyle(Memnox.Console.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Memnox.Spacing.medium)
            trailing
        }
        .padding(.horizontal, ShellMetrics.rowPaddingH)
        .padding(.vertical, ShellMetrics.rowPaddingV)
        .background(chosen ? Memnox.Console.active : Color.clear)
    }
}

/// A titled block of a page, with one optional action on the right of its title.
struct ShellSection<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.regular) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.base, .medium))
                    .foregroundStyle(Memnox.Console.foreground)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Memnox.Spacing.large)
                trailing
            }
            content
        }
    }
}

extension ShellSection where Trailing == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

/// What to do when there is nothing here yet, never only that nothing is here, in the console's bordered card.
struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String

    private static let maxText: CGFloat = 448
    private static let padding: CGFloat = 40
    private static let symbolSize: CGFloat = 20

    var body: some View {
        VStack(spacing: Memnox.Spacing.medium) {
            Image(systemName: symbol)
                .font(.system(size: Self.symbolSize))
                .foregroundStyle(Memnox.Console.muted)
                .accessibilityHidden(true)
            Text(title)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                .foregroundStyle(Memnox.Console.foreground)
            Text(detail)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
                .foregroundStyle(Memnox.Console.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(Memnox.Spacing.xxSmall)
                .frame(maxWidth: Self.maxText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(Self.padding)
        .background(Memnox.Console.card, in: RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
            .strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
        .accessibilityElement(children: .combine)
    }
}

/// A read that failed is said, never drawn as an empty page: the console's red tinted alert with a bordered Try again.
struct ReadFailed: View {
    let what: String
    let retry: () -> Void

    private static let edge = 0.3
    private static let wash = 0.05
    private static let padding: CGFloat = 16
    private static let buttonPadding: CGFloat = 14

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
        let button = RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous)
        HStack(spacing: Memnox.Spacing.large) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: Memnox.TextSize.callout))
                .foregroundStyle(Memnox.Console.destructive)
                .accessibilityHidden(true)
            Text("Memnox could not read \(what).")
                .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                .foregroundStyle(Memnox.Console.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: retry) {
                Label("Try again", systemImage: "arrow.clockwise")
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                    .foregroundStyle(Memnox.Console.foreground)
                    .padding(.horizontal, Self.buttonPadding)
                    .frame(height: Memnox.Console.fieldHeight)
                    .background(Memnox.Console.background, in: button)
                    .overlay(button.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
                    .contentShape(button)
            }
            .buttonStyle(.plain)
            .hoverLight(radius: Memnox.Console.controlRadius, inset: 0)
        }
        .padding(Self.padding)
        .background(Memnox.Console.destructive.opacity(Self.wash), in: shape)
        .overlay(shape.strokeBorder(Memnox.Console.destructive.opacity(Self.edge), lineWidth: Memnox.Stroke.hairline))
        .accessibilityElement(children: .contain)
    }
}

/// A quiet link to another place in the window.
struct GoLink: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Memnox.Spacing.xSmall) {
                Text(title)
                Image(systemName: "arrow.right").font(.system(size: Memnox.TextSize.micro, weight: .semibold))
            }
            .font(Memnox.Console.sans(Memnox.TextSize.footnote, .medium))
            .foregroundStyle(Memnox.Console.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHand()
    }
}

/// Names and values in two columns, the facts an inspector lists.
struct FactList: View {
    let facts: [(String, String)]

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Memnox.Spacing.xLarge, verticalSpacing: Memnox.Spacing.medium) {
            ForEach(facts, id: \.0) { name, value in
                GridRow {
                    Text(name).foregroundStyle(Memnox.Console.muted)
                    Text(value)
                        .foregroundStyle(Memnox.Console.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
            }
        }
    }
}

/// The tabs of a destination under the top bar, drawn only when there are two or more to choose between.
struct ShellTabBar: View {
    let tabs: [TabInfo]
    let chosen: String?
    let choose: (String) -> Void

    private static let underline: CGFloat = 2

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Memnox.Spacing.xSmall) {
                ForEach(tabs, id: \.id) { tab in
                    let on = tab.id == chosen
                    Button { choose(tab.id) } label: {
                        Text(tab.title)
                            .font(Memnox.Console.sans(Memnox.TextSize.body, on ? .medium : .regular))
                            .foregroundStyle(on ? Memnox.Console.foreground : Memnox.Console.muted)
                            .padding(.horizontal, Memnox.Spacing.regular)
                            .padding(.vertical, Memnox.Spacing.regular)
                            .overlay(alignment: .bottom) {
                                if on {
                                    Capsule().fill(Memnox.Console.primary).frame(height: Self.underline)
                                        .padding(.horizontal, Memnox.Spacing.medium)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                    .accessibilityHint("Tab")
                }
            }
            .padding(.horizontal, Memnox.Spacing.large)
        }
        .scrollIndicators(.never)
        .overlay(alignment: .bottom) { ShellDivider() }
    }
}

/// A page's column: as wide as the window allows up to the page's own limit, scrolling under the top bar.
struct ShellScroll<Content: View>: View {
    let width: WidthClass
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ShellMetrics.sectionSpacing) { content }
                .frame(maxWidth: ShellMetrics.pageWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, ShellScroll.side(width))
                .padding(.top, ShellMetrics.pageTop)
                .padding(.bottom, ShellMetrics.pageBottom)
        }
        .scrollIndicators(.automatic)
        .clipped()
    }

    /// The page's sides at a width: tight on the narrowest windows, roomier from the console's widest breakpoint.
    static func side(_ width: WidthClass) -> CGFloat {
        switch width {
        case .compact: ShellMetrics.compactPadding
        case .wide: ShellMetrics.widePadding
        case .medium, .narrow: ShellMetrics.pagePadding
        }
    }
}

/// The page with its selected item's details. Wide windows keep the details beside the page at a width the person
/// drags and the window remembers; medium ones float them over the page, and narrower ones give them the whole width.
struct InspectorLayout<Page: View, Detail: View>: View {
    let width: WidthClass
    /// The details' title, nil while nothing is selected.
    let title: String?
    let close: () -> Void
    @ViewBuilder let page: Page
    @ViewBuilder let detail: Detail

    @AppStorage(InspectorSize.key) private var size = InspectorSize.standard

    var body: some View {
        switch width {
        case .wide:
            HStack(spacing: 0) {
                page.frame(maxWidth: .infinity)
                if let title {
                    InspectorHandle(size: $size)
                    pane(title).frame(width: InspectorSize.clamped(size))
                }
            }
        case .medium:
            ZStack(alignment: .trailing) {
                page
                if let title {
                    let shape = RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous)
                    pane(title)
                        .clipShape(shape)
                        .overlay(shape.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
                        .shadow(color: .black.opacity(Memnox.Console.liftShadow), radius: Memnox.Console.liftRadius, y: Memnox.Console.liftDrop)
                        .frame(width: InspectorSize.clamped(size))
                        .padding(InspectorSize.floatInset)
                        .transition(.move(edge: .trailing))
                }
            }
        case .narrow, .compact:
            ZStack {
                page
                if let title { pane(title) }
            }
        }
    }

    private func pane(_ title: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Memnox.Spacing.medium) {
                Text(title)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .semibold))
                    .foregroundStyle(Memnox.Console.foreground)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button {
                    // The same details in a window of their own, which leaves the page's pane free.
                    InspectorWindows.open(title: title, content: AnyView(detail))
                    close()
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: Memnox.TextSize.footnote, weight: .semibold))
                        .foregroundStyle(Memnox.Console.muted)
                        .frame(width: InspectorSize.closeSide, height: InspectorSize.closeSide)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverLight(radius: Memnox.Console.controlRadius, inset: 0)
                .help("Open the details in their own window")
                .accessibilityLabel("Open the details in their own window")
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: Memnox.TextSize.footnote, weight: .semibold))
                        .foregroundStyle(Memnox.Console.muted)
                        .frame(width: InspectorSize.closeSide, height: InspectorSize.closeSide)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverLight(radius: Memnox.Console.controlRadius, inset: 0)
                .help("Close the details")
                .accessibilityLabel("Close the details")
            }
            .padding(.horizontal, Memnox.Spacing.xLarge)
            .frame(height: ShellMetrics.barHeight - Memnox.Spacing.xSmall)
            ShellDivider()
            ScrollView {
                detail
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Memnox.Spacing.xxLarge)
            }
        }
        .background(Memnox.Console.card)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// How wide the details are beside the page, remembered between openings.
enum InspectorSize {
    static let key = "memnox.inspector.width"
    static let standard: Double = 380
    static let least: Double = 300
    static let most: Double = 640
    /// How far one press of an arrow moves the edge, for somebody resizing from the keyboard.
    static let step: Double = 20
    /// Floating over a medium window: held off its edges, lifted just enough to read as above the page.
    static let floatInset: CGFloat = 8
    static let closeSide: CGFloat = 32

    static func clamped(_ size: Double) -> CGFloat {
        CGFloat(min(most, max(least, size)))
    }
}

/// The edge between the page and its details, dragged to resize them and adjustable from the keyboard.
private struct InspectorHandle: View {
    @Binding var size: Double
    @State private var start: Double?
    @State private var cursor = false

    private static let hitWidth: CGFloat = 7

    var body: some View {
        Rectangle()
            .fill(Memnox.Console.panelEdge)
            .frame(width: Memnox.Stroke.hairline)
            .frame(width: Self.hitWidth)
            .contentShape(Rectangle())
            .onHover { over in
                guard over != cursor else { return }
                cursor = over
                if over { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .onDisappear {
                if cursor { NSCursor.pop() }
                cursor = false
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        let from = start ?? size
                        start = from
                        size = Double(InspectorSize.clamped(from - drag.translation.width))
                    }
                    .onEnded { _ in start = nil }
            )
            .accessibilityElement()
            .accessibilityLabel("Resize the details")
            .accessibilityValue("\(Int(InspectorSize.clamped(size))) points wide")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: size = Double(InspectorSize.clamped(size + InspectorSize.step))
                case .decrement: size = Double(InspectorSize.clamped(size - InspectorSize.step))
                @unknown default: break
                }
            }
    }
}
