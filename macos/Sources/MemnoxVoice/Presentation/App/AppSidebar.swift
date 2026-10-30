import MemnoxVoiceCore
import SwiftUI

/// The five destinations, with Settings and the runtime's standing at the foot. As a rail it keeps only the icons, each
/// named for VoiceOver and on hover, so nothing is lost when the window is made narrow.
struct AppSidebar: View {
    @ObservedObject var shell: AppShellModel
    let route: WindowRoute
    let rail: Bool
    /// Whether the person may fold it themselves, which only a window wide enough for labels offers.
    let canFold: Bool
    let home: HomeModel?

    enum Layout {
        static let width: CGFloat = 232
        static let railWidth: CGFloat = 60
        /// The window's buttons sit over the sidebar's top, so its first row starts below them.
        static let trafficLightsRoom: CGFloat = 44
        static let padding: CGFloat = 10
        static let rowHeight: CGFloat = 32
        static let railRow: CGFloat = 40
        static let rowRadius: CGFloat = 8
        static let iconWidth: CGFloat = 18
        static let iconSize: CGFloat = 14
        static let logo: CGFloat = 22
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
        VStack(alignment: rail ? .center : .leading, spacing: 2) {
            header
            ForEach(Destinations.all.filter { $0.id != .settings }, id: \.id) { each in
                item(symbol: Self.symbol(each.id), title: each.title, hint: each.subtitle, chosen: route.destination == each.id) {
                    shell.go(WindowRoute(each.id))
                }
            }
            Spacer(minLength: Layout.padding)
            ShellDivider().padding(.bottom, Memnox.Spacing.small)
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
        .padding(.top, Layout.trafficLightsRoom)
        .padding(.horizontal, rail ? Memnox.Spacing.medium : Layout.padding)
        .padding(.bottom, Layout.padding)
        .frame(width: rail ? Layout.railWidth : Layout.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Memnox")
    }

    private var header: some View {
        HStack(spacing: Memnox.Spacing.medium) {
            LogoMark(size: Layout.logo)
            if !rail {
                Text("Memnox")
                    .font(Memnox.Console.sans(Memnox.TextSize.headline, .semibold))
                    .foregroundStyle(Memnox.Console.foreground)
                Spacer(minLength: 0)
                Text("Local")
                    .font(Memnox.Console.sans(Memnox.TextSize.micro, .medium))
                    .foregroundStyle(Memnox.Console.muted)
                    .padding(.horizontal, Memnox.Spacing.small)
                    .padding(.vertical, Memnox.Spacing.xxSmall)
                    .overlay(RoundedRectangle(cornerRadius: Memnox.radius, style: .continuous)
                        .strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
            }
        }
        .padding(.horizontal, rail ? 0 : Memnox.Spacing.small)
        .padding(.bottom, Memnox.Spacing.xLarge)
    }

    private func item(symbol: String, title: String, hint: String, chosen: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Memnox.Spacing.regular) {
                Image(systemName: symbol)
                    .font(.system(size: Layout.iconSize, weight: .medium))
                    .foregroundStyle(chosen ? Memnox.Console.primary : Memnox.Console.muted)
                    .frame(width: Layout.iconWidth)
                if !rail {
                    Text(title)
                        .font(Memnox.Console.sans(Memnox.TextSize.body, chosen ? .medium : .regular))
                        .foregroundStyle(chosen ? Memnox.Console.foreground : Memnox.Console.muted)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, rail ? 0 : Memnox.Spacing.regular)
            .frame(width: rail ? Layout.railRow : nil, height: Layout.rowHeight)
            .frame(maxWidth: rail ? nil : .infinity, alignment: .leading)
            .background(chosen ? Memnox.Console.hover : Color.clear,
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
                    .padding(.horizontal, Memnox.Spacing.regular)
                    .frame(maxWidth: .infinity, minHeight: AppSidebar.Layout.rowHeight, alignment: .leading)
            }
        }
    }
}
