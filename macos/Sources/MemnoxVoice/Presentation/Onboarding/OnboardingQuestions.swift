import MemnoxVoiceCore
import SwiftUI

/// A radio mark, the same on both questions and the rule packs.
private struct RadioMark: View {
    let on: Bool

    private static let side: CGFloat = 16
    private static let ring: CGFloat = 2

    var body: some View {
        Circle()
            .strokeBorder(on ? Memnox.Palette.primary : Memnox.ink(Memnox.Ink.tertiary), lineWidth: Self.ring)
            .background(Circle().fill(on ? Memnox.Palette.primary : Color.clear))
            .frame(width: Self.side, height: Self.side)
            .accessibilityHidden(true)
    }
}

/// One answer of a question as a row that is pressed whole.
private struct AnswerRow: View {
    let symbol: String
    let title: String
    let detail: String
    let on: Bool
    var disabled = false
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            KitRow(symbol: symbol, title: title, detail: detail) { RadioMark(on: on) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHand()
        .disabled(disabled)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}

/// A line of what a press came to, in the quiet ink under the step.
private struct StepNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Memnox.sans(Memnox.TextSize.footnote))
            .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The first question: what the person wants their AI to help with, answered by picking one of the runtime's jobs,
/// which is kept as a profile with no agent behind it yet. Nothing is applied, and skipping is always allowed.
struct JobStep: View {
    @ObservedObject var flow: OnboardingFlow

    var body: some View {
        StepTitle(title: FirstRunQuestions.jobTitle, detail: FirstRunQuestions.jobDetail)
        if let profiles = AppWindow.shared.shell.profiles, AppWindow.shared.shell.supports("templates") == true {
            JobChoices(flow: flow, screen: profiles)
        } else {
            StepNote(text: FirstRunQuestions.noJobs)
            Next(title: "Continue", flow: flow)
        }
    }
}

private struct JobChoices: View {
    @ObservedObject var flow: OnboardingFlow
    @ObservedObject var screen: ProfilesScreen
    @State private var picked: String?
    @State private var keeping = false
    @State private var failed: String?

