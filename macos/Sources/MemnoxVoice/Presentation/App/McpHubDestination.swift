import MemnoxVoiceCore
import SwiftUI

/// The hub for the views: redrawn whenever the core's hub changes, with the line the last press ended in.
@MainActor
final class McpHubScreen: ObservableObject {
    let hub: McpHub
    /// Bumped when the hub changes, so every view reading it is drawn again.
    @Published private(set) var tick = 0
    /// What the last press came to, shown above the page until the next one.
    @Published var note: String?

    init(hub: McpHub) {
        self.hub = hub
        hub.changed = { [weak self] in
            Task { @MainActor [weak self] in self?.tick += 1 }
        }
    }

    func said(_ outcome: McpHubOutcome) {
        switch outcome {
        case .proposed: note = "\(McpHubLines.waitingForTouchID): confirm it there and the runtime writes it."
        case .failed(let why): note = why
        case .done(let line): note = line
        }
    }

    /// Runs one press and says how it ended.
    func press(_ work: @escaping (McpHub) async -> McpHubOutcome) {
        Task { said(await work(hub)) }
    }
}

extension Tone {
    init(_ tone: McpTone) {
        switch tone {
        case .good: self = .good
        case .bad: self = .bad
        case .quiet: self = .quiet
        }
    }
}

