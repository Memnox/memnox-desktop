import MemnoxVoiceCore
import ServiceManagement
import SwiftUI

/// Step one, on one card: the service installing and starting by itself, the Touch ID key, and the agents found here.
/// Continue opens as soon as the service runs, since the rest finishes behind it.
struct ConnectStep: View {
    @ObservedObject var flow: OnboardingFlow
    @ObservedObject var setup: SetupModel

    var body: some View {
        let ready = FirstRunLines.canContinueConnect(serviceRunning: setup.daemon == .done)
        StepTitle(title: "Connect your agents",
                  detail: "Memnox installs its service, makes your Touch ID key and finds your agents by itself. No account needed.")
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
            KitDivider()
            if let agents = AppWindow.shared.shell.agents {
                FoundAgents(screen: agents, setup: setup, home: SettingsWindow.shared.home)
            } else {
                InstalledAgents(setup: setup)
            }
        }
        Next(title: "Continue", flow: flow, disabled: !ready)
        if !ready {
            Text(FirstRunLines.connectWaiting)
                .font(Memnox.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var checkAgain: some View {
        Button("Check again", systemImage: "arrow.clockwise") { Task { await setup.check() } }.buttonStyle(KitButton(kind: .secondary))
    }
}

/// The agents the runtime found here, as rows of the connect card, each protected or one press from it.
private struct FoundAgents: View {
    @ObservedObject var screen: AgentsScreen
    @ObservedObject var setup: SetupModel
    let home: HomeModel?

    private static let logo: CGFloat = 26

    var body: some View {
        let found = screen.agents.agents
        VStack(alignment: .leading, spacing: 0) {
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
                    KitRow(symbol: "person.crop.circle.badge.questionmark", title: "No agent found yet",
                           detail: FirstRunLines.agentsFound(found)) {
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
private struct InstalledAgents: View {
    @ObservedObject var setup: SetupModel

    private static let logo: CGFloat = 26

    var body: some View {
        let installed = setup.agents.filter(\.installed)
        if installed.isEmpty {
            KitRow(symbol: "person.crop.circle.badge.questionmark", title: "Agents on this Mac", detail: "Looking for the agents on this Mac.") {
                ProgressView().controlSize(.small)
            }
        }
        ForEach(Array(installed.enumerated()), id: \.element.kind) { index, agent in
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

/// Step two: the servers and skills the agents already keep, every one ticked, brought into Memnox with one press.
struct WorkspaceStep: View {
    @ObservedObject var flow: OnboardingFlow

    var body: some View {
        StepTitle(title: "Bring in what your agents already use",
                  detail: "Their own tools and skills, kept once in Memnox and shared with the agents you choose. Everything is ticked for you.")
        if let hub = AppWindow.shared.shell.hub, let skills = AppWindow.shared.shell.skills {
            BringIn(flow: flow, hub: hub, skills: skills)
        } else {
            Next(title: "Continue", flow: flow)
        }
    }
}

/// What the agents already keep, grouped by agent so ninety skills read as a few agents: a search over every row, a
/// few rows each until Show all, every row ticked so any can be left where it is, and one Bring them in for the rest. The list
/// scrolls inside a bounded region, so the step never grows past the window however much was found.
private struct BringIn: View {
    @ObservedObject var flow: OnboardingFlow
    @ObservedObject var hub: McpHubScreen
    @ObservedObject var skills: SkillsScreen
    @State private var importing = false
    @State private var said: String?
    @State private var query = ""
    /// The rows the person unticked from the import, by id; empty means everything found goes in.
    @State private var leftOut: Set<String> = []
    /// The agents whose every row shows.
    @State private var expanded: Set<String> = []
    /// The list's own height, read off the list, so the region is only as tall as it needs up to the cap.
    @State private var contentHeight: CGFloat = 0

    private enum Layout {
        static let logo: CGFloat = 22
        /// Tall enough for two agents with a few rows each, short enough that Import stays above the fold.
        static let listHeight: CGFloat = 300
        /// One row's worth, so the region has a size before the list is first measured.
        static let minimumHeight: CGFloat = 32
    }

    /// The key the found line is said under, once in this first run.
    private static let foundKey = "workspace.found"

    var body: some View {
        let read = hub.hub.hub != nil || skills.skills.hub != nil
        let found = FirstRunLines.found(servers: hub.hub.hub?.found ?? [], skills: skills.skills.hub?.found ?? [])
        let kept = FoundList.kept(found, leaving: leftOut)
        let total = found.servers.count + found.skills.count
        let keeping = kept.servers.count + kept.skills.count
        KitCard(symbol: "square.stack.3d.up", title: read ? FirstRunLines.foundLine(found) : "Looking through your agents",
                detail: "Brought in, a tool runs behind Memnox, so everything it does is checked against your rules and recorded.") {
            if !read {
                ProgressView().controlSize(.small)
            } else if total > 0 {
                VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
                    if total > FoundList.collapsed {
                        SearchField(prompt: "Search \(total) skills and servers", text: $query)
                    }
                    chosenBar(keeping: keeping, of: total)
                    bounded(FoundList.groups(found, matching: query))
                }
                .disabled(importing || said != nil)
            }
        }
        .task {
            async let servers: Void = hub.hub.refresh()
            async let kept: Void = skills.skills.refresh()
            _ = await (servers, kept)
            let read = FirstRunLines.found(servers: hub.hub.hub?.found ?? [], skills: skills.skills.hub?.found ?? [])
            flow.sayOnce(FirstRunGuide.found(read), key: Self.foundKey)
        }
        if let said {
            Text(said)
                .font(Memnox.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                .fixedSize(horizontal: false, vertical: true)
        }
        if !found.isEmpty, said == nil {
            Button { Task { await importAll(kept) } } label: {
                Label(importing ? "Bringing them in" : FirstRunLines.bringIn, systemImage: "square.and.arrow.down")
            }
            .buttonStyle(KitButton(kind: .primary, wide: true))
            .keyboardShortcut(.defaultAction)
            .disabled(importing || keeping == 0)
            Button("Skip") { flow.next() }
                .buttonStyle(KitButton(kind: .secondary, wide: true))
        } else {
            Next(title: "Continue", flow: flow)
        }
    }

    /// How many go in, so a row left out shows in the count before the press.
    private func chosenBar(keeping: Int, of total: Int) -> some View {
        Text(FoundList.importTitle(kept: keeping, of: total))
            .font(Memnox.sans(Memnox.TextSize.footnote, .medium))
            .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
            .monospacedDigit()
    }

    /// The groups at their own height while they fit, and scrolled inside a region no taller than the cap once they
    /// do not, measured rather than guessed so a short list leaves no gap under it.
    private func bounded(_ groups: [FoundGroup]) -> some View {
        ScrollView {
            list(groups)
                .padding(.trailing, Memnox.Spacing.medium)
                .background(GeometryReader { inside in
                    Color.clear.preference(key: FoundListHeight.self, value: inside.size.height)
                })
        }
        .scrollIndicators(.visible)
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(max(contentHeight, Layout.minimumHeight), Layout.listHeight))
        .onPreferenceChange(FoundListHeight.self) { contentHeight = $0 }
    }

    @ViewBuilder private func list(_ groups: [FoundGroup]) -> some View {
        if groups.isEmpty {
            Text(FoundList.noMatch(query))
                .font(Memnox.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                .padding(.vertical, Memnox.Spacing.regular)
        } else {
            VStack(alignment: .leading, spacing: Memnox.Spacing.regular) {
                ForEach(groups) { group in
                    if group.id != groups.first?.id { KitDivider() }
                    section(group)
                }
            }
        }
    }

    /// One agent: its name with what it holds and a tick for all of it, a few rows, and Show all where there is more.
    private func section(_ group: FoundGroup) -> some View {
        let open = expanded.contains(group.id) || !query.trimmingCharacters(in: .whitespaces).isEmpty
        let ids = Set(group.items.map(\.id))
        let label = McpHubLines.agentLabel(group.agent)
        return VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
            HStack(spacing: Memnox.Spacing.medium) {
                BrandLogo(agent: group.agent, name: label, size: Layout.logo)
                VStack(alignment: .leading, spacing: 0) {
                    Text(label)
                        .font(Memnox.sans(Memnox.TextSize.callout, .semibold))
                        .foregroundStyle(Memnox.Palette.ink)
                    Text(FoundList.holds(group))
                        .font(Memnox.sans(Memnox.TextSize.footnote))
                        .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                }
                Spacer(minLength: Memnox.Spacing.small)
                Toggle("All of \(label)", isOn: Binding(
                    get: { leftOut.isDisjoint(with: ids) },
                    set: { all in if all { leftOut.subtract(ids) } else { leftOut.formUnion(ids) } }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help("Choose every one \(label) keeps")
            }
            ForEach(FoundList.shown(group, expanded: open)) { item in row(item) }
            if let more = FoundList.showAll(group, expanded: open) {
                Button(more, systemImage: "chevron.down") { withAnimation(.snappy) { _ = expanded.insert(group.id) } }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .font(Memnox.sans(Memnox.TextSize.footnote, .medium))
                    .foregroundStyle(Memnox.Palette.primary)
            } else if expanded.contains(group.id), group.items.count > FoundList.collapsed {
                Button("Show fewer", systemImage: "chevron.up") { withAnimation(.snappy) { _ = expanded.remove(group.id) } }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .font(Memnox.sans(Memnox.TextSize.footnote, .medium))
                    .foregroundStyle(Memnox.Palette.primary)
            }
        }
    }

    /// One server or skill with its tick, and what kind it is on the right.
    private func row(_ item: FoundItem) -> some View {
        HStack(spacing: Memnox.Spacing.medium) {
            Toggle(item.name, isOn: Binding(
                get: { !leftOut.contains(item.id) },
                set: { keep in if keep { leftOut.remove(item.id) } else { leftOut.insert(item.id) } }
            ))
            .toggleStyle(.checkbox)
            .font(Memnox.sans(Memnox.TextSize.footnote))
            .lineLimit(1)
            Spacer(minLength: Memnox.Spacing.small)
            Text(item.kind == .server ? "Tool" : "Skill")
                .font(Memnox.sans(Memnox.TextSize.caption))
                .foregroundStyle(Memnox.ink(Memnox.Ink.tertiary))
        }
        .padding(.leading, Layout.logo + Memnox.Spacing.medium)
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
        flow.setup?.guide(FirstRunGuide.imported(imported))
    }
}

/// The found list's height inside its scroll region.
private struct FoundListHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Step three: the recommended pack already chosen, the others one press away, and Finish proposing it through the
/// runtime so each rule is signed with Touch ID on the island.
struct BoundariesStep: View {
    @ObservedObject var flow: OnboardingFlow

    var body: some View {
        StepTitle(title: "Your starting rules",
                  detail: "We chose the pack we recommend. Nothing holds until you confirm each rule with Touch ID on the island.")
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
    /// The pack the person picked over the recommended one; nil keeps the recommended.
    @State private var picked: String?
    @State private var others = false
    @State private var failed: String?
    @State private var sending = false

    private static let radio: CGFloat = 16
    private static let ring: CGFloat = 2

    var body: some View {
        let packs = screen.studio.packs ?? []
        let recommended = FirstRunLines.recommendedPack(packs)
        let chosen = packs.first { $0.id == picked } ?? recommended
        KitCard(symbol: "checklist", title: "Recommended for you", detail: "A safe start. Change any rule later under Protection settings.") {
            if screen.studio.packs == nil {
                ProgressView().controlSize(.small)
            } else if let recommended {
                option(recommended, chosen: chosen)
                if others {
                    ForEach(FirstRunLines.otherPacks(packs), id: \.id) { each in
                        KitDivider()
                        option(each, chosen: chosen)
                    }
                } else if !FirstRunLines.otherPacks(packs).isEmpty {
                    Button("See other packs", systemImage: "chevron.down") { withAnimation(.snappy) { others = true } }
                        .buttonStyle(.plain)
                        .pointingHand()
                        .font(Memnox.sans(Memnox.TextSize.footnote, .medium))
                        .foregroundStyle(Memnox.Palette.primary)
                        .padding(.top, Memnox.Spacing.regular)
                }
            } else {
                Text("Memnox has no rule sets to pick from yet. The rules it starts with stay on.")
                    .font(Memnox.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { await screen.studio.readPacks() }
        if let failed {
            Text(failed)
                .font(Memnox.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                .fixedSize(horizontal: false, vertical: true)
        }
        if let chosen, failed == nil {
            Button { Task { await use(chosen) } } label: {
                HStack(spacing: Memnox.Spacing.small) {
                    Text(sending ? "Proposing \(chosen.name)" : "Finish")
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(KitButton(kind: .primary, wide: true))
            .keyboardShortcut(.defaultAction)
            .disabled(sending)
        } else {
            // Nothing to propose, or the proposal was refused and said so above; the rules Memnox starts with stay on.
            Next(title: "Finish", flow: flow)
        }
    }

    /// One pack as a radio row, with its rule count and what it is for.
    private func option(_ pack: RulePackView, chosen: RulePackView?) -> some View {
        let on = chosen?.id == pack.id
        return Button { picked = pack.id } label: {
            KitRow(symbol: "checklist", title: FirstRunLines.packTitle(pack), detail: pack.description) {
                Circle()
                    .strokeBorder(on ? Memnox.Palette.primary : Memnox.ink(Memnox.Ink.tertiary), lineWidth: Self.ring)
                    .background(Circle().fill(on ? Memnox.Palette.primary : Color.clear))
                    .frame(width: Self.radio, height: Self.radio)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHand()
        .disabled(sending)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    /// Proposes the pack through the runtime; its rules then wait on the island for Touch ID while the end shows.
    private func use(_ pack: RulePackView) async {
        sending = true
        let outcome = await screen.studio.importPack(pack.toml)
        sending = false
        switch outcome {
        case .failed(let why):
            failed = why
        case .proposed:
            flow.setup?.guide(FirstRunGuide.packProposed)
            flow.next()
        case .done:
            flow.next()
        }
    }
}

/// The end: one next action, talking when the microphone is allowed and Home otherwise, then a short list of what is
/// optional, each a link to the Settings page that holds it. The one thing left for the person, the microphone, is
/// said and shown once, with Allow beside it.
struct ReadyStep: View {
    @ObservedObject var flow: OnboardingFlow
    @ObservedObject var setup: SetupModel

    /// The key the permission hint is said under, once in this first run.
    private static let hintKey = "ready.permission"

    var body: some View {
        let hearing = setup.listening == .done
        let next = FirstRunEnd.next(hearing: hearing)
        StepTitle(title: FirstRunEnd.title(name: setup.name), detail: FirstRunEnd.lead)
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            switch next {
            case .talk:
                Button(next.title, systemImage: "mic.fill") { flow.menu?.talk() }
                    .buttonStyle(KitButton(kind: .primary, wide: true))
                    .keyboardShortcut(.defaultAction)
                Text(FirstRunEnd.talkHint)
                    .font(Memnox.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                Button(FirstRunNext.openHome.title) { open() }
                    .buttonStyle(KitButton(kind: .secondary, wide: true))
            case .openHome:
                Button(next.title, systemImage: "sparkles") { open() }
                    .buttonStyle(KitButton(kind: .primary, wide: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        KitCard(title: "Optional, in Settings") {
            ForEach(Array(FirstRunEnd.extras(hearing: hearing, signedIn: signedIn, phonePaired: paired).enumerated()),
                    id: \.element.id) { index, extra in
                if index > 0 { KitDivider() }
                KitRow(symbol: Self.symbol(extra.id), title: extra.title, detail: extra.detail,
                       hint: extra.id == .voice ? FirstRunEnd.permissionHint(hearing: hearing) : nil) {
                    trailing(extra)
                }
            }
        }
        .task {
            if let line = FirstRunEnd.permissionHint(hearing: hearing) { flow.sayOnce(line, key: Self.hintKey) }
            StartAtSignIn.turnOn()
        }
    }

    /// Allow for the microphone where it waits, a tick where the extra is in place, and a link to Settings otherwise.
    @ViewBuilder private func trailing(_ extra: FirstRunExtra) -> some View {
        if extra.id == .voice, !extra.done {
            Button("Allow", systemImage: "checkmark.shield") { Task { await setup.allowListening() } }
                .buttonStyle(KitButton(kind: .secondary))
        } else if extra.done {
            CheckBox(state: .done)
        } else {
            Button("Settings", systemImage: "arrow.up.forward") { openSettings(extra.id.settingsTab) }
                .buttonStyle(KitButton(kind: .secondary))
                .help("Open \(extra.title) in Settings")
        }
    }

    private static func symbol(_ id: FirstRunExtraId) -> String {
        switch id {
        case .voice: "waveform"
        case .keys: "keyboard"
        case .workspace: "building.2"
        case .phone: "iphone"
        }
    }

    private var signedIn: Bool {
        if case .signedIn = flow.account?.step { return true }
        return false
    }

    private var paired: Bool {
        if case .paired = setup.phone { return true }
        return false
    }

    /// Setup is done: the full screen scan of this Mac goes up, and closing it opens Memnox on Home.
    private func open() {
        setup.finish(scanning: true)
    }

    /// The Memnox window on one Settings page, beside this one, so the end stays to come back to.
    private func openSettings(_ tab: String) {
        SettingsWindow.shared.show()
        AppWindow.shared.shell.go(WindowRoute(.settings, tab: tab))
    }
}

/// Memnox opens when the person signs in, so a call that waits on them is never missed because it was closed. A safe
/// default turned on by itself at the end of the first run; macOS may refuse a copy outside Applications, which changes
/// nothing else, and the person can turn it off in System Settings under Login Items.
@MainActor
private enum StartAtSignIn {
    static func turnOn() {
        guard SMAppService.mainApp.status != .enabled else { return }
        try? SMAppService.mainApp.register()
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