    var body: some View {
        let templates = screen.profiles.templates
        KitCard(symbol: "briefcase", title: "Jobs to start from", detail: "Each one is a job description. \(AgentProfileLines.noAgent).") {
            if let templates {
                if templates.isEmpty { StepNote(text: FirstRunQuestions.noJobs) }
                ForEach(Array(templates.enumerated()), id: \.element.id) { index, each in
                    if index > 0 { KitDivider() }
                    AnswerRow(symbol: "briefcase", title: each.name, detail: each.purpose, on: chosen == each.id, disabled: keeping) {
                        picked = each.id
                    }
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task {
            if picked == nil, let kept = flow.job { picked = screen.profiles.profiles?.first { $0.id == kept.id }?.templateOf }
            await screen.profiles.readTemplates()
        }
        if let failed { StepNote(text: failed) }
        if let template = templates?.first(where: { $0.id == chosen }), flow.job?.name != template.name {
            Button { Task { await keep(template) } } label: {
                HStack(spacing: Memnox.Spacing.small) {
                    Text(keeping ? "Keeping \(template.name)" : "Continue")
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(KitButton(kind: .primary, wide: true))
            .keyboardShortcut(.defaultAction)
            .disabled(keeping)
        } else {
            Next(title: "Continue", flow: flow)
        }
        if flow.job == nil {
            Button(FirstRunQuestions.skip) { flow.next() }
                .buttonStyle(KitButton(kind: .secondary, wide: true))
                .disabled(keeping)
        }
    }

    private var chosen: String? { picked }

    /// Copies the job into a profile with no suggested skill taken and no rule applied, then moves on.
    private func keep(_ template: ProfileTemplate) async {
        keeping = true
        failed = nil
        let outcome = await screen.profiles.fromTemplate(template.id, named: template.name, skills: [])
        keeping = false
        switch outcome {
        case .failed(let why):
            // A job of that name kept by an earlier first run is used as it is, so a second run never stops here.
            if let kept = Self.kept(template, in: screen.profiles.profiles) {
                flow.job = (kept.id, kept.name)
                flow.next()
            } else {
                failed = why
            }
        case .done:
            if let kept = Self.kept(template, in: screen.profiles.profiles) { flow.job = (kept.id, kept.name) }
            flow.next()
        }
    }

    private static func kept(_ template: ProfileTemplate, in profiles: [ProfileView]?) -> ProfileView? {
        let matching = (profiles ?? []).filter { $0.templateOf == template.id }
        return matching.first { $0.name == template.name } ?? matching.first
    }
}

/// The second question: where the person's agent runs. On this Mac the agents found are already under Memnox and the
/// job can go to one of them; anywhere else the agent reaches Memnox through Memnox Cloud, offered and never required.
struct PlaceStep: View {
    @ObservedObject var flow: OnboardingFlow

    var body: some View {
        StepTitle(title: FirstRunQuestions.placeTitle, detail: FirstRunQuestions.placeDetail)
        if let agents = AppWindow.shared.shell.agents {
            PlaceChoices(flow: flow, agents: agents, profiles: AppWindow.shared.shell.profiles)
        } else {
            PlaceChoices(flow: flow, agents: nil, profiles: AppWindow.shared.shell.profiles)
        }
    }
}

private struct PlaceChoices: View {
    @ObservedObject var flow: OnboardingFlow
    let agents: AgentsScreen?
    let profiles: ProfilesScreen?
    @State private var agent = ""
    @State private var binding = false
    @State private var failed: String?

    var body: some View {
        let found = agents?.agents.agents ?? []
        KitCard(symbol: "point.3.connected.trianglepath.dotted", title: "Pick one") {
            ForEach(Array(AgentPlace.allCases.enumerated()), id: \.element.id) { index, place in
                if index > 0 { KitDivider() }
                AnswerRow(symbol: Self.symbol(place), title: place.title, detail: place.detail, on: flow.place == place, disabled: binding) {
                    flow.place = place
                }
            }
        }
        .onAppear {
            if flow.place == nil { flow.place = AgentPlace.suggested(foundHere: found.count) }
            if agent.isEmpty { agent = found.first?.kind ?? "" }
        }
        if let place = flow.place { answer(place, found: found) }
        if let failed { StepNote(text: failed) }
        Button { Task { await go(found) } } label: {
            HStack(spacing: Memnox.Spacing.small) {
                Text(binding ? "Giving the job" : "Continue")
                Image(systemName: "arrow.right")
            }
        }
        .buttonStyle(KitButton(kind: .primary, wide: true))
        .keyboardShortcut(.defaultAction)
        .disabled(binding)
    }

    /// What the answer means: the agents found here and who takes the job, or how a remote agent connects.
    @ViewBuilder private func answer(_ place: AgentPlace, found: [AgentStanding]) -> some View {
        KitCard(symbol: place.isLocal ? "desktopcomputer" : "cloud", title: "How it reaches Memnox", detail: place.connects) {
            if place.isLocal {
                if found.isEmpty {
                    StepNote(text: FirstRunQuestions.nothingFound)
                } else if let job = flow.job {
                    ConsoleSelect(label: "Give \(job.name) to", selection: $agent,
                                  options: [SelectOption(value: "", title: "No agent yet")]
                                      + found.map { SelectOption(value: $0.kind, title: $0.name) })
                } else {
                    StepNote(text: FirstRunLines.agentsFound(found))
                }
            } else if place.throughCloud {
                StepNote(text: FirstRunQuestions.cloudOptional)
                if let account = flow.account { CloudOffer(account: account) }
            } else if let line = FirstRunQuestions.jobLine(job: flow.job?.name, boundTo: nil) {
                StepNote(text: line)
            }
        }
    }

    /// Binds the job to the agent chosen on this Mac, which a person does on purpose, then moves on.
    private func go(_ found: [AgentStanding]) async {
        guard let place = flow.place, place.isLocal, let job = flow.job, let profiles, !agent.isEmpty,
              found.contains(where: { $0.kind == agent }) else {
            flow.next()
            return
        }
        binding = true
        failed = nil
        let outcome = await profiles.profiles.bind(job.id, agent: agent)
        binding = false
        switch outcome {
        case .failed(let why): failed = why
        case .done:
            flow.boundTo = found.first { $0.kind == agent }?.name
            flow.next()
        }
    }

    private static func symbol(_ place: AgentPlace) -> String {
        switch place {
        case .thisMacCoding: "chevron.left.forwardslash.chevron.right"
        case .thisMacApp: "macwindow"
        case .hosted: "server.rack"
        case .insideApp: "app.connected.to.app.below.fill"
        case .noCode: "square.grid.3x3"
        case .ownCode: "curlybraces"
        case .noneYet: "sparkles"
        }
    }
}

/// Signing in to Memnox Cloud, offered where it is the way an agent connects and never needed to go on.
struct CloudOffer: View {
    @ObservedObject var account: AccountModel

    var body: some View {
        HStack(spacing: Memnox.Spacing.medium) {
            switch account.step {
            case .signedIn(let name, _):
                CheckBox(state: .done)
                StepNote(text: "Signed in as \(name).")
            case .showingCode(let code):
                StepNote(text: "Approve \(code) on the page that opened, or press Cancel and go on.")
                Button("Cancel") { account.cancel() }.buttonStyle(KitButton(kind: .secondary))
            case .starting:
                ProgressView().controlSize(.small)
                Button("Cancel") { account.cancel() }.buttonStyle(KitButton(kind: .secondary))
            case .failed(let why):
                StepNote(text: why)
                Button("Try again") { account.start() }.buttonStyle(KitButton(kind: .secondary))
            case .signedOut:
                Button("Sign in to Memnox Cloud", systemImage: "person.crop.circle") { account.start() }
                    .buttonStyle(KitButton(kind: .secondary))
                StepNote(text: "Optional")
            }
        }
        .padding(.top, Memnox.Spacing.regular)
    }
}