/// The MCP Hub: servers set up once and given to the agents the person chooses. Every config is written by the
/// runtime, a change that gives an agent more waits for a signature on the island, and a secret is kept by this
/// computer and never shown again.
struct McpHubDestination: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var screen: McpHubScreen
    @ObservedObject var island: IslandModel
    let tab: String?
    let width: WidthClass

    var body: some View {
        page
            // A proposal signed or declined on the island is read back by the hub itself, from the daemon's settled event.
            .task(id: tab) { await screen.hub.refresh() }
    }

    @ViewBuilder private var page: some View {
        if let view = screen.hub.hub {
            switch tab {
            case "clients": ShellScroll(width: width) { note; McpClients(screen: screen, view: view, workspaces: workspaces) }
            case "secrets": ShellScroll(width: width) { note; McpSecrets(screen: screen, view: view) }
            default: McpServers(shell: shell, screen: screen, view: view, width: width) { note }
            }
        } else if screen.hub.unreadable {
            ShellScroll(width: width) { ReadFailed(what: "the MCP Hub") { Task { await screen.hub.refresh() } } }
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// A server given in one project only is changed in that project's settings, which Workspaces shows.
    private func workspaces() {
        shell.go(WindowRoute(.workspaces, tab: "projects"))
    }

    @ViewBuilder private var note: some View {
        if let line = screen.note {
            Text(line)
                .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.Console.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ShellMetrics.rowPaddingH)
                .padding(.vertical, ShellMetrics.rowPaddingV)
                .background(Memnox.Console.card, in: RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
                    .strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

private enum McpServersLayout {
    /// The narrowest a server card reads well at: its name beside the transport pill, and its status row whole.
    static let cardWidth: CGFloat = 300
    static let searchWidth: CGFloat = 320
}

/// Every server in the hub as a card, what agents already had before it, and what it left alone.
private struct McpServers<Note: View>: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var screen: McpHubScreen
    let view: McpHubView
    let width: WidthClass
    @ViewBuilder let note: Note
    @State private var query = ""
    @State private var adding = false

    var body: some View {
        let picked = view.servers.first { $0.name == shell.inspecting }
        InspectorLayout(width: width, title: picked?.name, close: { shell.inspecting = nil }) {
            ShellScroll(width: width) {
                note
                toolbar
                if shell.scope == .organization {
                    QuietLine(shown.isEmpty ? ShellLines.noOrganizationItems : ShellLines.organizationReadOnly)
                }
                if view.servers.isEmpty {
                    VStack(spacing: Memnox.Spacing.large) {
                        EmptyState(symbol: "powerplug", title: "No servers in the hub yet",
                                   detail: "Add a server once and give it to any agent, or bring in one an agent already has from Found on this computer below.")
                        Button { adding = true } label: { Label("Add server", systemImage: "plus") }
                            .buttonStyle(KitButton(kind: .primary))
                    }
                } else {
                    EqualRowsGrid(items: shown, cardWidth: McpServersLayout.cardWidth) { server in
                        McpServerCard(screen: screen, server: server, chosen: server.name == shell.inspecting) { shell.inspecting = server.name }
                    }
                }
                McpFound(screen: screen, view: view)
                McpLeftAlone(view: view)
            }
        } detail: {
            if let picked {
                McpServerDetail(screen: screen, view: view, server: picked, workspaces: { shell.go(WindowRoute(.workspaces, tab: "projects")) }) { shell.inspecting = nil }
            }
        }
        .consoleSheet(isPresented: $adding) {
            AddServerSheet(screen: screen, agents: view.agents.map(\.agent)) { adding = false }
        }
    }

    private var shown: [McpHubServerView] {
        // The scope selector shows the person's servers or the organization's, never the two mixed.
        let scoped = ShellLines.inScope(view.servers, shell.scope) { McpHubLines.fromOrganization($0) }
        let words = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !words.isEmpty else { return scoped }
        return scoped.filter { "\($0.name) \($0.description ?? "")".lowercased().contains(words) }
    }

    private var toolbar: some View {
        HStack(spacing: Memnox.Spacing.regular) {
            SearchField(prompt: "Search servers", text: $query).frame(maxWidth: McpServersLayout.searchWidth)
            Spacer(minLength: Memnox.Spacing.medium)
            Button { screen.press { await $0.sync() } } label: { Label("Sync", systemImage: "arrow.clockwise") }
                .buttonStyle(KitButton(kind: .secondary))
                .disabled(screen.hub.busy == McpHub.syncing)
                .help("Write what the hub gives each agent into its config again")
            Button { adding = true } label: { Label("Add server", systemImage: "plus") }
                .buttonStyle(KitButton(kind: .primary))
        }
    }
}

/// One server as a card: its name and transport on top, how it is reached in mono, a calm status row with Test, then
/// the agents by logo beside Governed. Every pill keeps its words whole, and a row too narrow drops what matters least
/// rather than squeezing a word. The card is not itself a button, so Test is its own press; a tap elsewhere opens details.
private struct McpServerCard: View {
    @ObservedObject var screen: McpHubScreen
    let server: McpHubServerView
    let chosen: Bool
    let pick: () -> Void

    private static let logo: CGFloat = 18
    private static let overlap: CGFloat = -5
    private static let ring: CGFloat = 2
    /// The most logos a card stacks before the names beside them carry the rest.
    private static let logosShown = 4

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            header
            ShellDivider()
            standing
            Spacer(minLength: 0)
            footer
        }
        .padding(Memnox.Spacing.xLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Memnox.Console.card, in: shape)
        .overlay(shape.strokeBorder(chosen ? Memnox.Console.primary : Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
        .contentShape(shape)
        .onTapGesture(perform: pick)
        .pointingHand()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(server.name)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Show details", pick)
    }

    /// The name with the transport pill on one line, and how it is reached in mono beneath, cut in the middle.
    private var header: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
            HStack(alignment: .firstTextBaseline, spacing: Memnox.Spacing.medium) {
                Text(server.name)
                    .font(Memnox.Console.sans(Memnox.TextSize.headline, .semibold))
                    .foregroundStyle(Memnox.Console.foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Memnox.Spacing.small)
                StatusWord(.quiet, McpHubLines.transport(server))
            }
            Text(McpHubLines.launch(server))
                .font(Memnox.Console.code(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.Console.muted)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(([McpHubLines.launch(server)] + (server.args ?? [])).joined(separator: " "))
            if let description = server.description {
                Text(description)
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Console.muted)
                    .lineLimit(1)
            }
        }
    }

    /// How it stands with how many tools it listed beside it, and Test at the end; the count goes first when it is narrow.
    private var standing: some View {
        let health = screen.hub.testOf(server.name) ?? server.health
        let tools = McpHubLines.tools(health.tools?.count ?? server.toolCount)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Memnox.Spacing.medium) {
                state
                Text(tools)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                    .foregroundStyle(Memnox.Console.faint)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: Memnox.Spacing.small)
                test
            }
            HStack(spacing: Memnox.Spacing.medium) {
                state
                Spacer(minLength: Memnox.Spacing.small)
                test
            }
        }
    }

    @ViewBuilder private var state: some View {
        let health = screen.hub.testOf(server.name) ?? server.health
        let words = McpHubLines.health(health)
        if McpHubLines.missingSecrets(server).isEmpty {
            StatusWord(Tone(words.tone), words.word)
        } else {
            StatusWord(.bad, "Needs a secret")
        }
    }

    private var test: some View {
        let busy = screen.hub.busy == server.name
        return Button { screen.press { await $0.test(server.name) } } label: {
            HStack(spacing: Memnox.Spacing.xSmall) {
                if busy { ProgressView().controlSize(.mini) }
                Text(busy ? "Testing" : "Test")
            }
            .font(Memnox.Console.sans(Memnox.Console.TextSize.meta, .medium))
            .foregroundStyle(Memnox.Console.primary)
            .fixedSize()
        }
        .buttonStyle(.plain)
        .pointingHand()
        .disabled(busy)
        .help("Starts the server once and asks what it offers")
        .accessibilityLabel("Test \(server.name)")
    }

    /// The agents by logo and name, then Governed and whose it is; whose it is goes first, then the pills take a line.
    private var footer: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Memnox.Spacing.medium) { users; Spacer(minLength: Memnox.Spacing.small); governed; scope }
                HStack(spacing: Memnox.Spacing.medium) { users; Spacer(minLength: Memnox.Spacing.small); governed }
                VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
                    users
                    HStack(spacing: Memnox.Spacing.small) { governed; scope }
                }
            }
            if !(server.projects ?? []).isEmpty {
                HStack(spacing: Memnox.Spacing.small) {
                    ForEach(McpHubLines.agentsOnce(server), id: \.self) { agent in
                        McpProjectChips(server: server, agent: agent)
                    }
                }
            }
        }
    }

    private var governed: some View {
        server.governed ? StatusWord(.good, "Governed") : StatusWord(.attention, "Not governed")
    }

    private var scope: some View {
        ScopeChip(ScopeLines.server(server))
    }

    /// The agents given it, by logo and by name on one line cut at its end.
    private var users: some View {
        let agents = McpHubLines.agentsOnce(server)
        return HStack(spacing: Memnox.Spacing.medium) {
            if !agents.isEmpty {
                HStack(spacing: Self.overlap) {
                    ForEach(agents.prefix(Self.logosShown), id: \.self) { agent in
                        BrandLogo(agent: agent, name: McpHubLines.agentLabel(agent), size: Self.logo)
                            .overlay(RoundedRectangle(cornerRadius: Self.logo / 4, style: .continuous)
                                .strokeBorder(Memnox.Console.card, lineWidth: Self.ring))
                    }
                }
                .fixedSize()
                .accessibilityHidden(true)
            }
            Text(McpHubLines.usedBy(server))
                .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                .foregroundStyle(agents.isEmpty ? Memnox.Console.faint : Memnox.Console.muted)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(McpHubLines.usedBy(server))
        }
    }
}

