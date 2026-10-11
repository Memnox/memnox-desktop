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
                  detail: "Your agents can already do the work. Memnox makes it safe to let them do it without you.")
        KitCard {
            ForEach(Highlight.allCases) { part in
                if part != Highlight.allCases.first { KitDivider() }
                KitRow(symbol: part.symbol, title: part.title, detail: part.detail) {
                    if part == flow.highlight {
                        Image(systemName: "play.fill")
                            .font(.system(size: Memnox.TextSize.footnote))
                            .foregroundStyle(Memnox.Palette.primary)
                            .accessibilityLabel("playing now")
                    }
                }
                .opacity(flow.highlight == nil || part == flow.highlight ? 1 : Shade.resting)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: Memnox.Motion.standard), value: flow.highlight)
        Next(title: "Set up this Mac", flow: flow)
    }
}

/// Everything this Mac needs on one page: the three grants, and Memnox installed under the agents it found.
struct ThisMacStep: View {
    @ObservedObject var flow: OnboardingFlow
    @ObservedObject var setup: SetupModel

    var body: some View {
        StepTitle(title: "Set up this Mac",
                  detail: "Three permissions, asked once, and Memnox installs itself under your agents.")
        KitCard(symbol: "lock.shield", title: "Permissions", detail: "Used only when you talk or approve.") {
            KitRow(symbol: "mic", title: "Hear you", detail: "Microphone and speech recognition.", hint: hint(setup.listening)) {
                grant(setup.listening) { Task { await setup.allowListening() } }
            }
            KitDivider()
            KitRow(symbol: "cursorarrow.click.2", title: "Type and see for you",
                   detail: "Accessibility and Screen Recording, so a follow up lands in the agent's own app.",
                   hint: hint(setup.seeing)) {
                grant(setup.seeing) { setup.allowSeeing() }
            }
            KitDivider()
            KitRow(symbol: "touchid", title: "Approve with Touch ID", detail: "The key stays in this Mac's Secure Enclave.",
                   hint: hint(setup.key)) {
                if setup.key == .done { CheckBox(state: .done) } else { checkAgain }
            }
        }
        KitCard(symbol: "desktopcomputer", title: "Memnox on this Mac", detail: setup.agentsDetail) {
            KitRow(title: "Memnox daemon", detail: setup.runtime.doing.map { "\($0)…" } ?? "Installed, started and updated for you.",
                   hint: hint(setup.daemon), leading: { MemnoxTile() }) {
                if setup.daemon == .done { CheckBox(state: .done) } else { checkAgain }
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
                       detail: hint(setup.agentsState) ?? "Asking the daemon which agents are on this Mac.") {
                    Button("Check again", systemImage: "arrow.clockwise") { Task { await setup.loadAgents(recheck: true) } }
                        .buttonStyle(KitButton(kind: .secondary))
                        .disabled(setup.checkingAgents)
                }
            }
        }
        Next(title: "Continue", flow: flow)
    }

    private var checkAgain: some View {
        Button("Check again", systemImage: "arrow.clockwise") { Task { await setup.check() } }.buttonStyle(KitButton(kind: .secondary))
    }

    /// Allow until it is granted, then the checkbox.
    @ViewBuilder private func grant(_ state: StepState, _ action: @escaping () -> Void) -> some View {
        if state == .done {
            CheckBox(state: .done)
        } else {
            Button("Allow", systemImage: "checkmark.shield", action: action).buttonStyle(KitButton(kind: .secondary))
        }
    }

    private func status(_ agent: VoiceAgentStatus) -> String {
        guard let works = agent.works else { return setup.checkingAgents ? "Asking" : "Not asked yet" }
        if !works { return agent.because ?? "Did not answer" }
        return agent.chosen ? "Answers when you talk, kept to reading" : "Can answer when you talk"
    }
}

/// The two keys to try, the iPhone and the team for whoever wants them now, and the button that starts Memnox.
/// The voice, waking by name and speaking up keep their defaults and live in Settings, so nobody decides them here.
struct ReadyStep: View {
    @ObservedObject var flow: OnboardingFlow
    @ObservedObject var setup: SetupModel

    var body: some View {
        StepTitle(title: greeting, detail: "Give an agent a task and walk away. Memnox asks only when you need to decide.")
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
        KitCard(symbol: "iphone", title: "Optional", detail: "Answer from your iPhone, or for your team. Both wait in Settings.") {
            PhonePairing(setup: setup)
            if let team = flow.team {
                KitDivider()
                TeamSignIn(team: team)
            }
        }
        Button("Start using Memnox", systemImage: "sparkles") { setup.finish() }
            .buttonStyle(KitButton(kind: .primary, wide: true))
            .keyboardShortcut(.defaultAction)
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

/// Signing in to the team with a code approved in the console, and signed in once it is.
private struct TeamSignIn: View {
    @ObservedObject var team: TeamModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            KitRow(symbol: "building.2", title: title, detail: detail, hint: failure) {
                switch team.step {
                case .signedOut, .failed:
                    Button("Sign in", systemImage: "person.crop.circle") { team.start() }.buttonStyle(KitButton(kind: .secondary))
                case .starting:
                    ProgressView().controlSize(.small)
                case .showingCode:
                    Button("Cancel", systemImage: "xmark") { team.cancel() }.buttonStyle(KitButton(kind: .secondary))
                case .signedIn:
                    CheckBox(state: .done)
                }
            }
            if case .showingCode(let code) = team.step {
                Text(code)
                    .font(Memnox.mono(24, .semibold))
                    .foregroundStyle(Memnox.Palette.ink)
                    .textSelection(.enabled)
                    .padding(.leading, Kit.tileSide + Memnox.Spacing.large)
            }
        }
    }

    private var title: String { team.isSignedIn ? "Signed in to your team" : "Sign in to your team" }

    private var detail: String {
        switch team.step {
        case .signedOut, .failed: return "Memnox Cloud opens in your browser to approve this Mac."
        case .starting: return "Asking Memnox Cloud for a code."
        case .showingCode(let code): return WorkspaceLines.enterCode(code)
        case .signedIn(let name, _): return "As \(name)."
        }
    }

    private var failure: String? {
        if case .failed(let why) = team.step { return why }
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
    }
}

/// What a step needs from the person, in words, or nothing once it is done.
private func hint(_ state: StepState) -> String? {
    if case .needs(let why) = state { return why }
    return nil
}
