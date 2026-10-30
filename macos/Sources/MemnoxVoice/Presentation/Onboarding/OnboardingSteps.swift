import AppKit
import MemnoxVoiceCore
import ServiceManagement
import SwiftUI

/// Step one: the service, Touch ID, and the agents found here, each protected so it passes the boundaries first.
struct ConnectStep: View {
    @ObservedObject var flow: OnboardingFlow
    @ObservedObject var setup: SetupModel

    var body: some View {
        StepTitle(title: "Connect your agents",
                  detail: "Memnox starts its service on this Mac and puts itself under the agents you already use. No account needed.")
        KitCard(symbol: "desktopcomputer", title: "Memnox on this Mac", detail: "Installed under your agents and kept up to date for you.") {
            KitRow(title: "Memnox service", detail: setup.runtime.doing.map { "\($0)…" } ?? "Installed, started and updated for you.",
                   hint: hint(setup.daemon), leading: { MemnoxTile() }) {
                if setup.daemon == .done {
                    CheckBox(state: .done)
                } else if setup.runtime.doing != nil {
                    ProgressView().controlSize(.small)
                } else {
                    checkAgain
                }
            }
            KitDivider()
            KitRow(symbol: "touchid", title: "Approve with Touch ID", detail: "Your approval signs what agents ask. The key never leaves this Mac.",
                   hint: hint(setup.key)) {
                if setup.key == .done { CheckBox(state: .done) } else { checkAgain }
            }
        }
        if let agents = AppWindow.shared.shell.agents {
            FoundAgents(screen: agents, setup: setup, home: SettingsWindow.shared.home)
        } else {
            FoundAgentsFallback(setup: setup)
        }
        Next(title: "Continue", flow: flow)
    }

    private var checkAgain: some View {
        Button("Check again", systemImage: "arrow.clockwise") { Task { await setup.check() } }.buttonStyle(KitButton(kind: .secondary))
    }
}

/// The agents the runtime found here, each protected or one press from it.
private struct FoundAgents: View {
    @ObservedObject var screen: AgentsScreen
    @ObservedObject var setup: SetupModel
    let home: HomeModel?

    private static let logo: CGFloat = 26

    var body: some View {
        let found = screen.agents.agents
        KitCard(symbol: "person.crop.circle.badge.questionmark", title: "Agents on this Mac",
                detail: found.map(FirstRunLines.agentsFound) ?? "Looking for the agents on this Mac.") {
            if let found {
                ForEach(Array(found.enumerated()), id: \.element.kind) { index, agent in
                    if index > 0 { KitDivider() }
                    KitRow(title: agent.name, detail: FirstRunLines.agentDetail(agent),
                           leading: { BrandLogo(agent: agent.kind, name: agent.name, size: Self.logo) }) {
                        if agent.agentStatus == .unprotected, let home {
                            ProtectAgents(home: home) { Task { await screen.agents.refresh() } }
                        } else {
                            CheckBox(state: .done)
                        }
                    }
                }
                if found.isEmpty {
                    KitRow(symbol: "person.crop.circle.badge.questionmark", title: "No agent found yet", detail: "Install one, then check again.") {
                        Button("Check again") { Task { await screen.agents.refresh() } }.buttonStyle(KitButton(kind: .secondary))
                    }
                }
            } else {
                // Before the agents method answers, the agents the voice found stand in, so a fresh Mac still shows its agents.
                InstalledAgents(setup: setup)
            }
        }
        .task { await screen.agents.refresh() }
    }
}

/// The agents the voice found, when this Mac's runtime has no agents method to ask.
private struct FoundAgentsFallback: View {
    @ObservedObject var setup: SetupModel

    var body: some View {
        KitCard(symbol: "person.crop.circle.badge.questionmark", title: "Agents on this Mac", detail: "Looking for the agents on this Mac.") {
            InstalledAgents(setup: setup)
        }
    }
}

private struct InstalledAgents: View {
    @ObservedObject var setup: SetupModel

    private static let logo: CGFloat = 26

    var body: some View {
        ForEach(Array(setup.agents.filter(\.installed).enumerated()), id: \.element.kind) { index, agent in
            if index > 0 { KitDivider() }
            KitRow(title: agent.label, detail: "Found on this Mac.", leading: { BrandLogo(agent: agent.kind, name: agent.label, size: Self.logo) }) {
                EmptyView()
            }
        }
    }
}

