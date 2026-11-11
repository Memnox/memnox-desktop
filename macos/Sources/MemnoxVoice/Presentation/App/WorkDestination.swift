import AppKit
import MemnoxVoiceCore
import SwiftUI

/// Agent work under AI agents: each piece joined to the issue where it lives, with its link, where it stands and the
/// latest word from its agent. A person starts, stops and closes it and answers a handoff; each press is an unsigned
/// steer to the daemon, which decides, and the issue itself stays in its tracker.
struct WorkDestination: View {
    @ObservedObject var screen: AgentWorkScreen
    /// The jobs a person can point at an issue, nil where this Mac's runtime keeps none.
    let profiles: ProfilesScreen?
    let width: WidthClass
    @State private var starting = false

    var body: some View {
        page
            .task {
                await screen.desk.refresh()
                await profiles?.profiles.refresh()
            }
            .consoleSheet(isPresented: $starting) {
                StartWorkSheet(screen: screen, profiles: profiles?.profiles.profiles ?? []) { starting = false }
            }
    }

    @ViewBuilder private var page: some View {
        let desk = screen.desk
        if let all = desk.work {
            let names = WorkNames(profiles?.profiles.profiles ?? [])
            ShellScroll(width: width) {
                NoteBanner(text: screen.note)
                HStack(alignment: .top, spacing: Memnox.Spacing.regular) {
                    QuietLine("The issue stays in Linear, Jira, GitHub or Asana. Memnox keeps only which agent carries it and what it said.")
                    Spacer(minLength: Memnox.Spacing.medium)
                    Button { starting = true } label: { Label("Start work", systemImage: "plus") }
                        .buttonStyle(KitButton(kind: .primary))
                }
                let open = AgentWorkLines.open(all)
                if open.isEmpty {
                    EmptyState(symbol: "checklist", title: "No agent is on any work",
                               detail: "Start work to point one of your agents at an issue, such as LIN-123, or paste its link.")
                } else {
                    ShellSection(title: "Open \u{00B7} \(open.count)") {
                        VStack(spacing: Memnox.Spacing.large) {
                            ForEach(open) { AgentWorkCard(screen: screen, work: $0, names: names) }
                        }
                    }
                }
                let finished = AgentWorkLines.finished(all)
                if !finished.isEmpty {
                    ShellSection(title: "Finished \u{00B7} \(finished.count)") {
                        ShellPanel {
                            ForEach(Array(finished.enumerated()), id: \.element.id) { index, work in
                                if index > 0 { ShellDivider() }
                                WorkLine(work: work).padding(.horizontal, ShellMetrics.rowPaddingH).padding(.vertical, ShellMetrics.rowPaddingV)
                            }
                        }
                    }
                }
            }
        } else if desk.unreadable {
            ShellScroll(width: width) { ReadFailed(what: "the agent work") { Task { await desk.refresh() } } }
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// A profile's name by its id, so a card says which agent carries the work rather than an id.
struct WorkNames {
    private let names: [String: String]

    init(_ profiles: [ProfileView]) {
        names = Dictionary(profiles.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    func name(_ id: String) -> String? { names[id] }
}

/// One piece of open work, with the presses it offers: Accept and Decline on a handoff, Confirm on a done claim, and
/// Stop at any point. None is signed, since each only points or stops an agent.
struct AgentWorkCard: View {
    @ObservedObject var screen: AgentWorkScreen
    let work: AgentWork
    let names: WorkNames

    /// The agent by its job's name, who answers for it, and the tracker; a blank responsible person is left out.
    private var facts: [(String, String)] {
        var facts: [(String, String)] = [("Agent", AgentWorkLines.agentName(work, profileName: names.name))]
        if let responsible = AgentWorkLines.filled(work.responsiblePerson) { facts.append(("Answers to", responsible)) }
        facts.append(("Tracker", AgentWorkLines.trackerName(work.target.source)))
        return facts
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
        let busy = screen.desk.busy != nil
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            WorkLine(work: work)
            FactList(facts: facts)
            if let handoff = work.waitingHandoff {
                Text(AgentWorkLines.handoffLine(handoff, profileName: names.name))
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Console.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Memnox.Spacing.medium) {
                if let handoff = work.waitingHandoff {
                    Button("Accept") { press { await screen.desk.answer(handoff.id, .accept) } }.buttonStyle(KitButton(kind: .primary))
                    Button("Decline") { press { await screen.desk.answer(handoff.id, .decline) } }.buttonStyle(KitButton(kind: .secondary))
                } else if work.workStatus == .doneClaimed {
                    Button("Confirm") { press { await screen.desk.close(work.id) } }
                        .buttonStyle(KitButton(kind: .primary))
                        .help("Closes it as done, once you checked what the agent says it did")
                } else {
                    Button("Close as done") { press { await screen.desk.close(work.id) } }.buttonStyle(KitButton(kind: .secondary))
                }
                // Set apart, so stopping an agent is never pressed by a slip.
                Spacer(minLength: Memnox.Spacing.xxLarge)
                Button("Stop") { press { await screen.desk.stop(work.id) } }.buttonStyle(KitButton(kind: .secondary))
            }
            .disabled(busy)
        }
        .padding(Memnox.Spacing.xLarge)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Memnox.Console.card, in: shape)
        .overlay(shape.strokeBorder(AgentWorkLines.needsYou(work) ? Memnox.Console.warm.opacity(Self.attentionEdge) : Memnox.Console.panelEdge,
                                    lineWidth: Memnox.Stroke.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AgentWorkLines.issue(work))
    }

    private static let attentionEdge = 0.55

    private func press(_ action: @escaping () async -> WorkOutcome) {
        Task { screen.said(await action()) }
    }
}

/// Pointing a job's agent at an issue: the job, the key or link pasted as it is, and an optional title and folder.
private struct StartWorkSheet: View {
    @ObservedObject var screen: AgentWorkScreen
    let profiles: [ProfileView]
    let close: () -> Void
    @State private var profile = ""
    @State private var target = ""
    @State private var tracker = Tracker.linear.rawValue
    @State private var title = ""
    @State private var project = ""
    @State private var problem: String?

    var body: some View {
        let offered = AgentProfileLines.ordered(profiles).filter(\.hasAgent)
        SkillSheetFrame(title: "Start work") {
            field("Agent") {
                if offered.isEmpty {
                    QuietLine("No agent is connected yet. Give one of your agents a job first.")
                    Button("Open Jobs", systemImage: "arrow.up.forward") {
                        close()
                        AppWindow.shared.shell.go(WindowRoute(.agents, tab: "jobs"))
                    }
                    .buttonStyle(KitButton(kind: .secondary))
                } else {
                    ConsoleSelect(label: "Agent", selection: $profile, options: offered.map { SelectOption(value: $0.id, title: $0.name) })
                }
            }
            field("Issue") { TextField("LIN-123, PAY-42 or the issue's link", text: $target).kitField() }
            field("Tracker, for a bare key") {
                ConsoleSelect(label: "Tracker", selection: $tracker,
                              options: Tracker.allCases.map { SelectOption(value: $0.rawValue, title: AgentWorkLines.trackerName($0.rawValue)) })
            }
            field("Title, optional") { TextField("Shown beside the key, never fetched", text: $title).kitField() }
            field("Repository, optional") { TextField("/Users/you/code/api", text: $project).kitField() }
            QuietLine("The agent sees it at its next pause. Nothing is written back to the tracker unless you confirm it there.")
            if let problem {
                Text(problem)
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Console.destructive)
            }
        } footer: {
            Button("Cancel", action: close).buttonStyle(KitButton(kind: .secondary)).keyboardShortcut(.cancelAction)
            Spacer(minLength: Memnox.Spacing.medium)
            Button("Start") { start() }
                .buttonStyle(KitButton(kind: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(screen.desk.busy != nil || profile.isEmpty)
        }
        .onAppear { if profile.isEmpty, let first = offered.first { profile = first.id } }
    }

    private func start() {
        if let missing = AgentWorkLines.targetProblem(target) {
            problem = missing
            return
        }
        Task {
            let outcome = await screen.desk.start(profile: profile, target: target, tracker: Tracker(rawValue: tracker),
                                                  title: title, project: project)
            if case .failed(let why) = outcome {
                problem = why
                return
            }
            screen.said(outcome)
            close()
        }
    }

    private func field<Field: View>(_ label: String, @ViewBuilder content: () -> Field) -> some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
            Text(label)
                .font(Memnox.Console.sans(Memnox.TextSize.footnote, .medium))
                .foregroundStyle(Memnox.Console.muted)
            content()
        }
    }
}

/// The agent work that waits on the person, for Needs your attention: handoffs to answer and done claims to confirm.
struct WorkNeedingYou: View {
    @ObservedObject var screen: AgentWorkScreen
    let names: WorkNames

    var body: some View {
        let waiting = AgentWorkLines.open(screen.desk.work ?? []).filter(AgentWorkLines.needsYou)
        if !waiting.isEmpty {
            ShellSection(title: "Agent work \u{00B7} \(waiting.count)") {
                VStack(spacing: Memnox.Spacing.large) {
                    ForEach(waiting) { AgentWorkCard(screen: screen, work: $0, names: names) }
                }
            }
        }
    }
}
