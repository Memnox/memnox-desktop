import MemnoxVoiceCore
import SwiftUI

/// The five destinations, with Settings and the runtime's standing at the foot, laid out as the console's sidebar: flat
/// on the ground with a rule down its right, a 56 high head holding the mark, the name and a Local pill, and rows at
/// radius 6 lit by the active fill. As a rail it keeps only the icons, each named for VoiceOver and on hover, so nothing
/// is lost when the window is made narrow.
struct AppSidebar: View {
    @ObservedObject var shell: AppShellModel
    let route: WindowRoute
    let rail: Bool
    /// Whether the person may fold it themselves, which only a window wide enough for labels offers.
    let canFold: Bool
    let home: HomeModel?

    enum Layout {
        static let width: CGFloat = 240
        static let railWidth: CGFloat = 64
        /// The window's buttons sit at the head's start, so the mark begins after them.
        static let trafficLightsRoom: CGFloat = 76
        static let padding: CGFloat = 12
        static let rowHeight: CGFloat = 36
        static let railRow: CGFloat = 40
        static let rowRadius: CGFloat = Memnox.Console.controlRadius
        static let iconWidth: CGFloat = 18
        static let iconSize: CGFloat = 15
        static let tile: CGFloat = 26
        static let tileTint = 0.12
        static let pillTracking: CGFloat = 1.4
        static let pillText: CGFloat = 10
        static let pillPadding: CGFloat = 8
    }

    static func symbol(_ destination: Destination) -> String {
        switch destination {
        case .home: "house"
        case .agents: "cpu"
        case .workspaces: "folder"
        case .mcp: "powerplug"
        case .governance: "checkmark.shield"
        case .settings: "gearshape"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: rail ? .center : .leading, spacing: Memnox.Spacing.xxSmall) {
                    ForEach(Destinations.all.filter { $0.id != .settings }, id: \.id) { each in
                        item(symbol: Self.symbol(each.id), title: each.title, hint: each.subtitle, chosen: route.destination == each.id) {
                            shell.go(WindowRoute(each.id))
                        }
                    }
                }
                .padding(.horizontal, rail ? Memnox.Spacing.medium : Layout.padding)
                .padding(.top, Layout.padding)
                .padding(.bottom, Memnox.Spacing.medium)
            }
            .scrollIndicators(.never)
            VStack(alignment: rail ? .center : .leading, spacing: Memnox.Spacing.xxSmall) {
                if let home {
                    RuntimeStanding(home: home, rail: rail)
                } else {
                    RuntimeWord(tone: .quiet, words: RuntimeStanding.reaching, rail: rail)
                }
                let settings = Destinations.info(.settings)
                item(symbol: Self.symbol(.settings), title: settings.title, hint: settings.subtitle, chosen: route.destination == .settings) {
                    shell.go(WindowRoute(.settings))
                }
                if canFold {
                    item(symbol: "sidebar.left", title: shell.collapsed ? "Show labels" : "Hide labels",
                         hint: "Fold the sidebar to its icons", chosen: false) {
                        withAnimation(.snappy) { shell.collapsed.toggle() }
                    }
                }
            }
            .padding(.horizontal, rail ? Memnox.Spacing.medium : Layout.padding)
            .padding(.vertical, Memnox.Spacing.medium)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) { ShellDivider() }
        }
        .frame(width: rail ? Layout.railWidth : Layout.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Memnox.Console.surface)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Memnox.Console.panelEdge).frame(width: Memnox.Stroke.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Memnox")
    }

    /// The brand head, as tall as the top bar so their two rules meet. On the rail the window's buttons fill it.
    private var header: some View {
        HStack(spacing: Memnox.Spacing.regular) {
            if !rail {
                BrandTile(side: Layout.tile, tint: Layout.tileTint)
                Text("Memnox")
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.base, .semibold))
                    .tracking(Memnox.Console.titleTracking / 2)
                    .foregroundStyle(Memnox.Console.foreground)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("Local".uppercased())
                    .font(Memnox.Console.sans(Layout.pillText, .medium))
                    .tracking(Layout.pillTracking)
                    .foregroundStyle(Memnox.Console.muted)
                    .padding(.horizontal, Layout.pillPadding)
                    .padding(.vertical, 1)
                    .overlay(Capsule().strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
                    .fixedSize()
                    .accessibilityLabel("Local")
            }
        }
        .padding(.leading, rail ? 0 : Layout.trafficLightsRoom)
        .padding(.trailing, rail ? 0 : Layout.padding + Memnox.Spacing.xSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: ShellMetrics.barHeight)
        .overlay(alignment: .bottom) { ShellDivider() }
    }

    private func item(symbol: String, title: String, hint: String, chosen: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Memnox.Spacing.regular) {
                Image(systemName: symbol)
                    .font(.system(size: Layout.iconSize, weight: .regular))
                    .foregroundStyle(chosen ? Memnox.Console.foreground : Memnox.Console.muted)
                    .frame(width: Layout.iconWidth)
                if !rail {
                    Text(title)
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, chosen ? .medium : .regular))
                        .foregroundStyle(chosen ? Memnox.Console.foreground : Memnox.Console.muted)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, rail ? 0 : Layout.padding)
            .frame(width: rail ? Layout.railRow : nil, height: Layout.rowHeight)
            .frame(maxWidth: rail ? nil : .infinity, alignment: .leading)
            .background(chosen ? Memnox.Console.active : Color.clear,
                        in: RoundedRectangle(cornerRadius: Layout.rowRadius, style: .continuous))
            .hoverLight(radius: Layout.rowRadius, inset: 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(rail ? title : hint)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// The runtime's standing at the sidebar's foot, read off the home the window already keeps.
private struct RuntimeStanding: View {
    @ObservedObject var home: HomeModel
    let rail: Bool

    static let reaching = "Reaching the runtime"

    var body: some View {
        if home.home != nil {
            RuntimeWord(tone: .good, words: "Runtime running", rail: rail)
        } else if home.unavailable {
            RuntimeWord(tone: .bad, words: "Runtime not answering", rail: rail)
        } else {
            RuntimeWord(tone: .quiet, words: Self.reaching, rail: rail)
        }
    }
}

/// The standing as a word with its dot, or as the dot alone on the rail with the word for hover and VoiceOver.
private struct RuntimeWord: View {
    let tone: Tone
    let words: String
    let rail: Bool

    var body: some View {
        Group {
            if rail {
                Circle().fill(tone.dot)
                    .frame(width: ShellMetrics.dot + 2, height: ShellMetrics.dot + 2)
                    .frame(width: AppSidebar.Layout.railRow, height: AppSidebar.Layout.rowHeight)
                    .help(words)
                    .accessibilityElement()
                    .accessibilityLabel(words)
            } else {
                StatusWord(tone, words)
                    .padding(.horizontal, Memnox.Spacing.small)
                    .frame(maxWidth: .infinity, minHeight: AppSidebar.Layout.rowHeight, alignment: .leading)
            }
        }
    }
}

/// The mark in the console's blue on a tile of its own tint, as the console's sidebar heads itself.
private struct BrandTile: View {
    let side: CGFloat
    let tint: Double

    /// The mark fills a little over half the tile.
    private static let markShare: CGFloat = 0.6

    var body: some View {
        Group {
            if let logo = MemnoxLogo.white {
                Image(nsImage: logo)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(Memnox.Console.primary)
            } else {
                Circle().fill(Memnox.Console.primary)
            }
        }
        .frame(width: side * Self.markShare, height: side * Self.markShare)
        .frame(width: side, height: side)
        .background(Memnox.Console.primary.opacity(tint), in: RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}