/// The home's own Protect press, which hooks every agent found on this Mac into Memnox the way setup does.
private struct ProtectAgents: View {
    @ObservedObject var home: HomeModel
    let done: () -> Void

    var body: some View {
        Button(home.protecting ? "Protecting" : "Protect", action: home.protect)
            .buttonStyle(KitButton(kind: .secondary))
            .disabled(home.protecting)
            .onChange(of: home.protecting) { _, protecting in if !protecting { done() } }
    }
}

/// Step two: the servers and skills the agents already keep, brought into Memnox with one tap.
struct WorkspaceStep: View {
    @ObservedObject var flow: OnboardingFlow

    var body: some View {
        StepTitle(title: "Set up your workspace",
                  detail: "Your agents already have servers and skills of their own. Bring them in once, and give each to the agents you choose.")
        if let hub = AppWindow.shared.shell.hub, let skills = AppWindow.shared.shell.skills {
            BringIn(flow: flow, hub: hub, skills: skills)
        } else {
            Next(title: "Continue", flow: flow)
        }
    }
}

private struct BringIn: View {
    @ObservedObject var flow: OnboardingFlow
    @ObservedObject var hub: McpHubScreen
    @ObservedObject var skills: SkillsScreen
    @State private var importing = false
    @State private var said: String?

    private static let logo: CGFloat = 26

