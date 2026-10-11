import SwiftUI

/// The window's first page, where the person lands: a greeting, the home's five blocks once this Mac is set up, and
/// the setup checklist, which comes first until setup is finished.
struct OverviewPage: View {
    @ObservedObject var menu: MenuModel
    @ObservedObject var setup: SetupModel
    /// The team sign in, absent only before the app has built it.
    let team: TeamModel?
    /// The home's blocks, absent only before the app has built them.
    let home: HomeModel?
    let go: (SettingsPage) -> Void
    /// Which way the first run went, so the choice is offered once and the checklist takes its place after.
    @AppStorage(FirstRun.key) private var firstRun = ""

    private enum Layout {
        static let titleSize: CGFloat = 30
        static let keycapSpacing: CGFloat = 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xxLarge) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
                Text("Overview")
                    .font(Memnox.sans(Memnox.TextSize.footnote, .medium))
                    .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                Text(greeting)
                    .font(Memnox.display(Layout.titleSize))
                    .foregroundStyle(Memnox.Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("What waits on you, what your agents are doing, and what could run on its own.")
                    .font(Memnox.sans(Memnox.TextSize.body))
                    .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
            }
            Button(action: menu.talk) {
                HStack(spacing: Memnox.Spacing.small) {
                    Image(systemName: MenuSymbol.talk)
                    Text("Talk to Memnox")
                    HStack(spacing: Layout.keycapSpacing) {
                        Keycap(label: "\u{2325}")
                        Keycap(label: "Space")
                    }
                }
            }
            .buttonStyle(KitButton(kind: .secondary))
            .help("Or press Option Space from anywhere")
            if setup.isFinished { homeBlocks }
            if let team, !setup.isFinished, firstRun.isEmpty {
                FirstRunChoice(team: team) { path in
                    firstRun = path
                    if path == FirstRun.team { go(.team) }
                }
            } else {
                SetupProgressCard(setup: setup, go: go)
            }
            if !setup.isFinished { homeBlocks }
        }
    }

    /// The home when the daemon gives one, and the session counts a runtime from before the home still answers.
    @ViewBuilder private var homeBlocks: some View {
        if let home { OverviewHome(home: home, overview: menu.overview) } else { OverviewNumbers(overview: menu.overview) }
    }

    private var greeting: String {
        let first = setup.name.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init)
        return first.map { "Hi \($0)" } ?? "Memnox"
    }
}

/// The two ways in on a first run, side by side, since somebody may be here only to answer their team.
enum FirstRun {
    static let key = "firstRunPath"
    static let thisMac = "mac"
    static let team = "team"
}

/// "Set up this Mac" beside "Join your team": the first walks the checklist for this Mac's own agents, the second
/// signs in to the workspace so teammates' calls reach the island before anything else here is set up.
private struct FirstRunChoice: View {
    @ObservedObject var team: TeamModel
    let chose: (String) -> Void

    private static let tracking: CGFloat = 1.2
    private static let symbolSize: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xLarge) {
            Text("Start here")
                .font(Memnox.sans(Memnox.TextSize.caption, .semibold))
                .tracking(Self.tracking)
                .textCase(.uppercase)
                .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
            HStack(alignment: .top, spacing: Memnox.Spacing.large) {
                path(
                    symbol: "laptopcomputer",
                    title: "Set up this Mac",
                    detail: "Your own agents, the voice, and Touch ID for what they ask.",
                    action: "Set up"
                ) { chose(FirstRun.thisMac) }
                path(
                    symbol: "person.3",
                    title: "Join your team",
                    detail: team.isSignedIn
                        ? "Signed in. Your teammates' calls come to the island."
                        : "Answer the calls your teammates' agents route to you, before setting up anything else.",
                    action: team.isSignedIn ? "Open Team" : "Join"
                ) {
                    if !team.isSignedIn { team.start() }
                    chose(FirstRun.team)
                }
            }
        }
        .padding(Memnox.Spacing.xxLarge)
        .surface()
    }

    private func path(symbol: String, title: String, detail: String, action: String, go: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            Image(systemName: symbol)
                .font(.system(size: Self.symbolSize, weight: .regular))
                .foregroundStyle(Memnox.Palette.ink)
                .accessibilityHidden(true)
            Text(title)
                .font(Memnox.sans(Memnox.TextSize.title, .semibold))
                .foregroundStyle(Memnox.Palette.ink)
            Text(detail)
                .font(Memnox.sans(Memnox.TextSize.body))
                .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action, action: go).buttonStyle(KitButton(kind: .primary))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Memnox.Spacing.xLarge)
        .surface()
    }
}

/// The console's "do this next" card: the first step still open with what it asks for, every step as a checklist
/// that opens its page, and Finish while the first run is still open.
private struct SetupProgressCard: View {
    @ObservedObject var setup: SetupModel
    let go: (SettingsPage) -> Void

    private static let tracking: CGFloat = 1.2
    private static let checklistSpacing: CGFloat = 10

