import AppKit
import MemnoxVoiceCore
import SwiftUI

/// What Memnox does, as the first thing read, each part lit while the notch beside it plays that part.
struct WelcomeStep: View {
    @ObservedObject var flow: OnboardingFlow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Shade {
        /// The parts not playing stay readable, only quieter.
        static let resting = 0.55
    }

    var body: some View {
        StepTitle(title: "Welcome to Memnox",
                  detail: "Let AI agents work autonomously. Keep their actions within your boundaries.")
        KitCard {
            ForEach(Highlight.allCases) { part in
                if part != Highlight.allCases.first { KitDivider() }
                // Each part is a button, so the person plays the one they care about on the notch and hears it.
                Button { flow.pick(part) } label: {
                    KitRow(symbol: part.symbol, title: part.title, detail: part.detail) {
                        Image(systemName: part == flow.highlight ? "play.fill" : "play")
                            .font(.system(size: Memnox.TextSize.footnote))
                            .foregroundStyle(part == flow.highlight ? Memnox.Palette.primary : Memnox.ink(Memnox.Ink.tertiary))
                            .accessibilityLabel(part == flow.highlight ? "playing now" : "play")
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHand()
                .help("Play this on the notch")
                .opacity(flow.highlight == nil || part == flow.highlight ? 1 : Shade.resting)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: Memnox.Motion.standard), value: flow.highlight)
        // Said before setup starts, so nobody goes looking for a key: the thinking is the person's own agent's.
        KitCard(symbol: "person.badge.key", title: "Works through your own agent",
                detail: "Memnox has no model of its own. It answers through an agent you already use, such as Claude Code, Codex, Cursor or Hermes, signed in with that agent's own account. No API key to bring.") {
            EmptyView()
        }
        Next(title: "Set up this Mac", flow: flow)
    }
}

/// Everything this Mac needs on one page: the four grants, and Memnox installed under the agents it found.
struct ThisMacStep: View {
    @ObservedObject var flow: OnboardingFlow
    @ObservedObject var setup: SetupModel

    var body: some View {
        StepTitle(title: "Set up this Mac",
                  detail: "Four permissions, asked once, and Memnox installs itself and its voice under your agents.")
        KitCard(symbol: "lock.shield", title: "Permissions", detail: "Used only when you talk or approve.") {
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
            KitDivider()
            KitRow(symbol: "touchid", title: "Approve with Touch ID", detail: "Your fingerprint approves what agents ask. The key never leaves this Mac.",
                   hint: hint(setup.key)) {
                if setup.key == .done { CheckBox(state: .done) } else { checkAgain }
            }
        }
        KitCard(symbol: "desktopcomputer", title: "Memnox on this Mac", detail: setup.agentsDetail) {
            KitRow(title: "Memnox service", detail: setup.runtime.doing.map { "\($0)…" } ?? "Installed, started and updated for you.",
                   hint: hint(setup.daemon), leading: { MemnoxTile() }) {
                if setup.daemon == .done { CheckBox(state: .done) } else { checkAgain }
            }
            KitDivider()
            // The voice downloads here, during the first run, so Settings never shows it still installing after.
            KitRow(symbol: "waveform", title: "Voice", detail: setup.voiceDetail, hint: hint(setup.voiceState)) {
                voiceControl
            }
            // Said here so nobody learns of the extension from an error later: the daemon puts it in on its own.
            if setup.editorsPresent {
                KitDivider()
                KitRow(symbol: "terminal", title: "Memnox in your editor", detail: editorDetail) {
                    if setup.editorsWithExtension.isEmpty { ProgressView().controlSize(.small) } else { CheckBox(state: .done) }
                }
            }
            ForEach(setup.agents.filter(\.installed)) { agent in
                KitDivider()
                KitRow(title: agent.label, detail: status(agent), leading: {
                    BrandLogo(agent: agent.kind, name: agent.label, size: Kit.tileSide)
                }, trailing: {
                    if agent.chosen {
                        CheckBox(state: .done)
                    } else if agent.works == true {
                        Button("Use", systemImage: "checkmark") { Task { await setup.useAgent(agent.kind) } }.buttonStyle(KitButton(kind: .secondary))
                    }
                })
            }
            if setup.agents.filter(\.installed).isEmpty {
                KitDivider()
                // An empty list is the daemon not answering far more often than a Mac with no agent, so it says which.
                KitRow(symbol: "person.crop.circle.badge.questionmark", title: setup.agents.isEmpty ? "Your agents" : "No agent found yet",
                       detail: hint(setup.agentsState) ?? "Looking for the agents on this Mac.") {
                    Button("Check again", systemImage: "arrow.clockwise") { Task { await setup.loadAgents(recheck: true) } }
                        .buttonStyle(KitButton(kind: .secondary))
                        .disabled(setup.checkingAgents)
                }
            }
        }
        // The voice is part of this Mac being set up, so the step holds until it is in.
        Next(title: setup.voiceStillComing ? "Installing the voice" : "Continue", flow: flow, disabled: setup.voiceStillComing)
    }

    private var checkAgain: some View {
        Button("Check again", systemImage: "arrow.clockwise") { Task { await setup.check() } }.buttonStyle(KitButton(kind: .secondary))
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

    /// The daemon's extension for VS Code, Cursor and Windsurf, which lets the voice reach a session's own tab.
    private var editorDetail: String {
        setup.editorsWithExtension.isEmpty
            ? "The Memnox terminals extension goes into VS Code, Cursor and Windsurf by itself, so your voice reaches the session's own tab."
            : "The Memnox terminals extension is in, so your voice reaches the session's own tab. Restart the editor if it was open."
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

    private func status(_ agent: VoiceAgentStatus) -> String {
        guard let works = agent.works else { return setup.checkingAgents ? "Asking" : "Not asked yet" }
        if !works { return agent.because ?? "Did not answer" }
        return agent.chosen ? "Answers when you talk, kept to reading" : "Can answer when you talk"
    }
}

/// The two keys to try, the iPhone and the sign in for whoever wants them now, and the button that starts Memnox.
/// The voice, waking by name and speaking up keep their defaults and live in Settings, so nobody decides them here.
struct ReadyStep: View {
    @ObservedObject var flow: OnboardingFlow
    @ObservedObject var setup: SetupModel

    var body: some View {
        StepTitle(title: greeting, detail: "Hand an agent the task and close your laptop. Everything inside your boundary runs on its own, and the one thing outside it finds you on your phone.")
        KitCard(symbol: "keyboard", title: "Two keys to try", detail: "Memnox answers in the notch.") {
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
        }
        KitCard(symbol: "building.2", title: "Optional", detail: "Your workspace and your iPhone. Both wait in Settings.") {
            // First, since the rules, the workspace memory and a paired phone all come to this Mac through it.
            if let account = flow.account {
                if let daemon = account.daemon, let machine = account.machine {
                    AccountSignIn(account: account, daemon: daemon, machine: machine)
                }
                KitDivider()
            }
            PhonePairing(setup: setup)
        }
        // Memnox starts with its voice in place, so the button waits for the download begun on the step before.
        Button(setup.voiceStillComing ? "Installing the voice first" : "Start using Memnox",
               systemImage: setup.voiceStillComing ? "arrow.down.circle" : "sparkles") { setup.finish() }
            .buttonStyle(KitButton(kind: .primary, wide: true))
            .keyboardShortcut(.defaultAction)
            .disabled(setup.voiceStillComing)
    }

    private var greeting: String {
        let name = setup.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "You're set." : "You're set, \(name)."
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
