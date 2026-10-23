import SwiftUI

/// The window's first page, where the person lands: a greeting with the two keys, the setup checklist until setup is
/// finished, the numbers in one row, what the agents are doing, then the latest dictations.
struct OverviewPage: View {
    @ObservedObject var menu: MenuModel
    @ObservedObject var setup: SetupModel
    /// The person's sign in, absent only before the app has built it.
    let account: AccountModel?
    /// The home's blocks, absent only before the app has built them.
    let home: HomeModel?
    /// The person's dictations, absent only before the app has built them.
    let dictations: DictationStore?
    let go: (SettingsPage) -> Void
    /// Which way the first run went, so the choice is offered once and the checklist takes its place after.
    @AppStorage(FirstRun.key) private var firstRun = ""

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.pageSpacing) {
            OverviewHero(name: firstName, talk: menu.talk)
            if !setup.isFinished { setupBlocks }
            OverviewStats(overview: menu.overview, store: dictations)
            if let home { OverviewHome(home: home, overview: menu.overview) }
            if let dictations { RecentDictations(store: dictations) }
        }
    }

    /// Before setup is finished: the first run's choice, then the checklist of what is left.
    @ViewBuilder private var setupBlocks: some View {
        if let account, firstRun.isEmpty {
            FirstRunChoice(account: account) { path in
                firstRun = path
                if path == FirstRun.account { go(.account) }
            }
        } else {
            SetupProgressCard(setup: setup, go: go)
        }
    }

    /// The first name only, as a person is greeted; nil before setup has one.
    private var firstName: String? {
        setup.name.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init)
    }
}

/// The two ways in on a first run, side by side, since somebody may be here only to answer what is routed to them.
enum FirstRun {
    static let key = "firstRunPath"
    static let thisMac = "mac"
    /// Still stored as "team", so a choice made before the page was renamed resolves the same way.
    static let account = "team"
}

/// "Set up this Mac" over "Sign in", as two of Vorssaint's rows: the first walks the checklist for this Mac's own
/// agents, the second signs in to the workspace so the calls routed to the person reach the island first.
private struct FirstRunChoice: View {
    @ObservedObject var account: AccountModel
    let chose: (String) -> Void

    var body: some View {
        SettingsSection(title: "Start here") {
            SettingsCard {
                SettingsRow(symbol: "laptopcomputer", title: "Set up this Mac",
                            caption: "Your own agents, the voice, and Touch ID for what they ask.") {
                    Button("Set up") { chose(FirstRun.thisMac) }.buttonStyle(KitButton(kind: .primary))
                }
                SettingsDivider()
                SettingsRow(symbol: "person.crop.circle.badge.checkmark", title: "Sign in",
                            caption: account.isSignedIn
                                ? "Signed in. What your workspace routes to you comes to the notch."
                                : "Answer what your workspace routes to you, from the notch, before setting up anything else.") {
                    Button(account.isSignedIn ? "Open Account" : "Sign in") {
                        if !account.isSignedIn { account.start() }
                        chose(FirstRun.account)
                    }
                    .buttonStyle(KitButton(kind: .secondary))
                }
            }
        }
    }
}

/// The console's "do this next" card in Vorssaint's rows: the first step still open with its button, then every
/// step as a row that opens its page, and Finish while the first run is still open.
private struct SetupProgressCard: View {
    @ObservedObject var setup: SetupModel
    let go: (SettingsPage) -> Void

    private static let chevron = "chevron.right"
    private static let chevronSize: CGFloat = 11
    private static let checklistRowHeight: CGFloat = 32

    var body: some View {
        let steps = Self.steps(setup)
        let open = steps.first { $0.state != .done }
        let ready = steps.filter { $0.state == .done }.count
        SettingsSection(title: open == nil ? "Set up" : "Do this next") {
            Text("\(ready) of \(steps.count)")
                .font(.system(size: SettingsMetrics.captionSize).monospacedDigit())
                .foregroundStyle(Memnox.Palette.muted)
        } content: {
            SettingsCard {
                if let open {
                    SettingsRow(symbol: "arrow.forward.circle", title: open.title, caption: open.hint) {
                        Button("Go to \(open.page.title)") { go(open.page) }.buttonStyle(KitButton(kind: .primary))
                    }
                } else {
                    SettingsRow(symbol: "checkmark.circle", title: "Everything is ready",
                                caption: "Press Option Space from anywhere and ask about your agents.", tint: Memnox.Palette.success)
                }
                SettingsDivider(full: true)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(steps, id: \.title) { step in checklistRow(step) }
                }
                if !setup.isFinished {
                    SettingsDivider(full: true)
                    HStack {
                        Text(setup.nameState == .done ? "Finish and hear Memnox say hello." : "Add your name first, then finish.")
                            .font(.system(size: SettingsMetrics.captionSize))
                            .foregroundStyle(Memnox.Palette.muted)
                        Spacer()
                        // The card's one primary is the open step; Finish takes it over once nothing is left.
                        Button("Finish setup") { setup.finish() }
                            .buttonStyle(KitButton(kind: open == nil ? .primary : .secondary))
                            .disabled(setup.nameState != .done)
                    }
                }
            }
        }
    }

    private func checklistRow(_ step: OverviewStep) -> some View {
        Button { go(step.page) } label: {
            HStack(spacing: Memnox.Spacing.medium) {
                SetupMark(state: step.state)
                Text(step.title)
                    .font(.system(size: SettingsMetrics.rowTextSize))
                    .foregroundStyle(step.state == .done ? Memnox.Palette.muted : Memnox.Palette.foreground)
                Spacer(minLength: 0)
                Text(step.page.title)
                    .font(.system(size: SettingsMetrics.captionSize))
                    .foregroundStyle(Memnox.Palette.faint)
                Image(systemName: Self.chevron)
                    .font(.system(size: Self.chevronSize, weight: .semibold))
                    .foregroundStyle(Memnox.Palette.faint)
            }
            .frame(height: Self.checklistRowHeight)
            .contentShape(Rectangle())
            .hoverLight()
        }
        .buttonStyle(.plain)
        .help("Open \(step.page.title)")
        // One spoken line per step, so VoiceOver says where it stands and where it leads.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(step.title), \(step.state == .done ? "done" : "not done yet")")
        .accessibilityHint("Opens \(step.page.title)")
    }

/// Each setup step with the page it lives on and what to do when it is still open.
    private static func steps(_ setup: SetupModel) -> [OverviewStep] {
        [
            OverviewStep("Tell Memnox your name", setup.nameState, .account, "So it greets you and speaks to you by name."),
            OverviewStep("Let it hear you", setup.listening, .permissions, "Microphone and speech recognition, on this Mac only."),
            OverviewStep("Let it type for you", setup.typing, .permissions, "Type what you confirm into your agents, and read back that it landed."),
            OverviewStep("Let it see your screen", setup.seeing, .permissions, "Read the window you ask about, and check that what it sent landed."),
            OverviewStep("Start the Memnox service", setup.daemon, .connection, setup.daemonDetail),
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
