import Combine
import MemnoxVoiceCore
import SwiftUI

/// Home's getting started steps, drawn the way the cloud console's home draws its ladder: the stage this Mac is at and
/// how many steps are done, the one thing to do next with its press, what waits on an agent, the rest of the steps
/// under their two tracks, and the counts already won. Every tick is a count the runtime or this Mac reports, read
/// again on opening; the block goes once every step is done, and folds to one line while the person hides it.
struct HomeStart: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var tools: ToolsModel
    @ObservedObject var menu: MenuModel
    /// The home's own presses, so Turn on stopping asks the runtime and shows what it came to here.
    @ObservedObject var home: HomeModel
    /// What the runtime's home said today, and whether it observes or enforces; zero and nil before it answered.
    let actions: Int
    let mode: HomeMode?
    @AppStorage(Self.hiddenKey) private var hidden = false
    @StateObject private var reads = StartReads()

    /// Remembered, so a person who hid it is not shown it again on every opening.
    static let hiddenKey = "memnox.home.startHidden"

    private enum Layout {
        static let padding: CGFloat = 20
        static let trackMinimum: CGFloat = 280
    }

    var body: some View {
        let setup = HomeSteps.setup(standing)
        Group {
            if setup.climbed {
                EmptyView()
            } else if hidden {
                folded(setup)
            } else {
                VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
                    header(setup)
                    if let next = setup.next { NextRung(step: next, busy: next.id == .enforce && home.enforcing) { press(next) } }
                    if let note = home.enforceNote {
                        Text(note)
                            .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
                            .foregroundStyle(Memnox.Console.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    ForEach(setup.waiting) { WaitingRung(step: $0) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: Layout.trackMinimum), spacing: Memnox.Spacing.xLarge, alignment: .top)],
                              alignment: .leading, spacing: Memnox.Spacing.xLarge) {
                        ForEach(HomeTrack.allCases, id: \.self) { track in
                            TrackList(track: track, steps: setup.rest(of: track)) { id in
                                if let step = setup.steps.first(where: { $0.id == id }) { press(step) }
                            }
                        }
                    }
                    Standing(counts: setup.standing)
                }
                .padding(Layout.padding)
                .background(Memnox.Console.card, in: RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous)
                    .strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("What to do next")
            }
        }
        .consoleSheet(isPresented: $home.askingEnforce) {
            ConsoleConfirm(symbol: "hand.raised", title: HomeEnforce.title, message: HomeEnforce.message,
                           detail: HomeEnforce.detail, confirm: HomeEnforce.confirm, destructive: false,
                           aside: HomeEnforce.readFirst,
                           asideAct: {
                               home.askingEnforce = false
                               shell.go(Self.route(.enforce))
                           },
                           cancel: { home.askingEnforce = false },
                           act: {
                               home.askingEnforce = false
                               home.enforce()
                           })
        }
        .onAppear { reads.follow(shell) }
        .task {
            tools.refresh()
            reads.follow(shell)
            await shell.studio?.studio.refresh()
            await shell.memory?.memory.refreshSources()
            await shell.agents?.agents.refresh()
            await shell.skills?.skills.refresh()
            await shell.hub?.hub.refresh()
        }
    }

    /// Every count the steps are read off, taken from the screens that already hold them.
    private var standing: HomeStanding {
        let _ = reads.tick
        let agents = shell.agents?.agents.agents ?? []
        var standing = HomeStanding()
        standing.agents = agents.count
        standing.agentsProtected = agents.filter { $0.agentStatus != .unprotected }.count
        standing.rulesInForce = shell.studio?.studio.rules?.rules.count ?? 0
        // Today's count resets at midnight, so the agents' own recent actions keep the step ticked the morning after.
        standing.actionsRecorded = max(actions, agents.reduce(0) { $0 + $1.recent.count })
        standing.phonesPaired = menu.devices.filter { $0.revokedAt == nil }.count
        standing.mode = mode
        standing.appsConnected = ScanLines.reachable(tools.yourApps).count
        standing.sourcesLinked = shell.memory?.memory.sources?.count ?? 0
        standing.skillsShared = shell.skills?.skills.hub?.skills.count ?? 0
        standing.serversShared = shell.hub?.hub.hub?.servers.count ?? 0
        return standing
    }

    /// The block put away: one line with the stage and the steps done, and Show to open it again.
    private func folded(_ setup: HomeSetup) -> some View {
        HStack(alignment: .center, spacing: Memnox.Spacing.large) {
            Text(setup.stage.label)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                .foregroundStyle(Memnox.Console.foreground)
            Spacer(minLength: Memnox.Spacing.medium)
            StepsDone(setup: setup)
            toggle
        }
        .padding(.horizontal, Layout.padding)
        .padding(.vertical, Memnox.Spacing.large)
        .background(Memnox.Console.card, in: RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous)
            .strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("What to do next, hidden")
    }

    /// Hide and Show are one press, so the steps fold to a line and open again from it.
    private var toggle: some View {
        Button(hidden ? "Show" : "Hide") { withAnimation(.easeOut(duration: Memnox.Motion.quick)) { hidden.toggle() } }
            .buttonStyle(KitButton(kind: .secondary))
            .help(hidden ? "Show the steps again" : "Fold these steps to one line until you want them again")
    }

    /// The stage and what it means, the steps done, and the way to put the block away.
    private func header(_ setup: HomeSetup) -> some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
            HStack(alignment: .center, spacing: Memnox.Spacing.large) {
                Text(setup.stage.label)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.base, .medium))
                    .foregroundStyle(Memnox.Console.foreground)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Memnox.Spacing.medium)
                StepsDone(setup: setup)
                toggle
            }
            Text(setup.stage.means)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
                .foregroundStyle(Memnox.Console.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A step's press: stopping rather than watching is confirmed here first, every other step opens where it is done.
    private func press(_ step: HomeStep) {
        if step.id == .enforce, !step.done {
            home.askingEnforce = true
        } else {
            shell.go(Self.route(step.id))
        }
    }

    /// Where each step's press goes in the window; for stopping, that is the record it is read off.
    static func route(_ step: HomeStepID) -> WindowRoute {
        switch step {
        case .protectAgents: return WindowRoute(.agents, tab: "agents")
        case .rulesInForce: return WindowRoute(.rules, tab: "rules")
        case .actionsRecorded, .enforce: return WindowRoute(.activity, tab: "timeline")
        case .answerAway: return WindowRoute(.settings, tab: "phones")
        case .connectApps: return WindowRoute(.connectors, tab: "systems")
        case .linkSource: return WindowRoute(.connectors, tab: "files")
        case .shareSkills: return WindowRoute(.memory, tab: "skills")
        }
    }
}

