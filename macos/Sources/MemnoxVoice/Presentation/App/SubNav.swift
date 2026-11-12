import MemnoxVoiceCore
import SwiftUI

/// A destination's tabs as the console lays out its settings: a tree under headings, and the chosen tab's pane.
struct SubNavContext {
    /// The destination's title, written over the tree.
    let title: String
    let groups: [TabGroup]
    let chosen: String?
    let choose: (String) -> Void
}

/// What heads the page: the sub navigation with the pane's own header, or for a destination with one tab shown, its
/// title and what it is for. Home has neither.
enum PaneHeading {
    case subNav(SubNavContext, tab: TabInfo, group: String)
    case page(title: String, subtitle: String)
}

private struct PaneHeadingKey: EnvironmentKey {
    static let defaultValue: PaneHeading? = nil
}

extension EnvironmentValues {
    /// Set by the shell for the page it draws, and read by the column the page scrolls in.
    var paneHeading: PaneHeading? {
        get { self[PaneHeadingKey.self] }
        set { self[PaneHeadingKey.self] = newValue }
    }
}

enum SubNavMetrics {
    /// The console's container breakpoint, 48rem, past which the tree stands beside the pane.
    static let besideFrom: CGFloat = 768
    /// The tree's column, 13rem.
    static let treeWidth: CGFloat = 208
    static let gap: CGFloat = 32
    /// Between groups, and from the destination's title to the first.
    static let groupSpacing: CGFloat = 24
    /// Stacked above a narrow pane, the groups flow side by side at no less than 11rem each.
    static let stackedGroup: CGFloat = 176
    static let rowHeight: CGFloat = 36
    static let rowPadding: CGFloat = 12
    static let headerBottom: CGFloat = 24
    static let summaryWidth: CGFloat = 672
    static let focusRing: CGFloat = 2
}

/// The page's content under its heading: the tree beside the pane when there is room and stacked above it when narrow,
/// or a page title, or nothing at all. `width` is the column the page has, the inspector already taken out of it.
struct PaneFrame<Content: View>: View {
    let heading: PaneHeading?
    let width: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        switch heading {
        case .none:
            content
        case .page(let title, let subtitle):
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxLarge) {
                PageTitle(title: title, subtitle: subtitle)
                content
            }
        case .subNav(let context, let tab, let group):
            if width >= SubNavMetrics.besideFrom {
                HStack(alignment: .top, spacing: SubNavMetrics.gap) {
                    SubNavTree(context: context, stacked: false)
                        .frame(width: SubNavMetrics.treeWidth, alignment: .leading)
                    pane(tab, group)
                }
            } else {
                VStack(alignment: .leading, spacing: SubNavMetrics.gap) {
                    SubNavTree(context: context, stacked: true)
                    pane(tab, group)
                }
            }
        }
    }

    /// The pane under its own header: the heading it sits under, its title, and one line saying what it is for.
    private func pane(_ tab: TabInfo, _ group: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PageTitle(eyebrow: group, title: tab.title, subtitle: tab.summary)
                .padding(.bottom, SubNavMetrics.headerBottom)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The tree itself. Up and Down walk its rows, Home and End jump to either end, and Return or Space opens one.
struct SubNavTree: View {
    let context: SubNavContext
    let stacked: Bool
    @FocusState private var focused: String?

    private static let walkKeys: Set<KeyEquivalent> = [.upArrow, .downArrow, .home, .end]

    var body: some View {
        VStack(alignment: .leading, spacing: SubNavMetrics.groupSpacing) {
            Text(context.title)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.title, .semibold))
                .tracking(Memnox.Console.titleTracking)
                .foregroundStyle(Memnox.Console.foreground)
                .accessibilityAddTraits(.isHeader)
            if stacked {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: SubNavMetrics.stackedGroup), spacing: SubNavMetrics.groupSpacing,
                                             alignment: .top)],
                          alignment: .leading, spacing: SubNavMetrics.groupSpacing) {
                    ForEach(context.groups, id: \.id) { group($0) }
                }
            } else {
                ForEach(context.groups, id: \.id) { group($0) }
            }
        }
        .onKeyPress(keys: Self.walkKeys) { press in
            walk(press.key) ? .handled : .ignored
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(context.title)
    }

    private func group(_ group: TabGroup) -> some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
            Label {
                Text(group.title.uppercased())
            } icon: {
                Image(systemName: Self.symbol(group.id)).font(.system(size: Memnox.TextSize.callout))
            }
            .font(Memnox.Console.sans(Memnox.Console.TextSize.label, .medium))
            .tracking(Memnox.Console.headingTracking)
            .foregroundStyle(Memnox.Console.muted)
            .labelStyle(HeadingLabel())
            .padding(.horizontal, SubNavMetrics.rowPadding)
            .padding(.bottom, Memnox.Spacing.xSmall)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(group.title)
            ForEach(group.tabs, id: \.id) { row($0) }
        }
    }

    private func row(_ tab: TabInfo) -> some View {
        SubNavRow(tab: tab, on: tab.id == context.chosen, focused: focused == tab.id) { context.choose(tab.id) }
            .focusable()
            .focused($focused, equals: tab.id)
            .focusEffectDisabled()
            .onKeyPress(keys: [.return, .space]) { _ in
                context.choose(tab.id)
                return .handled
            }
    }

    /// Moves the keyboard along the rows, every group's in order, staying inside the tree at either end.
    private func walk(_ key: KeyEquivalent) -> Bool {
        let rows = context.groups.flatMap { $0.tabs.map(\.id) }
        guard let last = rows.indices.last, let focused, let here = rows.firstIndex(of: focused) else { return false }
        let next: Int
        switch key {
        case .downArrow: next = min(here + 1, last)
        case .upArrow: next = max(here - 1, 0)
        case .home: next = 0
        case .end: next = last
        default: return false
        }
        self.focused = rows[next]
        return true
    }

    static func symbol(_ group: TabGroupId) -> String {
        switch group {
        case .account: "person.crop.circle"
        case .devices: "laptopcomputer"
        case .voice: "mic"
        case .app: "macwindow"
        }
    }
}

/// One tab of the tree: muted until chosen, then the active fill and medium words, lit under the pointer and ringed in
/// the blue while it holds the keyboard.
private struct SubNavRow: View {
    let tab: TabInfo
    let on: Bool
    let focused: Bool
    let choose: () -> Void
    @State private var hovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous)
    }

    private var fill: Color {
        if on { return Memnox.Console.active }
        return hovering ? Memnox.Console.hover : Color.clear
    }

    private var face: some View {
        Text(tab.title)
            .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, on ? .medium : .regular))
            .foregroundStyle(on || hovering ? Memnox.Console.foreground : Memnox.Console.muted)
            .lineLimit(1)
            .padding(.horizontal, SubNavMetrics.rowPadding)
            .frame(maxWidth: .infinity, minHeight: SubNavMetrics.rowHeight, alignment: .leading)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(focused ? Memnox.Console.primary : Color.clear, lineWidth: SubNavMetrics.focusRing))
    }

    var body: some View {
        face
            .contentShape(shape)
            .onHover { hovering = $0 }
            .onTapGesture(perform: choose)
            .pointingHand()
            .help(tab.summary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tab.title)
            .accessibilityHint(tab.summary)
            .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { choose() }
    }
}

/// A heading's icon before its words, as the console sets them.
private struct HeadingLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Memnox.Spacing.medium) {
            configuration.icon
            configuration.title
        }
    }
}
