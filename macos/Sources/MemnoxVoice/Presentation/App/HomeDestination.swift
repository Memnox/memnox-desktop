import MemnoxVoiceCore
import SwiftUI

/// Home is the one page the window opens on, the same on the console, this Mac, Windows and Linux: the greeting and
/// mode, one Do this next card, then the blocks in the contract's order, each counting what it holds in its header.
/// No charts and no tiles, and every number is a count the ledger can show.
struct HomeDestination: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var menu: MenuModel
    @ObservedObject var setup: SetupModel
    @ObservedObject var island: IslandModel
    @ObservedObject var models: SettingsModels
    let width: WidthClass

    var body: some View {
        if let home = models.home {
            HomeAtAGlance(shell: shell, home: home, island: island, menu: menu, setup: setup, width: width)
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct HomeAtAGlance: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var home: HomeModel
    @ObservedObject var island: IslandModel
    let menu: MenuModel
    @ObservedObject var setup: SetupModel
    let width: WidthClass

    var body: some View {
        let view = home.home
        TodayDestination(shell: shell, island: island, home: home, agents: shell.agents, activity: shell.todayActivity, width: width) {
            header(view)
            if home.unavailable { ReadFailed(what: "the runtime", retry: home.refresh) }
            // The one Do this next card, setup first until it is done, then the getting started steps until every one is.
            HomeStart(shell: shell, tools: menu.tools, menu: menu, home: home, actions: view?.today.actions ?? 0,
                      mode: view.flatMap { HomeMode(rawValue: $0.mode) }, setupFinished: setup.isFinished) {
                OnboardingWindow.shared.show(setup)
            }
        }
        .task { home.refresh() }
    }

    private func header(_ view: DaemonHome?) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom) {
                greeting
                Spacer(minLength: Memnox.Spacing.large)
                standing(view)
            }
            VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
                greeting
                standing(view)
            }
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
            Text(Self.greeting(setup.name))
                .font(.system(size: SettingsMetrics.pageTitleSize + 3, weight: .bold))
                .foregroundStyle(Memnox.Console.foreground)
                .accessibilityAddTraits(.isHeader)
            Text(Destinations.info(.home).subtitle)
                .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.Console.muted)
        }
    }

    @ViewBuilder private func standing(_ view: DaemonHome?) -> some View {
        // The last read decides, since a home kept from before outlives a runtime that stopped since.
        if home.unavailable {
            StatusWord(.bad, "The runtime is not answering")
        } else if let view, let mode = HomeMode(rawValue: view.mode) {
            StatusWord(mode == .enforce ? .good : .attention, mode.badge)
        } else if view != nil {
            StatusWord(.good, "Runtime protecting this Mac")
        }
    }

    /// "Hi Sam" with the first name once setup has one, else the name of the app.
    static func greeting(_ name: String) -> String {
        guard let first = name.split(whereSeparator: \.isWhitespace).first else { return "Memnox" }
        return "Hi \(first)"
    }
}