/// How far along the steps are, as a thin ring filling in the console's blue beside "3 of 8 done" in the console's
/// sans, centred on the Hide button beside it.
private struct StepsDone: View {
    let setup: HomeSetup

    private enum Layout {
        static let ring: CGFloat = 14
        static let line: CGFloat = 2
        /// A ring's stroke starts at three o'clock, so it is turned back a quarter to fill from the top.
        static let fromTop: Double = -90
    }

    var body: some View {
        let share = setup.total == 0 ? 0 : CGFloat(setup.completed) / CGFloat(setup.total)
        HStack(spacing: Memnox.Spacing.small) {
            ZStack {
                Circle().stroke(Memnox.Console.panelEdge, lineWidth: Layout.line)
                Circle()
                    .trim(from: 0, to: share)
                    .stroke(Memnox.Console.primary, style: StrokeStyle(lineWidth: Layout.line, lineCap: .round))
                    .rotationEffect(.degrees(Layout.fromTop))
            }
            .frame(width: Layout.ring, height: Layout.ring)
            Text(HomeSteps.progress(setup))
                .font(Memnox.Console.sans(Memnox.Console.TextSize.meta, .medium))
                .foregroundStyle(Memnox.Console.muted)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(setup.completed) of \(setup.total) steps done")
    }
}

/// Redraws the steps whenever any screen they count off changes, since those screens are optional and cannot be
/// observed directly from the view.
@MainActor
private final class StartReads: ObservableObject {
    @Published private(set) var tick = 0
    private var following: Set<AnyCancellable> = []

    func follow(_ shell: AppShellModel) {
        following = []
        let screens: [ObservableObjectPublisher?] = [shell.agents?.objectWillChange, shell.studio?.objectWillChange,
                                                     shell.memory?.objectWillChange, shell.skills?.objectWillChange,
                                                     shell.hub?.objectWillChange]
        for screen in screens.compactMap({ $0 }) {
            screen.sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.tick += 1 }
            }
            .store(in: &following)
        }
    }
}

/// The one thing to do now, and the only part of the block with a filled press, as the cloud's Do this next rung.
private struct NextRung: View {
    let step: HomeStep
    /// True while the press is under way, so it waits rather than being pressed twice.
    var busy = false
    let press: () -> Void

