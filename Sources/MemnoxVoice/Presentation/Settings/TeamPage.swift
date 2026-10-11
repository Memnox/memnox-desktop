import AppKit
import MemnoxVoiceCore
import SwiftUI

/// Where signing in to the team stands, from the code the person approves in the console to signed in.
enum TeamStep: Equatable {
    case signedOut
    /// Asking Memnox Cloud for a code.
    case starting
    /// The code is up and the console page open, waiting for the person to approve it there.
    case showingCode(String)
    case signedIn(name: String, workspaces: Int)
    case failed(String)
}

/// Signs this Mac in to the person's Memnox Cloud workspace and out again; the app polls the inbox while signed in.
@MainActor
final class TeamModel: ObservableObject {
    @Published var step: TeamStep
    private let signIn: WorkspaceSignIn
    private var running: Task<Void, Never>?
    /// The sign in under way, so one cancelled reports nothing when its asking finally stops.
    private var attempt = UUID()
    /// Told whenever the person signs in or out, so the app starts or stops reading the inbox.
    var changed: (() -> Void)?

    init(signIn: WorkspaceSignIn) {
        self.signIn = signIn
        step = signIn.current.map { .signedIn(name: $0.name, workspaces: $0.workspaces.count) } ?? .signedOut
    }

    var isSignedIn: Bool {
        if case .signedIn = step { return true }
        return false
    }

    /// Shows the code and opens the console on it, then waits for the person to approve this Mac there.
    func start() {
        running?.cancel()
        step = .starting
        let attempt = UUID()
        self.attempt = attempt
        let name = Host.current().localizedName ?? ServerPairingLines.thisMac
        running = Task { [weak self, signIn] in
            let outcome = await signIn.signIn(name: name) { code in
                Task { @MainActor [weak self] in
                    guard let self, self.attempt == attempt else { return }
                    self.step = .showingCode(code.userCode)
                    if let page = code.page { NSWorkspace.shared.open(page) }
                }
            }
            await MainActor.run { [weak self] in self?.finished(outcome, attempt: attempt) }
        }
    }

    func cancel() {
        running?.cancel()
        running = nil
        attempt = UUID()
        step = .signedOut
    }

    /// Removes this Mac from the workspace, which revokes its credential, and forgets it here.
    func signOut() {
        running?.cancel()
        attempt = UUID()
        Task { [weak self, signIn] in
            await signIn.signOut()
            await MainActor.run { [weak self] in
                self?.step = .signedOut
                self?.changed?()
            }
        }
    }

    /// The workspace refused the credential, so the page says so rather than claiming a sign in that no longer works.
    func signedOutByTeam() {
        step = .failed(WorkspaceLines.signedOut)
    }

    private func finished(_ outcome: SignInOutcome, attempt: UUID) {
        guard attempt == self.attempt else { return }
        running = nil
        switch outcome {
        case .signedIn(let credential):
            step = .signedIn(name: credential.name, workspaces: credential.workspaces.count)
            changed?()
        case .stopped(let why):
            step = .failed(why)
        }
    }
}

/// The Team page: sign in with a code approved in the console, and sign out.
struct TeamPage: View {
    @ObservedObject var team: TeamModel

    private enum Layout {
        static let codeSize: CGFloat = 26
        static let codeTracking: CGFloat = 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            HStack(alignment: .center, spacing: Memnox.Spacing.large) {
                StatusMark(state: state)
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                    Text(team.isSignedIn ? "Signed in to your team" : "Sign in to your team")
                        .font(Memnox.sans(Memnox.TextSize.body, .semibold))
                        .foregroundStyle(Memnox.Palette.ink)
                    Text(detail)
                        .font(Memnox.sans(Memnox.TextSize.caption))
                        .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                button
            }
            if case .showingCode(let code) = team.step {
                Text(code)
                    .font(.system(size: Layout.codeSize, weight: .semibold, design: .monospaced))
                    .tracking(Layout.codeTracking)
                    .foregroundStyle(Memnox.Palette.ink)
                    .textSelection(.enabled)
                Text(WorkspaceLines.enterCode(code))
                    .font(Memnox.sans(Memnox.TextSize.caption))
                    .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
            }
        }
        .padding(Memnox.Spacing.large)
        .surface()
    }

    private var state: StepState {
        switch team.step {
        case .signedIn: return .done
        case .failed(let why): return .needs(why)
        case .signedOut, .starting, .showingCode: return .waiting
        }
    }

    private var detail: String {
        switch team.step {
        case .signedOut, .failed:
            return "Answer the calls your teammates' agents route to you, on the island beside your own. Every allow asks for Touch ID."
        case .starting:
            return "Asking Memnox Cloud for a code."
        case .showingCode:
            return "The console is open in your browser. Approve this Mac there."
        case .signedIn(let name, let workspaces):
            return "As \(name), in \(workspaces == 1 ? "one workspace" : "\(workspaces) workspaces"). Signing out removes this Mac from your team."
        }
    }

    @ViewBuilder private var button: some View {
        switch team.step {
        case .signedOut, .failed:
            Button("Sign in") { team.start() }.buttonStyle(KitButton(kind: .primary))
        case .starting:
            ProgressView().controlSize(.small)
        case .showingCode:
            Button("Cancel") { team.cancel() }.buttonStyle(KitButton(kind: .secondary))
        case .signedIn:
            Button("Sign out") { team.signOut() }.buttonStyle(KitButton(kind: .secondary))
        }
    }
}