    var body: some View {
        let steps = Self.steps(setup)
        let open = steps.first { $0.state != .done }
        let ready = steps.filter { $0.state == .done }.count
        VStack(alignment: .leading, spacing: Memnox.Spacing.xLarge) {
            HStack(alignment: .firstTextBaseline) {
                Text(open == nil ? "Set up" : "Do this next")
                    .font(Memnox.sans(Memnox.TextSize.caption, .semibold))
                    .tracking(Self.tracking)
                    .textCase(.uppercase)
                    .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                Spacer()
                Text("\(ready) of \(steps.count)")
                    .font(Memnox.sans(Memnox.TextSize.footnote).monospacedDigit())
                    .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
            }
            if let open {
                VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
                    Text(open.title)
                        .font(Memnox.sans(Memnox.TextSize.title, .semibold))
                        .foregroundStyle(Memnox.Palette.ink)
                    Text(open.hint)
                        .font(Memnox.sans(Memnox.TextSize.body))
                        .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Go to \(open.page.title)") { go(open.page) }
                    .buttonStyle(KitButton(kind: .primary))
            } else {
                Text("Everything is ready. Press Option Space from anywhere and ask about your agents.")
                    .font(Memnox.sans(Memnox.TextSize.body))
                    .foregroundStyle(Memnox.ink(Memnox.Ink.primary))
            }
            VStack(alignment: .leading, spacing: Self.checklistSpacing) {
                ForEach(steps, id: \.title) { step in
                    Button { go(step.page) } label: {
                        HStack(spacing: Memnox.Spacing.medium) {
                            SetupMark(state: step.state)
                            Text(step.title)
                                .font(Memnox.sans(Memnox.TextSize.body))
                                .foregroundStyle(Memnox.ink(step.state == .done ? Memnox.Ink.secondary : Memnox.Ink.primary))
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .help("Open \(step.page.title)")
                }
            }
            if !setup.isFinished {
                HStack {
                    Spacer()
                    Button("Finish setup") { setup.finish() }
                        .buttonStyle(KitButton(kind: .primary))
                        .disabled(setup.nameState != .done)
                        .help(setup.nameState == .done ? "Finish and hear Memnox say hello" : "Add your name first")
                }
            }
        }
        .padding(Memnox.Spacing.xxLarge)
        .surface()
    }

    /// Each setup step with the page it lives on and what to do when it is still open.
    private static func steps(_ setup: SetupModel) -> [OverviewStep] {
        [
            OverviewStep("Tell Memnox your name", setup.nameState, .profile, "So it greets you and speaks to you by name."),
            OverviewStep("Let it hear you", setup.listening, .profile, "Microphone and speech recognition, on this Mac only."),
            OverviewStep("Let it see and act", setup.seeing, .profile, "Read your screen when you ask, and check that what it sent landed."),
            OverviewStep("Start the Memnox daemon", setup.daemon, .connection, setup.daemonDetail),
            OverviewStep("Register Touch ID", setup.key, .connection, "Your finger approves anything outside a session's repository."),
            OverviewStep("Choose who answers for you", setup.agentsState, .voice, setup.agentsDetail),
            OverviewStep("Pick a voice", setup.voiceState, .voice, setup.voiceDetail),
        ]
    }
}

/// One setup step as the overview lists it: its title, where it stands, the page it lives on, and what to do.
private struct OverviewStep {
    let title: String
    let state: StepState
    let page: SettingsPage
    let hint: String

    init(_ title: String, _ state: StepState, _ page: SettingsPage, _ general: String) {
        self.title = title
        self.state = state
        self.page = page
        // A step that needs the person says what to do in place of the general line.
        if case .needs(let why) = state { hint = why } else { hint = general }
    }
}

/// The home's blocks, falling back to the session counts while the daemon has no home to give.
private struct OverviewHome: View {
    @ObservedObject var home: HomeModel
    let overview: MenuOverview

    var body: some View {
        if home.home == nil, home.unavailable {
            OverviewNumbers(overview: overview)
        } else {
            HomeBlocks(model: home)
        }
    }
}

/// The agents' numbers on one line at the foot of the overview, as the console keeps its own.
private struct OverviewNumbers: View {
    let overview: MenuOverview

    var body: some View {
        HStack(spacing: Memnox.Spacing.xxLarge) {
            number("Need you", overview.needYou, tint: nil)
            number("Working", overview.working, tint: nil)
            number("Agents", overview.agents, tint: nil)
            number("Repositories", overview.repositories, tint: nil)
            Spacer(minLength: 0)
        }
        .padding(.top, Memnox.Spacing.xSmall)
        .animation(.easeOut(duration: Memnox.Motion.standard), value: overview)
    }

    private func number(_ label: String, _ value: Int, tint: Color?) -> some View {
        HStack(spacing: Memnox.Spacing.small) {
            Text(label)
                .font(Memnox.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
            Text("\(value)")
                .font(Memnox.sans(Memnox.TextSize.callout, .semibold).monospacedDigit())
                .foregroundStyle(tint ?? Memnox.Palette.ink)
                .contentTransition(.numericText(value: Double(value)))
        }
        .accessibilityElement(children: .combine)
    }
}