    var body: some View {
        let read = hub.hub.hub != nil || skills.skills.hub != nil
        let found = FirstRunLines.found(servers: hub.hub.hub?.found ?? [], skills: skills.skills.hub?.found ?? [])
        KitCard(symbol: "square.stack.3d.up", title: read ? FirstRunLines.foundLine(found) : "Looking through your agents",
                detail: "Brought in, a server runs behind Memnox so every call it makes is ruled on and recorded.") {
            ForEach(Array(found.servers.enumerated()), id: \.offset) { index, server in
                if index > 0 { KitDivider() }
                KitRow(title: server.name, detail: "MCP server in \(McpHubLines.agentLabel(server.agent))",
                       leading: { BrandLogo(agent: server.agent, name: McpHubLines.agentLabel(server.agent), size: Self.logo) }) { EmptyView() }
            }
            ForEach(Array(found.skills.enumerated()), id: \.element.id) { index, skill in
                if index > 0 || !found.servers.isEmpty { KitDivider() }
                KitRow(title: skill.name, detail: "Skill in \(McpHubLines.agentLabel(skill.agent))",
                       leading: { BrandLogo(agent: skill.agent, name: McpHubLines.agentLabel(skill.agent), size: Self.logo) }) { EmptyView() }
            }
            if !read { ProgressView().controlSize(.small) }
        }
        .task {
            async let servers: Void = hub.hub.refresh()
            async let kept: Void = skills.skills.refresh()
            _ = await (servers, kept)
        }
        if let said {
            Text(said)
                .font(Memnox.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                .fixedSize(horizontal: false, vertical: true)
        }
        if !found.isEmpty, said == nil {
            Button { Task { await importAll(found) } } label: {
                Label(importing ? "Bringing them in" : "Import all", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(KitButton(kind: .primary, wide: true))
            .keyboardShortcut(.defaultAction)
            .disabled(importing)
            Button("Not now") { flow.next() }
                .buttonStyle(KitButton(kind: .secondary, wide: true))
        } else {
            Next(title: "Continue", flow: flow)
        }
    }

    /// Each one is its own request, so one that fails leaves the rest brought in.
    private func importAll(_ found: FoundToImport) async {
        importing = true
        var imported = 0
        var failed: [String] = []
        for server in found.servers {
            if case .failed(let why) = await hub.hub.importServer(agent: server.agent, server: server.name) {
                failed.append("\(server.name): \(why)")
            } else {
                imported += 1
            }
        }
        for skill in found.skills {
            if case .failed(let why) = await skills.skills.importFound(id: skill.id, name: skill.name) {
                failed.append("\(skill.name): \(why)")
            } else {
                imported += 1
            }
        }
        importing = false
        said = FirstRunLines.importedLine(imported, failed: failed)
    }
}

/// Step three: a pack of rules to start from, each rule proposed and signed on the island one by one.
struct BoundariesStep: View {
    @ObservedObject var flow: OnboardingFlow

    var body: some View {
        StepTitle(title: "Choose your boundaries",
                  detail: "Pick the rules your agents start under. Nothing holds until you confirm each rule with Touch ID on the island.")
        if let studio = AppWindow.shared.shell.studio {
            RulePacks(flow: flow, screen: studio)
        } else {
            Next(title: "Finish", flow: flow)
        }
    }
}

private struct RulePacks: View {
    @ObservedObject var flow: OnboardingFlow
    @ObservedObject var screen: StudioScreen
    @State private var chosen: String?
    @State private var said: String?
    @State private var sending = false

    private static let radio: CGFloat = 16
    private static let ring: CGFloat = 2

    var body: some View {
        let packs = screen.studio.packs
        let pack = packs?.first { $0.id == chosen }
        let imported = said != nil && !sending
        KitCard(symbol: "checklist", title: "Rule packs", detail: "Each is a starting point. Change any rule later under Governance.") {
            if let packs {
                if packs.isEmpty {
                    Text("This runtime ships no packs yet. The rules it starts with stay in force.")
                        .font(Memnox.sans(Memnox.TextSize.footnote))
                        .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(packs.enumerated()), id: \.element.id) { index, each in
                    if index > 0 { KitDivider() }
                    Button { chosen = each.id } label: {
                        KitRow(symbol: "checklist", title: FirstRunLines.packTitle(each), detail: each.description) {
                            Circle()
                                .strokeBorder(chosen == each.id ? Memnox.Palette.primary : Memnox.ink(Memnox.Ink.tertiary), lineWidth: Self.ring)
                                .background(Circle().fill(chosen == each.id ? Memnox.Palette.primary : Color.clear))
                                .frame(width: Self.radio, height: Self.radio)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .disabled(imported)
                    .accessibilityAddTraits(chosen == each.id ? [.isButton, .isSelected] : .isButton)
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task { await screen.studio.readPacks() }
        if let said {
            Text(said)
                .font(Memnox.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                .fixedSize(horizontal: false, vertical: true)
        }
        if let pack, !imported {
            Button { Task { await use(pack) } } label: { Label("Use \(pack.name)", systemImage: "checkmark") }
                .buttonStyle(KitButton(kind: .primary, wide: true))
                .keyboardShortcut(.defaultAction)
                .disabled(sending)
        } else {
            Next(title: "Finish", flow: flow)
        }
    }

    private func use(_ pack: RulePackView) async {
        sending = true
        let outcome = await screen.studio.importPack(pack.toml)
        sending = false
        switch outcome {
        case .failed(let why): said = why
        case .proposed: said = "Waiting for you on the island."
        case .done(let line): said = line
        }
    }
}

/// After the three steps, all optional: the permissions to talk, the voice, the apps the agents run in, starting at
/// sign in, who answers, three keys to try, the workspace and the iPhone.
struct OptionalStep: View {
    @ObservedObject var flow: OnboardingFlow
    @ObservedObject var setup: SetupModel

    var body: some View {
        StepTitle(title: greeting, detail: "Your agents work inside your boundaries now. Everything below is optional, and waits in Settings.")
        KitCard(symbol: "lock.shield", title: "Talk to Memnox", detail: "Used only when you talk or approve.") {
            TalkPermissions(setup: setup)
            KitDivider()
            // The voice downloads here, so Settings never shows it still installing after.
            KitRow(symbol: "waveform", title: "Voice", detail: setup.voiceDetail, hint: hint(setup.voiceState)) {
                voiceControl
            }
            KitDivider()
            StartAtSignInRow()
        }
        AgentHomesSetup()
        // Its own card, so which agent answers reads apart from what Memnox installed.
        KitCard(symbol: "person.wave.2", title: "Who answers when you talk", detail: setup.agentsDetail) {
            AgentChecks(setup: setup)
            if setup.agents.filter(\.installed).isEmpty {
                // An empty list is the daemon not answering far more often than a Mac with no agent, so it says which.
                KitRow(symbol: "person.crop.circle.badge.questionmark", title: setup.agents.isEmpty ? "Your agents" : "No agent found yet",
                       detail: hint(setup.agentsState) ?? "Looking for the agents on this Mac.") {
                    Button("Check again", systemImage: "arrow.clockwise") { Task { await setup.loadAgents(recheck: true) } }
                        .buttonStyle(KitButton(kind: .secondary))
                        .disabled(setup.checkingAgents)
                }
            }
        }
        KitCard(symbol: "keyboard", title: "Three keys to try", detail: "Memnox answers in the notch.") {
            KitRow(symbol: "mic", title: "Ask out loud", detail: "Press, talk, and let go.") {
                HStack(spacing: Memnox.Spacing.medium) {
                    Keys(["\u{2325}", "Space"])
                    Button("Try it", systemImage: "play.fill") { flow.menu?.talk() }.buttonStyle(KitButton(kind: .secondary))
                }
            }
            KitDivider()
            KitRow(symbol: "text.badge.checkmark", title: "Say a rule", detail: "Hold, and say never deploy on Fridays.") {
                HStack(spacing: Memnox.Spacing.medium) {
                    Keys(["\u{2303}", "\u{2325}"])
                    Button("Try it", systemImage: "play.fill") { flow.menu?.sayRule() }.buttonStyle(KitButton(kind: .secondary))
                }
            }
            KitDivider()
            KitRow(symbol: "keyboard", title: "Dictate anywhere", detail: "Hold, speak, and it types where your cursor is.") {
                Keys(["Right \u{2325}"])
            }
        }
        if let tools = flow.menu?.tools {
            SuggestedApps(tools: tools)
        }
        KitCard(symbol: "building.2", title: "Your workspace and your phone", detail: "Sign in to your workspace or pair your iPhone. Both wait in Settings.") {
            // First, since the rules, the workspace memory and a paired phone all come to this Mac through it.
            if let account = flow.account {
                if let daemon = account.daemon, let machine = account.machine {
                    AccountSignIn(account: account, daemon: daemon, machine: machine)
                }
                KitDivider()
            }
            PhonePairing(setup: setup)
        }
        // The app delegate owns the Kokoro download and switches to it when it lands, so finishing never waits on it.
        Button("Start using Memnox", systemImage: "sparkles") { setup.finish() }
            .buttonStyle(KitButton(kind: .primary, wide: true))
            .keyboardShortcut(.defaultAction)
    }

    private var greeting: String {
        let name = setup.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "You're set." : "You're set, \(name)."
    }

    /// The tick once Kokoro is in, a spinner while it downloads, and a way to try again when it could not.
    @ViewBuilder private var voiceControl: some View {
        switch setup.kokoro.state {
        case .done:
            CheckBox(state: .done)
        case .installing, .idle:
            ProgressView().controlSize(.small)
        case .failed:
            Button("Try again", systemImage: "arrow.clockwise") { Task { await setup.useKokoro?() } }.buttonStyle(KitButton(kind: .secondary))
        }
    }
}

/// The three grants talking needs, each with the steps to its switch once Allow was not enough.
private struct TalkPermissions: View {
    @ObservedObject var setup: SetupModel

    var body: some View {
        KitRow(symbol: "mic", title: "Hear you", detail: "Microphone and speech recognition.", hint: hint(setup.listening)) {
            grant(setup.listening) { Task { await setup.allowListening() } }
        }
        KitDivider()
        KitRow(symbol: "keyboard", title: "Type for you",
               detail: "Accessibility, so a follow up lands in the agent's own app.") {
            grant(setup.typing, asking: setup.isAsking(.typing)) { setup.allowTyping() }
        }
        // Only once Allow was not enough do the steps appear, under the row and as wide as it.
        if case .needs = setup.typing {
            guide(.typing) {
                // Start over clears an earlier copy's switch, which shows on and does nothing.
                Button("Start over", systemImage: "arrow.counterclockwise") { Task { await setup.askAgain(.typing) } }
                    .buttonStyle(KitButton(kind: .secondary))
                    .disabled(setup.isAsking(.typing))
            }
        }
        KitDivider()
        KitRow(symbol: "rectangle.dashed.badge.record", title: "See your screen",
               detail: "Screen Recording, so it can read the window you ask about and check that words landed.") {
            grant(setup.seeing, asking: setup.isAsking(.seeing)) { setup.allowSeeing() }
        }
        if case .needs = setup.seeing {
            guide(.seeing) {
                // macOS hands the grant over only to the next start, so restarting is the last step; after a
                // restart that did not take, the switch is an earlier copy's and Start over clears it.
                if !setup.seeingStale {
                    Button("Restart Memnox", systemImage: "arrow.clockwise") { setup.reopen() }
                        .buttonStyle(KitButton(kind: .primary))
                }
                Button("Start over", systemImage: "arrow.counterclockwise") { Task { await setup.askAgain(.seeing) } }
                    .buttonStyle(KitButton(kind: setup.seeingStale ? .primary : .secondary))
                    .disabled(setup.isAsking(.seeing))
            }
        }
    }

    /// The steps and the picture of the switch to flip, set in under the row's words.
    private func guide<Actions: View>(_ pane: SettingsPane, @ViewBuilder actions: @escaping () -> Actions) -> some View {
        PermissionGuide(pane: pane, steps: setup.steps(for: pane), actions: actions)
            .padding(.leading, Kit.tileSide + Memnox.Spacing.large)
            .padding(.bottom, Memnox.Spacing.regular)
    }

    /// Allow until it is granted, then the checkbox.
    @ViewBuilder private func grant(_ state: StepState, _ action: @escaping () -> Void) -> some View {
        if state == .done {
            CheckBox(state: .done)
        } else {
            Button("Allow", systemImage: "checkmark.shield", action: action).buttonStyle(KitButton(kind: .secondary))
        }
    }

    /// Allow at first, a quiet wait while macOS is asked or the switch is still off, and the checkbox once it holds.
    @ViewBuilder private func grant(_ state: StepState, asking: Bool, _ action: @escaping () -> Void) -> some View {
        switch state {
        case .done: CheckBox(state: .done)
        case .waiting where !asking:
            Button("Allow", systemImage: "checkmark.shield", action: action).buttonStyle(KitButton(kind: .secondary))
        case .waiting, .needs:
            HStack(spacing: Memnox.Spacing.small) {
                ProgressView().controlSize(.small)
                Text("Waiting")
                    .font(Memnox.sans(Memnox.TextSize.footnote, .medium))
                    .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
            }
        }
    }
}

/// Memnox opened at sign in, so a call that waits on the person is never missed because it was closed.
private struct StartAtSignInRow: View {
    @State private var on = SMAppService.mainApp.status == .enabled
    @State private var failed: String?

    var body: some View {
        KitRow(symbol: "power", title: "Start when you sign in",
               detail: "So a call that waits on you is never missed because Memnox was closed.", hint: failed) {
            if on {
                CheckBox(state: .done)
            } else {
                Button("Turn on") { turnOn() }.buttonStyle(KitButton(kind: .secondary))
            }
        }
    }

    private func turnOn() {
        do {
            try SMAppService.mainApp.register()
            on = SMAppService.mainApp.status == .enabled
            failed = nil
        } catch {
            // Said on the row rather than thrown, since macOS can refuse a copy of Memnox outside Applications.
            failed = "macOS did not add Memnox to your login items: \(error.localizedDescription)"
        }
    }
}

/// Pair, the code to scan, the digits to compare, and the phone once paired.
private struct PhonePairing: View {
    @ObservedObject var setup: SetupModel

    private enum Layout {
        static let qrSide: CGFloat = 132
        static let quietZone: CGFloat = 8
        static let codeSize: CGFloat = 24
    }

    var body: some View {
        switch setup.phone {
        case .idle, .failed:
            KitRow(symbol: "qrcode", title: "Pair your iPhone", detail: "Scan a code with the Memnox app.", hint: hint(setup.phoneState)) {
                Button("Pair", systemImage: "qrcode") { Task { await setup.pairPhone() } }.buttonStyle(KitButton(kind: .secondary))
            }
        case .opening:
            KitRow(symbol: "qrcode", title: "Opening a pairing") { ProgressView().controlSize(.small) }
        case .showing(let qr):
            HStack(alignment: .center, spacing: Memnox.Spacing.xLarge) {
                if let image = QRImage.make(qr) {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: Layout.qrSide, height: Layout.qrSide)
                        .padding(Layout.quietZone)
                        .background(RoundedRectangle(cornerRadius: Kit.tileRadius, style: .continuous).fill(Color.white))
                }
                VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
                    Text("Scan this with the Memnox app on your iPhone.")
                        .font(Memnox.sans(Memnox.TextSize.body))
                        .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Memnox.Spacing.medium) {
                        Button("Copy link", systemImage: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(qr, forType: .string)
                        }
                        .buttonStyle(KitButton(kind: .secondary))
                        Button("Cancel", systemImage: "xmark") { Task { await setup.declinePhone() } }.buttonStyle(KitButton(kind: .secondary))
                    }
                }
            }
            .padding(.vertical, Memnox.Spacing.regular)
        case .checking(let phone), .approving(let phone):
            VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
                Text(phone.name).font(Memnox.sans(Memnox.TextSize.callout, .semibold)).foregroundStyle(Memnox.Palette.ink)
                Text(grouped(phone.code))
                    .font(Memnox.mono(Layout.codeSize, .semibold))
                    .foregroundStyle(Memnox.Palette.ink)
                    .textSelection(.enabled)
                Text("Approve if your iPhone shows the same digits.")
                    .font(Memnox.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                HStack(spacing: Memnox.Spacing.medium) {
                    // No Return shortcut, since letting a phone in must be a click made after comparing the digits.
                    Button("Approve", systemImage: "checkmark") { Task { await setup.approvePhone() } }.buttonStyle(KitButton(kind: .primary))
                    Button("Decline", systemImage: "xmark") { Task { await setup.declinePhone() } }.buttonStyle(KitButton(kind: .secondary))
                }
                .disabled(approving)
            }
            .padding(.vertical, Memnox.Spacing.regular)
        case .paired(let name):
            KitRow(symbol: "iphone", title: name, detail: "Paired. Questions reach it with Face ID.") { CheckBox(state: .done) }
        }
    }

    private var approving: Bool {
        if case .approving = setup.phone { return true }
        return false
    }

    /// "482913" as "482 913", so six digits read at a glance.
    private func grouped(_ digits: String) -> String {
        guard digits.count > 3 else { return digits }
        return "\(digits.prefix(3)) \(digits.dropFirst(3))"
    }
}

/// The one sign in: a single approval in the browser signs in this app and Memnox on this Mac, and connects
/// this Mac to the workspace, which carries the rules, the workspace memory and phone pairing.
private struct AccountSignIn: View {
    @ObservedObject var account: AccountModel
    @ObservedObject var daemon: DaemonAccountModel
    @ObservedObject var machine: DaemonAccountModel

    private var whole: AccountWhole { AccountWhole.of(account.step, daemon: daemon, machine: machine) }

    /// The code as large as the phone's digits, since both are read off the screen and typed or compared.
    private static let codeSize: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            KitRow(symbol: "building.2", title: title, detail: whole.detail, hint: hint) {
                switch whole {
                case .signedOut, .failed:
                    Button("Sign in", systemImage: "person.crop.circle") { account.start() }.buttonStyle(KitButton(kind: .secondary))
                case .working:
                    ProgressView().controlSize(.small)
                case .showingCode:
                    Button("Cancel", systemImage: "xmark") { account.cancel() }.buttonStyle(KitButton(kind: .secondary))
                case .incomplete:
                    Button("Finish", systemImage: "checkmark.circle") { account.finish() }.buttonStyle(KitButton(kind: .secondary))
                case .tooOld(let model):
                    UpdateButton(model: model)
                case .signedIn:
                    CheckBox(state: .done)
                }
            }
            if let code = whole.code {
                // The code with what to do with it, so it never sits on the page as a bare string.
                VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                    Text(code)
                        .font(Memnox.mono(Self.codeSize, .semibold))
                        .foregroundStyle(Memnox.Palette.ink)
                        .textSelection(.enabled)
                    Text(WorkspaceLines.enterCode(code))
                        .font(Memnox.sans(Memnox.TextSize.footnote))
                        .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, Kit.tileSide + Memnox.Spacing.large)
                .padding(.bottom, Memnox.Spacing.regular)
            }
        }
        .task {
            await daemon.refresh()
            await machine.refresh()
        }
    }

    private var title: String {
        if case .signedOut = whole { return "Sign in to your workspace" }
        return whole.title
    }

    private var hint: String? {
        if case .needs(let why) = whole.state { return why }
        return nil
    }
}

/// The keys of a shortcut, printed as keycaps.
private struct Keys: View {
    let labels: [String]

    init(_ labels: [String]) { self.labels = labels }

    var body: some View {
        HStack(spacing: Memnox.Spacing.xxSmall) { ForEach(labels, id: \.self) { Keycap(label: $0) } }
    }
}

/// The step's one button forward, the same on every step.
struct Next: View {
    let title: String
    @ObservedObject var flow: OnboardingFlow
    /// Held while something the step needs is still on its way.
    var disabled = false

    var body: some View {
        Button { flow.next() } label: {
            // The arrow trails the word, the way a step forward reads.
            HStack(spacing: Memnox.Spacing.small) {
                Text(title)
                Image(systemName: "arrow.right")
            }
        }
        .buttonStyle(KitButton(kind: .primary, wide: true))
        .keyboardShortcut(.defaultAction)
        .disabled(disabled)
    }
}

/// What a step needs from the person, in words, or nothing once it is done.
private func hint(_ state: StepState) -> String? {
    if case .needs(let why) = state { return why }
    return nil
}