    private enum Layout {
        static let edge = 0.3
        static let wash = 0.05
        static let tracking: CGFloat = 1.8
        static let padding: CGFloat = 16
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
            Text("DO THIS NEXT")
                .font(Memnox.mono(Memnox.Console.TextSize.label, .medium))
                .tracking(Layout.tracking)
                .foregroundStyle(Memnox.Console.primary)
            Text(step.title)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.base, .medium))
                .foregroundStyle(Memnox.Console.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Text(step.value)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
                .foregroundStyle(Memnox.Console.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text(step.how)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
                .foregroundStyle(Memnox.Console.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.top, Memnox.Spacing.xSmall)
            Button(action: press) {
                HStack(spacing: Memnox.Spacing.small) {
                    Text(step.action)
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(KitButton(kind: .primary))
            .disabled(busy)
            .padding(.top, Memnox.Spacing.small)
        }
        .padding(Layout.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Memnox.Console.primary.opacity(Layout.wash), in: shape)
        .overlay(shape.strokeBorder(Memnox.Console.primary.opacity(Layout.edge), lineWidth: Memnox.Stroke.hairline))
    }
}

/// A step nobody can hurry, drawn quietly as a state rather than a task: no accent and no press, only what it awaits.
private struct WaitingRung: View {
    let step: HomeStep

    private static let padding: CGFloat = 16

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous)
        HStack(alignment: .top, spacing: Memnox.Spacing.medium) {
            Image(systemName: "clock")
                .font(.system(size: Memnox.Console.TextSize.bodySmall))
                .foregroundStyle(Memnox.Console.muted)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                Text(HomeSteps.waitingLabel)
                    .font(Memnox.mono(Memnox.Console.TextSize.label, .medium))
                    .foregroundStyle(Memnox.Console.muted)
                Text(step.title)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                    .foregroundStyle(Memnox.Console.foreground)
                Text(HomeSteps.waitingMeans)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                    .foregroundStyle(Memnox.Console.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Self.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(shape.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
    }
}

/// The rest of one track as a list with a tick or an open ring, each step a press to where it is done.
private struct TrackList: View {
    let track: HomeTrack
    let steps: [HomeStep]
    let open: (HomeStepID) -> Void

    private static let mark: CGFloat = 14

    var body: some View {
        if !steps.isEmpty {
            VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
                Text(track.label)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                    .foregroundStyle(Memnox.Console.foreground)
                Text(track.lead)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                    .foregroundStyle(Memnox.Console.muted)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
                    ForEach(steps) { step in
                        Button { open(step.id) } label: {
                            HStack(alignment: .top, spacing: Memnox.Spacing.small) {
                                Image(systemName: step.done ? "checkmark" : "circle")
                                    .font(.system(size: Self.mark, weight: step.done ? .semibold : .regular))
                                    .foregroundStyle(step.done ? Memnox.Console.primary : Memnox.Console.faint)
                                    .frame(width: Self.mark)
                                    .accessibilityHidden(true)
                                Text(step.title)
                                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
                                    .foregroundStyle(step.done ? Memnox.Console.muted : Memnox.Console.foreground)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                        .help(step.value)
                        .accessibilityLabel("\(step.title), \(step.done ? "done" : "not yet")")
                    }
                }
                .padding(.top, Memnox.Spacing.xSmall)
            }
        }
    }
}

/// What was won beside what is left: only the counts above zero, each a count this Mac took, never an estimate.
private struct Standing: View {
    let counts: [HomeCount]

    /// Wide enough for the longest label and its count, when the counts wrap onto rows.
    private static let countMinimum: CGFloat = 140

    var body: some View {
        if !counts.isEmpty {
            VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
                KitDivider()
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Memnox.Spacing.xLarge) { items }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.countMinimum), alignment: .leading)],
                              alignment: .leading, spacing: Memnox.Spacing.small) { items }
                }
            }
        }
    }

    private var items: some View {
        ForEach(counts, id: \.label) { count in
            HStack(alignment: .firstTextBaseline, spacing: Memnox.Spacing.xSmall) {
                Text(count.label)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                    .foregroundStyle(Memnox.Console.muted)
                Text("\(count.count)")
                    .font(Memnox.mono(Memnox.Console.TextSize.bodySmall, .medium))
                    .foregroundStyle(Memnox.Console.foreground)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