/// Where the last press on one row stands, in that row: a spinner while the runtime works, then the island it waits on,
/// what it came to, or why it did not go through.
private struct McpPressLine: View {
    let press: McpPress?

    var body: some View {
        if press == .working {
            HStack(spacing: Memnox.Spacing.small) {
                ProgressView().controlSize(.mini)
                Text("Asking the runtime")
            }
            .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
            .foregroundStyle(Memnox.Console.muted)
        } else if let line = McpHubLines.pressLine(press) {
            Label {
                Text(line.text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            } icon: {
                Image(systemName: Self.symbol(line.tone, waiting: press.map(Self.waits) ?? false)).accessibilityHidden(true)
            }
            .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
            .foregroundStyle(Tone(line.tone).color)
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private static func waits(_ press: McpPress) -> Bool {
        if case .waiting = press { return true }
        return false
    }

    private static func symbol(_ tone: McpTone, waiting: Bool) -> String {
        if waiting { return "touchid" }
        switch tone {
        case .good: return "checkmark.circle"
        case .bad: return "exclamationmark.triangle"
        case .quiet: return "clock"
        }
    }
}

/// One server's health, who has it, which credentials it holds by name, its tools, and Remove set apart at the end.
private struct McpServerDetail: View {
    @ObservedObject var screen: McpHubScreen
    let view: McpHubView
    let server: McpHubServerView
    let workspaces: () -> Void
    let removed: () -> Void

    private static let logo: CGFloat = 22

    var body: some View {
        let hub = screen.hub
        let health = hub.testOf(server.name) ?? server.health
        let words = McpHubLines.health(health)
        let tools = health.tools ?? server.tools ?? []
        let missing = McpHubLines.missingSecrets(server)
        let busy = hub.busy == server.name
        VStack(alignment: .leading, spacing: Memnox.Spacing.xxLarge) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
                if missing.isEmpty {
                    StatusWord(Tone(words.tone), words.word)
                } else {
                    StatusWord(.bad, "Needs \(missing.joined(separator: ", "))")
                }
                if let checked = health.checkedAt {
                    quiet("Tested \(SessionText.ago(checked, now: Date()) ?? "just now")")
                }
                if let error = health.error {
                    Text(error)
                        .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                        .foregroundStyle(Memnox.Console.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                Text(([McpHubLines.launch(server)] + (server.args ?? [])).joined(separator: " "))
                    .font(Memnox.Console.code(Memnox.TextSize.micro))
                    .foregroundStyle(Memnox.Console.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                quiet(McpHubLines.calls(server.callsThisWeek))
            }
            Button(busy ? "Testing" : "Test connection") { screen.press { await $0.test(server.name) } }
                .buttonStyle(KitButton(kind: .secondary))
                .disabled(busy)

            if McpHubLines.fromOrganization(server) {
                // Given by the organization, so who has it is changed in Memnox Cloud and only shown here.
                ShellSection(title: "Agents") {
                    StatusWord(.quiet, McpHubLines.organizationWord)
                    if !server.agents.isEmpty {
                        ShellPanel {
                            ForEach(Array(McpHubLines.agentsOnce(server).enumerated()), id: \.element) { index, agent in
                                if index > 0 { ShellDivider() }
                                ShellRow(title: McpHubLines.agentLabel(agent), caption: McpHubLines.reachCaption(server, agent: agent)) {
                                    BrandLogo(agent: agent, name: McpHubLines.agentLabel(agent), size: Self.logo)
                                } trailing: {
                                    McpProjectChips(server: server, agent: agent)
                                }
                            }
                        }
                    }
                    quiet(McpHubLines.organizationLine)
                }
            } else {
                ShellSection(title: "Agents") {
                    ShellPanel {
                        ForEach(Array(view.agents.enumerated()), id: \.element.agent) { index, each in
                            if index > 0 { ShellDivider() }
                            agentRow(each.agent)
                        }
                    }
                    quiet("Giving a server to an agent waits for your signature with Touch ID. Taking it away happens at once.")
                    if !(server.projects ?? []).isEmpty { quiet(McpHubLines.projectOnlyLine) }
                }
            }

            let headers = HeaderLines.lines(server)
            if !headers.isEmpty {
                ShellSection(title: "Headers") {
                    ShellPanel {
                        ForEach(Array(headers.enumerated()), id: \.element.name) { index, header in
                            if index > 0 { ShellDivider() }
                            ShellRow(title: header.name) {
                                EmptyView()
                            } trailing: {
                                if let held = header.held {
                                    StatusWord(held ? .good : .bad, held ? "Secret kept by this Mac" : "Secret not set")
                                }
                            }
                        }
                    }
                    quiet("Sent with every call to the server. Only the names are shown here, never the values.")
                }
            }

            if !server.secretsHeld.isEmpty {
                ShellSection(title: "Credentials") {
                    ShellPanel {
                        ForEach(Array(server.secretsHeld.keys.sorted().enumerated()), id: \.element) { index, name in
                            if index > 0 { ShellDivider() }
                            let held = server.secretsHeld[name] == true
                            ShellRow(title: name) {
                                Image(systemName: "key").foregroundStyle(Memnox.Console.muted).accessibilityHidden(true)
                            } trailing: {
                                StatusWord(held ? .good : .bad, held ? "Kept by this computer" : "Not set")
                            }
                        }
                    }
                    quiet("A secret is never shown again. Replace one under Secrets.")
                }
            }

            ShellSection(title: "Tools") {
                if tools.isEmpty {
                    quiet("Test the connection to list what this server can do.")
                } else {
                    ShellPanel {
                        ForEach(Array(tools.enumerated()), id: \.element.name) { index, tool in
                            if index > 0 { ShellDivider() }
                            ShellRow(title: tool.name, caption: tool.description) { EmptyView() } trailing: { EmptyView() }
                        }
                    }
                }
            }

            // Set apart at the end, away from the routine controls; an organization's server is removed in Memnox Cloud.
            if !McpHubLines.fromOrganization(server) {
                VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
                    ShellDivider()
                    Button("Remove from every agent") {
                        let name = server.name
                        Task {
                            let outcome = await hub.removeServer(name)
                            screen.said(outcome)
                            if case .done = outcome { removed() }
                        }
                    }
                    .buttonStyle(KitButton(kind: .secondary))
                    .disabled(busy)
                }
            }
        }
    }

    private func agentRow(_ agent: String) -> some View {
        let reach = McpHubLines.reach(server, agent: agent)
        // Taking away removes only the everywhere assignment, so a project only one is offered Give alone.
        let on = reach == .everywhere
        let label = McpHubLines.agentLabel(agent)
        let pair = McpHub.pair(server.name, agent)
        let press = screen.hub.press(pair)
        let working = press == .working
        return VStack(alignment: .leading, spacing: 0) {
            ShellRow(title: label, caption: McpHubLines.reachCaption(server, agent: agent)) {
                BrandLogo(agent: agent, name: label, size: Self.logo)
            } trailing: {
                McpProjectChips(server: server, agent: agent)
                if reach == .projects { GoLink(McpHubLines.workspacesLink, action: workspaces) }
                Button {
                    screen.hub.clear(pair)
                    screen.press { await $0.assign(server.name, agent: agent, on: !on) }
                } label: {
                    HStack(spacing: Memnox.Spacing.xSmall) {
                        if working { ProgressView().controlSize(.mini) }
                        Text(on ? "Take away" : reach == .projects ? McpHubLines.giveEverywhere : "Give")
                    }
                    .fixedSize()
                }
                .buttonStyle(KitButton(kind: .secondary))
                .disabled(working)
            }
            if press != nil, !working {
                McpPressLine(press: press)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, ShellMetrics.rowPaddingH)
                    .padding(.bottom, ShellMetrics.rowPaddingV)
            }
        }
    }

    private func quiet(_ text: String) -> some View {
        Text(text)
            .font(Memnox.Console.sans(Memnox.TextSize.footnote))
            .foregroundStyle(Memnox.Console.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Servers an agent already had before the hub, offered to bring in and never touched until then. A line brought in
/// leaves this list as the answer redraws the hub, and its server shows in the grid above.
private struct McpFound: View {
    @ObservedObject var screen: McpHubScreen
    let view: McpHubView

    private static let logo: CGFloat = 22

    var body: some View {
        if !view.found.isEmpty {
            ShellSection(title: "Found on this computer \u{00B7} \(view.found.count)") {
                ShellPanel {
                    ForEach(Array(view.found.enumerated()), id: \.offset) { index, entry in
                        if index > 0 { ShellDivider() }
                        row(entry)
                    }
                }
                Text("Bringing a server in puts it behind Memnox, so every call it makes is ruled on and recorded.")
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Console.muted)
            }
        }
    }

    private func row(_ entry: McpHubEntryView) -> some View {
        let who = entry.agent.map(McpHubLines.agentLabel) ?? "Shared by several agents"
        let subject = entry.agent.map { McpHub.found(entry.name, $0) }
        let press = subject.flatMap(screen.hub.press)
        let working = press == .working
        return VStack(alignment: .leading, spacing: 0) {
            ShellRow(title: entry.name, caption: "\(who) \u{00B7} \(entry.path)") {
                if let agent = entry.agent {
                    BrandLogo(agent: agent, name: McpHubLines.agentLabel(agent), size: Self.logo)
                } else {
                    Image(systemName: "powerplug").foregroundStyle(Memnox.Console.muted).accessibilityHidden(true)
                }
            } trailing: {
                if let agent = entry.agent {
                    Button { screen.press { await $0.importServer(agent: agent, server: entry.name) } } label: {
                        HStack(spacing: Memnox.Spacing.xSmall) {
                            if working { ProgressView().controlSize(.mini) }
                            Text(working ? "Bringing in" : "Bring into the hub")
                        }
                        .fixedSize()
                    }
                    .buttonStyle(KitButton(kind: .secondary))
                    .disabled(working)
                } else {
                    Text("A repository\u{2019}s own file")
                        .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                        .foregroundStyle(Memnox.Console.muted)
                }
            }
            if press != nil, !working {
                McpPressLine(press: press)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, ShellMetrics.rowPaddingH)
                    .padding(.bottom, ShellMetrics.rowPaddingV)
            }
        }
    }
}

/// Lines the hub wrote that a person changed since, left as they are and said.
private struct McpLeftAlone: View {
    let view: McpHubView

    var body: some View {
        let entries = view.drifted + view.skipped
        if !entries.isEmpty {
            ShellSection(title: "Left as they are") {
                ShellPanel {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        if index > 0 { ShellDivider() }
                        ShellRow(title: entry.name,
                                 caption: (entry.agent.map { "\(McpHubLines.agentLabel($0)) \u{00B7} " } ?? "") + McpHubLines.leftAlone(entry)) {
                            EmptyView()
                        } trailing: {
                            StatusWord(.attention, "Yours now")
                        }
                    }
                }
            }
        }
    }
}

/// Agents across, servers down: one place to see and change who has what.
private struct McpClients: View {
    @ObservedObject var screen: McpHubScreen
    let view: McpHubView
    let workspaces: () -> Void

    private static let logo: CGFloat = 18
    private static let column: CGFloat = 96

    var body: some View {
        if view.servers.isEmpty || view.agents.isEmpty {
            EmptyState(symbol: "powerplug", title: "Nothing to give yet",
                       detail: "Once the hub holds a server and an agent with an MCP config is found, who has what is set here.")
        } else {
            ShellPanel {
                ScrollView(.horizontal) {
                    Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                        GridRow {
                            header("Server").frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(view.agents, id: \.agent) { each in
                                HStack(spacing: Memnox.Spacing.small) {
                                    BrandLogo(agent: each.agent, name: McpHubLines.agentLabel(each.agent), size: Self.logo)
                                    header(McpHubLines.agentLabel(each.agent))
                                }
                                .frame(minWidth: Self.column)
                            }
                        }
                        .padding(.vertical, ShellMetrics.rowPaddingV)
                        ForEach(view.servers) { server in
                            ShellDivider().gridCellUnsizedAxes(.horizontal)
                            GridRow {
                                Text(server.name)
                                    .font(Memnox.Console.sans(Memnox.TextSize.body, .medium))
                                    .foregroundStyle(Memnox.Console.foreground)
                                    .lineLimit(1)
                                    .padding(.horizontal, ShellMetrics.rowPaddingH)
                                ForEach(view.agents, id: \.agent) { each in
                                    cell(server, each.agent).frame(minWidth: Self.column)
                                }
                            }
                            .padding(.vertical, ShellMetrics.rowPaddingV)
                        }
                    }
                }
                .scrollIndicators(.automatic)
            }
            if view.servers.contains(where: { !($0.projects ?? []).isEmpty }) {
                VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
                    Text(McpHubLines.projectOnlyLine)
                        .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                        .foregroundStyle(Memnox.Console.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    GoLink(McpHubLines.workspacesLink, action: workspaces)
                }
            }
        }
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(Memnox.Console.sans(Memnox.TextSize.footnote, .semibold))
            .foregroundStyle(Memnox.Console.muted)
            .lineLimit(1)
            .padding(.horizontal, ShellMetrics.rowPaddingH)
    }

    @ViewBuilder private func cell(_ server: McpHubServerView, _ agent: String) -> some View {
        if McpHubLines.reach(server, agent: agent) == .projects {
            // Unticked, since ticking gives it everywhere; the project assignment is changed in Workspaces.
            let help = McpHubLines.projectOnlyHelp(server, agent: agent)
            let everywhere = Binding(get: { false }, set: { want in
                if want { screen.press { await $0.assign(server.name, agent: agent, on: true) } }
            })
            HStack(spacing: Memnox.Spacing.small) {
                Toggle("", isOn: everywhere)
                    .labelsHidden()
                    .toggleStyle(CheckboxStyle())
                    .disabled(McpHubLines.fromOrganization(server) || screen.hub.busy == McpHub.pair(server.name, agent))
                    .help(McpHubLines.fromOrganization(server) ? McpHubLines.organizationLine : McpHubLines.giveEverywhere)
                    .accessibilityLabel("\(McpHubLines.giveEverywhere): \(server.name) for \(McpHubLines.agentLabel(agent))")
                Button(action: workspaces) {
                    HStack(spacing: Memnox.Spacing.small) { McpProjectChips(server: server, agent: agent) }
                }
                .buttonStyle(.plain)
                .help(help)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(help)
                .accessibilityAddTraits(.isButton)
            }
        } else {
            toggleCell(server, agent)
        }
    }

    private func toggleCell(_ server: McpHubServerView, _ agent: String) -> some View {
        let on = McpHubLines.reach(server, agent: agent) == .everywhere
        let given = Binding(get: { on }, set: { want in screen.press { await $0.assign(server.name, agent: agent, on: want) } })
        return HStack(spacing: Memnox.Spacing.small) {
            Toggle("", isOn: given)
                .labelsHidden()
                .toggleStyle(CheckboxStyle())
                .disabled(McpHubLines.fromOrganization(server) || screen.hub.busy == McpHub.pair(server.name, agent))
                .help(McpHubLines.fromOrganization(server) ? McpHubLines.organizationLine : "")
                .accessibilityLabel("\(server.name) for \(McpHubLines.agentLabel(agent))")
            McpProjectChips(server: server, agent: agent)
        }
    }
}

/// Every repository one agent was given a server in, each by folder name with the full path as its help, or nothing.
private struct McpProjectChips: View {
    let server: McpHubServerView
    let agent: String

