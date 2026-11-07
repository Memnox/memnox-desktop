import MemnoxVoiceCore
import SwiftUI

/// Home is the one page the window opens on: the greeting, the getting started steps, then what Today showed in the
/// console's home order. No charts, and every number is a count the ledger can show. Until setup is done, the first
/// run's checklist is what Home has to say.
struct HomeDestination: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var menu: MenuModel
    @ObservedObject var setup: SetupModel
    @ObservedObject var island: IslandModel
    @ObservedObject var models: SettingsModels
    let width: WidthClass

    var body: some View {
        if !setup.isFinished {
            SettingsPageColumn {
                OverviewPage(menu: menu, setup: setup, account: models.account, home: models.home,
                             dictations: models.dictations, go: { shell.go(page: $0) })
            }
        } else if let home = models.home {
            HomeAtAGlance(shell: shell, home: home, island: island, menu: menu, name: setup.name, width: width)
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
    let name: String
    let width: WidthClass

    private static let recentSessions = 5
    private static let tileWidth: CGFloat = 150
    private static let smallLogo: CGFloat = 26

    var body: some View {
        let recent = Array(island.cards.filter { !$0.status.isActive }.prefix(Self.recentSessions))
        let view = home.home
        TodayDestination(shell: shell, island: island, home: home, agents: shell.agents, activity: shell.todayActivity, width: width) {
            header(view)
            if home.unavailable { ReadFailed(what: "the runtime", retry: home.refresh) }
            // The getting started steps, as the cloud console's home lists them, above the blocks until every one is done.
            HomeStart(shell: shell, tools: menu.tools, menu: menu, home: home, actions: view?.today.actions ?? 0,
                      mode: view.flatMap { HomeMode(rawValue: $0.mode) })
        } waitingFoot: {
            // Learn is left off for now, so Home offers no row that opens it.
            EmptyView()
        } trail: {
            // The count tiles and This week are left off for now, so Home reads straight down its blocks.
            if !recent.isEmpty { carryOn(recent) }
        }
        .task {
            home.refresh()
            // A runtime that does not answer progress yet leaves the week out rather than asking on every opening.
            if let studio = shell.studio, shell.supports("progress") != false { await studio.studio.refresh() }
            if let memory = shell.memory, shell.supports("memory-learn") != false { await memory.memory.refreshLearn() }
        }
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
            Text(Self.greeting(name))
                .font(.system(size: SettingsMetrics.pageTitleSize + 3, weight: .bold))
                .foregroundStyle(Memnox.Console.foreground)
                .accessibilityAddTraits(.isHeader)
            Text("What your agents can do on their own, and what still needs you.")
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

    private func tiles(running: Int, view: DaemonHome?) -> some View {
        let waiting = view?.waiting ?? 0
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.tileWidth), spacing: Memnox.Spacing.large)],
                         spacing: Memnox.Spacing.large) {
            tile(running, running == 1 ? "Agent working" : "Agents working", symbol: "bolt",
                 tone: running > 0 ? .good : .quiet) { shell.go(WindowRoute(.agents, tab: "list")) }
            tile(view?.today.actions ?? 0, "Actions today", symbol: "checklist", tone: .quiet, open: nil)
            tile(waiting, "Waiting on you", symbol: "hand.raised", tone: waiting > 0 ? .attention : .quiet) {
                shell.go(WindowRoute(.governance, tab: "approvals"))
            }
        }
    }

    @ViewBuilder
    private func tile(_ value: Int, _ label: String, symbol: String, tone: Tone, open: (() -> Void)?) -> some View {
        let face = StatTile(value: value, label: label, symbol: symbol, tint: tone == .quiet ? Memnox.Console.faint : tone.color)
        if let open {
            Button(action: open) { face.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .pointingHand()
                .accessibilityLabel("\(value) \(label)")
                .accessibilityAddTraits(.isButton)
        } else {
            face
        }
    }

    /// The projects on this computer, which name where each session ran.
    private var projects: [ProjectView] { shell.projects?.projects.projects ?? [] }

    private func carryOn(_ recent: [SessionCard]) -> some View {
        ShellSection(title: "Carry on") {
            ShellPanel {
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, card in
                    if index > 0 { ShellDivider() }
                    ShellRow(title: card.title,
                             caption: [card.agentName, ProjectContext.inLine(ProjectContext.projectName(repository: card.repository, projects: projects)),
                                       SessionText.ago(card.lastActive, now: Date())]
                                .compactMap { $0 }.joined(separator: SessionText.separator),
                             action: { island.watchLive(card.sessionId, card.host) }) {
                        BrandLogo(agent: card.agent, name: card.agentName, size: Self.smallLogo)
                    } trailing: {
                        EmptyView()
                    }
                }
            }
        }
    }
}

/// The week in counts, never hours saved, and the way to what could run on its own; nothing until progress is read.
private struct HomeThisWeek: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var screen: StudioScreen

    var body: some View {
        if let progress = screen.studio.progress {
            ShellSection(title: "This week") {
                GoLink("What could run on its own") { shell.go(WindowRoute(.governance, tab: "policies")) }
            } content: {
                Text(StudioLines.thisWeek(progress))
                    .font(Memnox.Console.sans(Memnox.TextSize.body))
                    .foregroundStyle(Memnox.Console.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// What waits in Learn, as one row under Waiting on you, and nothing while nothing waits there.
private struct LearnRow: View {
    @ObservedObject var shell: AppShellModel
    let toConfirm: Int

    private static let icon: CGFloat = 16

    var body: some View {
        if toConfirm > 0 {
            ShellPanel {
                ShellRow(title: MemoryLines.learnWaitingLine(toConfirm),
                         caption: "What your agent read from your sources, and what agents suggested, counts only once you confirm it.") {
                    Image(systemName: "graduationcap")
                        .font(.system(size: Self.icon, weight: .medium))
                        .foregroundStyle(Memnox.Console.warm)
                        .frame(width: Self.icon + 4)
                        .accessibilityHidden(true)
                } trailing: {
                    Button("Open Learn") { shell.go(WindowRoute(.governance, tab: "learn")) }.buttonStyle(KitButton(kind: .secondary))
                }
            }
        }
    }
}

/// Hands Home the count waiting in Learn, drawn again whenever the queue changes.
private struct LearnWaiting<Content: View>: View {
    @ObservedObject var screen: MemoryScreen
    @ViewBuilder let content: (Int) -> Content

    var body: some View {
        let queue = screen.memory.learn
        content(queue.map { $0.items.count + $0.more } ?? 0)
    }
}
