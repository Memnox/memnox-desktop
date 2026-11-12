import AppKit
import MemnoxVoiceCore
import ServiceManagement
import SwiftUI

/// Connect this machine, on one card: the service installing and starting by itself, the Touch ID key, and the agents
/// found here.
/// Continue opens as soon as the service runs, since the rest finishes behind it.
struct ConnectStep: View {
    @ObservedObject var flow: OnboardingFlow
    @ObservedObject var setup: SetupModel

    var body: some View {
        let ready = FirstRunLines.canContinueConnect(serviceRunning: setup.daemon == .done)
        StepTitle(title: FirstRunStepID.connect.title,
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
                FoundAgents(flow: flow, screen: agents, setup: setup, home: SettingsWindow.shared.home)
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

/// The agents the runtime found here, as rows of the connect card, each put under Memnox by itself once the service
/// runs, the way setup does, and one press from it again only where that did not go through.
private struct FoundAgents: View {
    @ObservedObject var flow: OnboardingFlow
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
        .task(id: unprotected) { await protectByItself() }
        if let failed = home?.protectFailed {
            Text(failed)
                .font(Memnox.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The agents found that still run outside Memnox, so a new one found later is put under it too.
    private var unprotected: [String] {
        (screen.agents.agents ?? []).filter { $0.agentStatus == .unprotected }.map(\.kind)
    }

    /// Puts what was found under Memnox once, with the same setup the service ran, while the service runs; a press of
    /// Protect stays for what that could not reach.
    private func protectByItself() async {
        guard !unprotected.isEmpty, !flow.autoProtected, setup.daemon == .done, let home, !home.remote() else { return }
        flow.autoProtected = true
        _ = await home.protectNow()
        await screen.agents.refresh()
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

/// Step two: the recommended pack already chosen, the others one press away, and Finish proposing it through the
/// runtime so each rule is signed with Touch ID on the island.
struct RulesStep: View {
    @ObservedObject var flow: OnboardingFlow

    var body: some View {
        StepTitle(title: FirstRunStepID.rules.title,
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
                        .foregroundStyle(Memnox.Console.primary)
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
                    .strokeBorder(on ? Memnox.Console.primary : Memnox.ink(Memnox.Ink.tertiary), lineWidth: Self.ring)
                    .background(Circle().fill(on ? Memnox.Console.primary : Color.clear))
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

/// The end, in the order a person acts on it: the prompt to try, the one button that opens Memnox, then what Memnox
/// covers and what is optional, both quiet. Nothing here opens the Memnox window but that button, since setup is
/// still on screen until it is pressed.
struct ReadyStep: View {
    @ObservedObject var flow: OnboardingFlow
    @ObservedObject var setup: SetupModel

    /// The key the permission hint is said under, once in this first run.
    private static let hintKey = "ready.permission"

    var body: some View {
        let hearing = setup.listening == .done
        StepTitle(title: FirstRunEnd.title(name: setup.name), detail: FirstRunEnd.lead)
        TryCard()
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            Button { open() } label: {
                HStack(spacing: Memnox.Spacing.small) {
                    Text(FirstRunNext.openHome.title)
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(KitButton(kind: .primary, wide: true))
            .keyboardShortcut(.defaultAction)
            if FirstRunEnd.next(hearing: hearing) == .talk {
                Button(FirstRunNext.talk.title, systemImage: "mic.fill") { flow.menu?.talk() }
                    .buttonStyle(KitButton(kind: .secondary, wide: true))
                    .help(FirstRunEnd.talkHint)
            }
            Text(FirstRunEnd.later)
                .font(Memnox.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                .fixedSize(horizontal: false, vertical: true)
        }
        CoverageCard()
        KitCard(title: "Optional, and you can skip all of it") {
            ForEach(Array(FirstRunEnd.extras(hearing: hearing).enumerated()),
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

    /// Allow for the microphone where it waits and a tick where the extra is in place; the keys are only read.
    @ViewBuilder private func trailing(_ extra: FirstRunExtra) -> some View {
        if extra.id == .voice, !extra.done {
            Button("Allow", systemImage: "checkmark.shield") { Task { await setup.allowListening() } }
                .buttonStyle(KitButton(kind: .secondary))
        } else if extra.done {
            CheckBox(state: .done)
        }
    }

    private static func symbol(_ id: FirstRunExtraId) -> String {
        switch id {
        case .voice: "waveform"
        case .keys: "keyboard"
        }
    }

    /// Setup is done: the full screen scan of this Mac goes up, and closing it opens Memnox on Home.
    private func open() {
        setup.finish(scanning: true)
    }
}

/// The one thing to try first: a prompt to paste into the agent that produces a real ask, so the first success is a
/// minute away rather than a day; the same words on every surface, from the contract's `tryPrompt`.
private struct TryCard: View {
    @State private var copied = false

    var body: some View {
        KitCard(symbol: "sparkles", title: FirstRunLines.tryTitle, detail: FirstRunLines.tryDetail) {
            HStack(spacing: Memnox.Spacing.medium) {
                Text(FirstRunLines.tryPrompt)
                    .font(Memnox.mono(Memnox.TextSize.footnote))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Memnox.Spacing.medium)
                Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(FirstRunLines.tryPrompt, forType: .string)
                    copied = true
                }
                .buttonStyle(KitButton(kind: .secondary))
            }
        }
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