    private static let icon: CGFloat = 9
    private static let widest: CGFloat = 140

    var body: some View {
        ForEach(McpHubLines.projects(server, agent: agent), id: \.path) { project in
            let help = McpHubLines.projectHelp(agent: agent, path: project.path)
            HStack(spacing: Memnox.Spacing.xxSmall) {
                Image(systemName: "folder").font(.system(size: Self.icon)).accessibilityHidden(true)
                Text(project.name).lineLimit(1).truncationMode(.middle)
            }
            .font(Memnox.Console.sans(Memnox.TextSize.micro))
            .foregroundStyle(Memnox.Console.muted)
            .padding(.horizontal, Memnox.Spacing.small)
            .padding(.vertical, Memnox.Spacing.xxSmall)
            .frame(maxWidth: Self.widest)
            .background(Memnox.Console.hover, in: Capsule())
            .overlay(Capsule().strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
            .help(help)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(help)
        }
    }
}

/// Each secret by name, where it is used and whether this computer holds it. A value is typed in once and never read back.
private struct McpSecrets: View {
    @ObservedObject var screen: McpHubScreen
    let view: McpHubView

    var body: some View {
        let secrets = McpHubLines.secretsAcross(view.servers)
        if secrets.isEmpty {
            EmptyState(symbol: "key", title: "No secrets yet",
                       detail: "When a server needs a token, mark it as a secret while adding the server. Its value stays with this computer and no agent\u{2019}s config ever holds it.")
        } else {
            ShellPanel {
                ForEach(Array(secrets.enumerated()), id: \.element.name) { index, secret in
                    if index > 0 { ShellDivider() }
                    McpSecretRow(screen: screen, secret: secret)
                }
            }
        }
    }
}

private struct McpSecretRow: View {
    @ObservedObject var screen: McpHubScreen
    let secret: HubSecret
    @State private var editing = false
    @State private var value = ""

