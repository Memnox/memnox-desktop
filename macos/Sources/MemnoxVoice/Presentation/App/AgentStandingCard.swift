import AppKit
import MemnoxVoiceCore
import SwiftUI

/// One agent: who it is and where it stands at the top, the few numbers worth reading, when it was last active and what
/// it reaches, what it did last, and its controls pinned along the foot, so the cards in a row line up at both edges.
struct AgentStandingCard: View {
    @ObservedObject var screen: AgentsScreen
    let agent: AgentStanding
    /// The home's Protect press, which a card outside Memnox leads with; nil where this window has none.
    let home: HomeModel?
    let folders: [FolderPick]
    let profiles: [ProfileView]
    /// The one card whose Launch form is open, by agent kind.
    @Binding var launching: String?

    private static let logo: CGFloat = 30
    /// The recent actions a card lists; the Activity page holds the rest, so one busy agent does not stretch its row.
    private static let recentShown = 3
    /// How strongly an unprotected card's edge wears the console's amber, so the one to act on is seen first.
    private static let attentionEdge = 0.55
    /// The skills a card names as chips before it counts the rest, so the chips keep to one line.
    private static let skillChips = 3

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
        let standing = StudioLines.statusWord(agent.status)
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            HStack(spacing: Memnox.Spacing.regular) {
                BrandLogo(agent: agent.kind, name: agent.name, size: Self.logo)
                Text(agent.name)
                    .font(Memnox.Console.sans(Memnox.TextSize.headline, .semibold))
                    .foregroundStyle(Memnox.Console.foreground)
                    .lineLimit(1)
                Spacer(minLength: Memnox.Spacing.small)
                StatusWord(Tone(standing.tone), standing.word)
            }
            VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
                AgentFigures(agent: agent)
                Text(AgentLines.reachLine(agent, now: Date()))
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                    .foregroundStyle(Memnox.Console.muted)
                    .lineLimit(1)
            }
            reach
            if !agent.recent.isEmpty {
                VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
                    ForEach(agent.recent.prefix(Self.recentShown)) { RecentRow(action: $0) }
                }
            }
            Spacer(minLength: 0)
            controls
            if let result = screen.protectResult, result.covers(agent.kind) { ProtectResultLine(result: result, screen: screen, home: home) }
            if launching == agent.kind { launchForm }
        }
        .padding(Memnox.Spacing.xLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Memnox.Console.card, in: shape)
        .overlay(shape.strokeBorder(agent.agentStatus == .unprotected ? Memnox.Console.warm.opacity(Self.attentionEdge) : Memnox.Console.panelEdge,
                                    lineWidth: Memnox.Stroke.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(agent.name)
    }

    /// The hub's servers by name on a line cut rather than wrapped, and its skills as a few chips and a count of the rest.
    @ViewBuilder private var reach: some View {
        if !agent.mcpServers.isEmpty {
            ReachLine(label: "Servers", names: agent.mcpServers)
        }
        let chips = AgentLines.chips(agent.skills, limit: Self.skillChips)
        if !chips.shown.isEmpty {
            HStack(spacing: Memnox.Spacing.small) {
                ForEach(chips.shown, id: \.self) { SkillChip(text: $0) }
                if chips.more > 0 { SkillChip(text: "+\(chips.more)") }
            }
            .help((agent.skills ?? []).joined(separator: ", "))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Skills: \((agent.skills ?? []).joined(separator: ", "))")
        }
    }

    /// The one press its standing calls for at the start, Protect in the console's blue where it runs outside Memnox,
    /// and Launch at the end only where the runtime can open it, so the foot reads the same on every card.
    private var controls: some View {
        HStack(spacing: Memnox.Spacing.medium) {
            let busy = screen.agents.busy == agent.kind
            switch AgentLines.press(agent) {
            case .protect:
                if let home, !home.remote() { ProtectButton(home: home, screen: screen, kinds: [agent.kind]) }
            case .resume:
                Button { screen.press { await $0.resume(agent.kind) } } label: { Label("Resume", systemImage: "play.fill") }
                    .buttonStyle(KitButton(kind: .secondary))
                    .disabled(busy)
                    .help("Lets it carry on once you confirm with Touch ID")
            case .pause:
                Button { screen.press { await $0.pause(agent.kind) } } label: { Label("Pause", systemImage: "pause.fill") }
                    .buttonStyle(KitButton(kind: .secondary))
                    .disabled(busy)
                    .help("Holds everything it tries until you resume it")
                    .accessibilityLabel("Pause \(agent.name)")
            }
            Spacer(minLength: Memnox.Spacing.small)
            if agent.canLaunch, launching != agent.kind {
                Button { launching = agent.kind } label: { Label("Launch", systemImage: "apple.terminal") }
                    .buttonStyle(KitButton(kind: .secondary))
                    .help("Opens it in a new terminal in a folder you choose")
            }
        }
    }

    private var launchForm: some View {
        LaunchForm(folders: folders, profiles: profiles, busy: screen.agents.busy == Agents.launching(agent.kind)) {
            launching = nil
        } launch: { folder, profile in
            let kind = agent.kind
            Task {
                let outcome = await screen.agents.launch(kind, in: folder, profile: profile)
                screen.note = StudioNotes.line(outcome, proposed: "Waiting for you on the island: confirm it with Touch ID.")
                if case .failed = outcome { return }
                launching = nil
            }
        }
    }
}

/// Its sessions running and today's actions, asks and refusals as small labelled numbers, or a few words when it did nothing.
private struct AgentFigures: View {
    let agent: AgentStanding

