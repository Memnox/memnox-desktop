import MemnoxVoiceCore
import SwiftUI

/// Home answers three things before anything else: what is running, what needs the person, and where they can carry
/// on. No charts, and every number is a count the ledger can show. Until setup is done, the first run's checklist is
/// what Home has to say.
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
            HomeAtAGlance(shell: shell, home: home, island: island, name: setup.name, width: width)
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct HomeAtAGlance: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var home: HomeModel
    @ObservedObject var island: IslandModel
    let name: String
    let width: WidthClass

    private static let recentSessions = 5
    private static let tileWidth: CGFloat = 150
    private static let logo: CGFloat = 30
    private static let smallLogo: CGFloat = 26

    var body: some View {
        let running = island.cards.filter { $0.status.isActive }
        let recent = Array(island.cards.filter { !$0.status.isActive }.prefix(Self.recentSessions))
        let view = home.home
        ShellScroll(width: width) {
            header(view)
            if home.unavailable, view == nil { ReadFailed(what: "the runtime", retry: home.refresh) }
            tiles(running: running.count, view: view)
            runningSection(running)
            if let view {
                if let memory = shell.memory {
                    LearnWaiting(screen: memory) { HomeAttention(shell: shell, home: home, view: view, toConfirm: $0) }
                } else {
                    HomeAttention(shell: shell, home: home, view: view, toConfirm: 0)
                }
            }
            if !recent.isEmpty { carryOn(recent) }
            if let studio = shell.studio { HomeThisWeek(shell: shell, screen: studio) }
            if let view {
                Text(HomeLines.today(view.today))
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Console.muted)
            }
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
            Text("Your agents at a glance.")
                .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.Console.muted)
        }
    }

    @ViewBuilder private func standing(_ view: DaemonHome?) -> some View {
        if view != nil {
            StatusWord(.good, "Runtime protecting this Mac")
        } else if home.unavailable {
            StatusWord(.bad, "The runtime is not answering")
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
                 tone: running > 0 ? .good : .quiet) { shell.go(WindowRoute(.agents, tab: "sessions")) }
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

    private func runningSection(_ running: [SessionCard]) -> some View {
        ShellSection(title: "Running agents") {
            GoLink("All sessions") { shell.go(WindowRoute(.agents, tab: "sessions")) }
        } content: {
            if running.isEmpty {
                EmptyState(symbol: "sparkles", title: "Nothing is running right now",
                           detail: "Start Claude Code, Codex or any agent you use, and it appears here while it works.")
            } else {
                ShellPanel {
                    ForEach(Array(running.enumerated()), id: \.element.id) { index, card in
                        if index > 0 { ShellDivider() }
                        ShellRow(title: card.agentName,
                                 caption: [card.title, SessionReading.repository(card.repository)].compactMap { $0 }.joined(separator: " in "),
                                 action: { island.watchLive(card.sessionId, card.host) }) {
                            BrandLogo(agent: card.agent, name: card.agentName, size: Self.logo)
                        } trailing: {
                            StatusWord(.good, card.status.label)
                        }
                        .help("Watch \(card.agentName) live")
                    }
                }
            }
        }
    }

    private func carryOn(_ recent: [SessionCard]) -> some View {
        ShellSection(title: "Carry on") {
            ShellPanel {
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, card in
                    if index > 0 { ShellDivider() }
                    ShellRow(title: card.title,
                             caption: [card.agentName, SessionReading.repository(card.repository), SessionText.ago(card.lastActive, now: Date())]
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

/// Everything that waits on the person, in one place to clear, and nothing when nothing waits. The buttons are the
/// home's own, so a press here does what the same press does on the overview.
private struct HomeAttention: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var home: HomeModel
    let view: DaemonHome
    /// What waits in Learn, counted past the ones the queue listed.
    let toConfirm: Int

    private static let icon: CGFloat = 16

    var body: some View {
        let needs = view.needsYou ?? []
        let nothing = view.waiting == 0 && needs.isEmpty && view.ready == nil && view.notCovered.unprotected == 0 && toConfirm == 0
        if !nothing {
            ShellSection(title: "Needs your attention") {
                VStack(alignment: .leading, spacing: Memnox.Spacing.regular) {
                    ShellPanel { rows(needs) }
                    if let note = home.handOverNote { quiet(note) }
                    if let why = home.protectFailed { quiet(why) }
                    if view.waiting > 0 {
                        GoLink("See every approval") { shell.go(WindowRoute(.governance, tab: "approvals")) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func rows(_ needs: [String]) -> some View {
        if view.waiting > 0 {
            ShellRow(title: HomeLines.waiting(view.waiting)) {
                icon("hand.raised", Memnox.Console.warm)
            } trailing: {
                Button("Answer", action: home.openWaiting)
                    .buttonStyle(KitButton(kind: .secondary))
                    .help("Open the waiting calls on the island")
            }
        }
        ForEach(Array(needs.enumerated()), id: \.offset) { index, line in
            if index > 0 || view.waiting > 0 { ShellDivider() }
            ShellRow(title: line) { icon("exclamationmark.circle", Memnox.Console.warm) } trailing: { EmptyView() }
        }
        if toConfirm > 0 {
            if view.waiting > 0 || !needs.isEmpty { ShellDivider() }
            ShellRow(title: MemoryLines.learnWaitingLine(toConfirm),
                     caption: "What your agent read from your sources, and what agents suggested, counts only once you confirm it.") {
                icon("graduationcap", Memnox.Console.warm)
            } trailing: {
                Button("Open Learn") { shell.go(WindowRoute(.governance, tab: "learn")) }.buttonStyle(KitButton(kind: .secondary))
            }
        }
        if let ready = view.ready {
            if view.waiting > 0 || !needs.isEmpty || toConfirm > 0 { ShellDivider() }
            ShellRow(title: HomeLines.ready(ready), caption: ready.because) {
                icon("arrow.right", Memnox.Console.primary)
            } trailing: {
                Button(home.handingOver ? "Proposing" : "Let it run on its own") { home.handOver(ready) }
                    .buttonStyle(KitButton(kind: .primary))
                    .disabled(home.handingOver)
                    .help("Proposes an allow rule for exactly these; nothing changes until you confirm it with Touch ID")
            }
        }
        if view.notCovered.unprotected > 0 {
            if view.waiting > 0 || !needs.isEmpty || toConfirm > 0 || view.ready != nil { ShellDivider() }
            ShellRow(title: HomeLines.notCovered(view.notCovered).first ?? "",
                     caption: home.remote() ? "Run memnox setup on that server to put them under Memnox." : nil) {
                icon("shield", Memnox.Console.warm)
            } trailing: {
                // The button runs this Mac's own memnox, which cannot reach a server's agents.
                if !home.remote() {
                    Button(home.protecting ? "Protecting" : "Protect my agents", action: home.protect)
                        .buttonStyle(KitButton(kind: .primary))
                        .disabled(home.protecting)
                        .help("Hooks every agent found on this Mac into Memnox, the way setup does")
                }
            }
        }
    }

    private func icon(_ symbol: String, _ tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: Self.icon, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: Self.icon + 4)
            .accessibilityHidden(true)
    }

    private func quiet(_ text: String) -> some View {
        Text(text)
            .font(Memnox.Console.sans(Memnox.TextSize.footnote))
            .foregroundStyle(Memnox.Console.muted)
            .fixedSize(horizontal: false, vertical: true)
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