    private static let fieldWidth: CGFloat = 200

    var body: some View {
        ShellRow(title: secret.name, caption: "Used by \(secret.usedBy.joined(separator: ", "))") {
            Image(systemName: "key").foregroundStyle(Memnox.Console.muted).accessibilityHidden(true)
        } trailing: {
            HStack(spacing: Memnox.Spacing.medium) {
                if editing {
                    SecureField("", text: $value)
                        .kitField()
                        .frame(width: Self.fieldWidth)
                        .onSubmit { if !value.isEmpty { save() } }
                        .accessibilityLabel("The value of \(secret.name)")
                    Button("Keep", action: save)
                        .buttonStyle(KitButton(kind: .primary))
                        .disabled(value.isEmpty || screen.hub.busy == secret.name)
                } else {
                    StatusWord(secret.held ? .good : .bad, secret.held ? "Kept" : "Not set")
                    Button(secret.held ? "Replace" : "Set") { editing = true }
                        .buttonStyle(KitButton(kind: .secondary))
                    if secret.held {
                        Button("Remove") { screen.press { await $0.removeSecret(secret.name) } }
                            .buttonStyle(KitButton(kind: .secondary))
                            .disabled(screen.hub.busy == secret.name)
                    }
                }
            }
        }
    }

    private func save() {
        let typed = value
        // The field is cleared at once, so the value lives here only as long as the press takes.
        value = ""
        editing = false
        screen.press { await $0.setSecret(secret.name, value: typed) }
    }
}