    var body: some View {
        let figures = AgentLines.figures(agent)
        if figures.isEmpty {
            Text(AgentLines.nothingToday)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                .foregroundStyle(Memnox.Console.faint)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Memnox.Spacing.xLarge) {
                ForEach(figures, id: \.label) { figure in
                    VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                        Text("\(figure.value)")
                            .font(Memnox.Console.sans(Memnox.Console.TextSize.large, .semibold).monospacedDigit())
                            .foregroundStyle(figure.tone == .quiet ? Memnox.Console.foreground : Tone(figure.tone).color)
                        Text(figure.label)
                            .font(Memnox.Console.sans(Memnox.Console.TextSize.label, .medium))
                            .foregroundStyle(Memnox.Console.muted)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// A skill's name in a small bordered capsule, cut rather than wrapped.
private struct SkillChip: View {
    let text: String

    private static let height: CGFloat = 20

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous)
        Text(text)
            .font(Memnox.Console.sans(Memnox.Console.TextSize.label, .medium))
            .foregroundStyle(Memnox.Console.muted)
            .lineLimit(1)
            .padding(.horizontal, Memnox.Spacing.small)
            .frame(height: Self.height)
            .background(Memnox.Console.hover, in: shape)
            .overlay(shape.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
    }
}

/// "Servers: github, linear", cut at the end with every name in its help.
private struct ReachLine: View {
    let label: String
    let names: [String]

    var body: some View {
        let all = names.joined(separator: ", ")
        Text("\(label): \(all)")
            .font(Memnox.Console.sans(Memnox.TextSize.footnote))
            .foregroundStyle(Memnox.Console.muted)
            .lineLimit(1)
            .help(all)
    }
}

/// One thing it did lately: the target by its last parts on top, the operation's own name and how long ago under it,
/// and the decision's pill, the whole line in its help.
private struct RecentRow: View {
    let action: AgentAction

    var body: some View {
        let target = AgentLines.target(action)
        HStack(spacing: Memnox.Spacing.medium) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                Text(target ?? action.operation)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                    .foregroundStyle(Memnox.Console.foreground)
                    .lineLimit(1)
                    .truncationMode(.head)
                HStack(spacing: Memnox.Spacing.small) {
                    if target != nil {
                        Text(action.operation)
                            .font(Memnox.Console.code(Memnox.Console.TextSize.label))
                            .lineLimit(1)
                    }
                    if let ago = SessionText.ago(action.at, now: Date()) {
                        Text(ago)
                            .font(Memnox.Console.sans(Memnox.Console.TextSize.label))
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(Memnox.Console.muted)
            }
            Spacer(minLength: Memnox.Spacing.small)
            StatusWord(Tone(effect: action.effect), StudioLines.title(action.effect))
        }
        .help(StudioLines.activityLine(operation: action.operation, target: action.target))
        .accessibilityElement(children: .combine)
    }
}

/// The folder an agent opens in, chosen in Finder's own panel, typed whole or one of the workspaces its sessions ran in,
/// and a profile to apply first.
private struct LaunchForm: View {
    let folders: [FolderPick]
    let profiles: [ProfileView]
    let busy: Bool
    let cancel: () -> Void
    let launch: (String, String?) -> Void
    @State private var folder = ""
    @State private var profile = ""
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            ShellDivider()
            Text("Open it in")
                .font(Memnox.Console.sans(Memnox.TextSize.footnote, .medium))
                .foregroundStyle(Memnox.Console.muted)
            HStack(spacing: Memnox.Spacing.medium) {
                TextField("/Users/you/code/project", text: $folder)
                    .kitField()
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .onSubmit(go)
                    .accessibilityLabel("The folder it opens in")
                Button("Choose", systemImage: "folder", action: choose)
                    .buttonStyle(KitButton(kind: .secondary))
                    .help("Pick the folder in Finder")
            }
            if !folders.isEmpty {
                // The workspaces as quick picks, so the usual folder is one click away.
                ScrollView(.horizontal) {
                    HStack(spacing: Memnox.Spacing.small) {
                        ForEach(folders, id: \.path) { each in
                            Button(each.name) { folder = each.path }
                                .buttonStyle(KitButton(kind: folder == each.path ? .primary : .secondary))
                                .help(each.path)
                                .accessibilityAddTraits(folder == each.path ? .isSelected : [])
                        }
                    }
                }
                .scrollIndicators(.never)
                .accessibilityLabel("Your workspaces")
            }
            if !profiles.isEmpty {
                ConsoleSelect(label: "With a profile", selection: $profile,
                              options: [SelectOption(value: "", title: "No profile")]
                                  + profiles.map { SelectOption(value: $0.id, title: $0.name) })
                if !profile.isEmpty { QuietLine("What the profile gives waits for your signature on the island as the agent opens.") }
            }
            if let problem {
                Text(problem)
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Console.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Memnox.Spacing.medium) {
                Button(busy ? "Opening" : "Open a terminal", systemImage: "apple.terminal", action: go)
                    .buttonStyle(KitButton(kind: .primary))
                    .disabled(busy)
                Button("Cancel", action: cancel).buttonStyle(KitButton(kind: .secondary))
            }
        }
        .onAppear { if folder.isEmpty, let first = folders.first { folder = first.path } }
    }

    private func go() {
        problem = LaunchLines.folderProblem(folder)
        if problem == nil { launch(folder, profile.isEmpty ? nil : profile) }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Open here"
        if !folder.isEmpty { panel.directoryURL = URL(fileURLWithPath: folder) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = url.path
        problem = nil
    }
}
