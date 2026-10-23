import AppKit
import MemnoxVoiceCore
import SwiftUI

/// Where signing this app in as the person stands, from the code they approve in the console to signed in.
enum AccountStep: Equatable {
    case signedOut
    /// Asking Memnox Cloud for a code.
    case starting
    /// The code is up and the console page open, waiting for the person to approve it there.
    case showingCode(String)
    case signedIn(name: String, workspaces: Int)
    case failed(String)
}

/// Signs this app in to the person's Memnox Cloud workspace and out again; the app polls the inbox while signed in.
@MainActor
final class AccountModel: ObservableObject {
    @Published var step: AccountStep
    private let signIn: WorkspaceSignIn
    private var running: Task<Void, Never>?
    /// The sign in under way, so one cancelled reports nothing when its asking finally stops.
    private var attempt = UUID()
    /// Told whenever the person signs in or out, so the app starts or stops reading the inbox.
    var changed: (() -> Void)?
    /// The daemon's own sign in, nil before the app has built it.
    var daemon: DaemonAccountModel?
    /// This Mac's connection to its workspace, the credential the daemon's rules, memory and phone pairing read.
    var machine: DaemonAccountModel?

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
                    // The daemon's code rides on this one before the page opens, so one approval covers both.
                    await self.daemon?.ride(on: code.deviceCode, name: name)
                    guard self.attempt == attempt else { return }
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
        if daemon?.riding == true { daemon?.cancel() }
        step = .signedOut
    }

    /// Signs out everywhere it signed in: this app, the daemon acting as the person, and this Mac's connection.
    /// The rules already on this Mac stay, as each of the three already keeps them.
    func signOut() {
        running?.cancel()
        attempt = UUID()
        daemon?.signOut()
        machine?.signOut()
        Task { [weak self, signIn] in
            await signIn.signOut()
            await MainActor.run { [weak self] in
                self?.step = .signedOut
                self?.changed?()
            }
        }
    }

    /// Completes what the one sign in carries and is still missing, asking only for what is not held: the daemon's
    /// own approval when it never rode along, else only this Mac's connection, which needs no browser at all.
    func finish() {
        guard let daemon else { return }
        let name = Host.current().localizedName ?? ServerPairingLines.thisMac
        if daemon.isSignedIn {
            Task { [weak self] in
                await daemon.complete(name: name)
                await self?.machine?.follow()
            }
        } else {
            daemon.start { [weak self] in await self?.machine?.follow() }
        }
    }

    /// After the person approved: the daemon's code was approved in the same act on a cloud that knows how, and
    /// otherwise it is shown to approve on its own; once the daemon is in, it connects this Mac by itself.
    private func settleRest() {
        guard let daemon else { return }
        Task { [weak self] in
            for _ in 0..<Self.rideWaits where daemon.riding {
                try? await Task.sleep(nanoseconds: Self.rideStep)
            }
            if daemon.riding { daemon.showHeldCode() }
            await daemon.settled()
            await self?.machine?.follow()
        }
    }

    /// Seconds the daemon is given to follow the app's approval before its own code is shown, one a second.
    private static let rideWaits = 12
    private static let rideStep: UInt64 = 1_000_000_000

    /// Signs in and waits for it to end, so connecting a tool before anybody signed in carries straight on once they
    /// approve. True once the daemon holds the person as well, since it is the daemon that connects the tool.
    func signInAndWait() async -> Bool {
        if !isSignedIn {
            start()
            // An approval left unfinished in the browser is given up on, rather than holding the tool for as long as the code lives.
            let deadline = Task { [weak self] in
                try? await Task.sleep(nanoseconds: Self.approvalWait)
                guard !Task.isCancelled, let self, !self.isSignedIn else { return }
                self.cancel()
            }
            defer { deadline.cancel() }
            waiting: for await now in $step.values {
                switch now {
                case .starting, .showingCode: continue
                case .signedIn: break waiting
                case .signedOut, .failed: return false
                }
            }
            // A Connect pressed again stopped this wait, so the code it showed is dropped with it.
            if Task.isCancelled {
                cancel()
                return false
            }
        }
        guard let daemon else { return true }
        for _ in 0..<Self.daemonWaits {
            if await daemon.connected() != false { return true }
            try? await Task.sleep(nanoseconds: Self.rideStep)
        }
        return false
    }

    /// Three minutes, long enough to sign in to the console and approve, short enough that a tab closed halfway is let go.
    private static let approvalWait: UInt64 = 180_000_000_000

    /// Seconds the daemon is given after the approval to hold the person too, longer than the ride itself waits.
    private static let daemonWaits = 20

    /// The workspace refused the credential, so the page says so rather than claiming a sign in that no longer works.
    func signedOutByWorkspace() {
        step = .failed(WorkspaceLines.signedOut)
    }

    private func finished(_ outcome: SignInOutcome, attempt: UUID) {
        guard attempt == self.attempt else { return }
        running = nil
        switch outcome {
        case .signedIn(let credential):
            step = .signedIn(name: credential.name, workspaces: credential.workspaces.count)
            changed?()
            settleRest()
        case .stopped(let why):
            step = .failed(why)
        }
    }
}

/// Where the daemon's own sign in stands: the credential the voice acts through and the terminal answers with.
enum DaemonAccountStep: Equatable {
    /// Not asked yet.
    case unknown
    case signedOut
    case starting
    case showingCode(String)
    case signedIn(name: String)
    case failed(String)
    /// This Memnox is from before the daemon could sign a person in, so there is no button.
    case tooOld
}

/// Signs the daemon in as the person and out again, through the daemon, which runs the code flow itself.
@MainActor
final class DaemonAccountModel: ObservableObject {
    @Published var step: DaemonAccountStep = .unknown
    private let signIn: DaemonSignIn
    private var running: Task<Void, Never>?
    private var attempt = UUID()

    /// Brings the Memnox under the app up to date and restarts it, set by the app; nil leaves the row without the button.
    var update: (() async -> Void)?
    @Published private(set) var updating = false

    /// The daemon brought up to date, then asked again, so a row that said too old turns into one that works.
    func bringUpToDate() {
        guard let update, !updating else { return }
        updating = true
        Task { [weak self] in
            await update()
            self?.updating = false
            await self?.refresh()
        }
    }

    /// What a standing with no name is called: the person, or a workspace that has not been named.
    private let unnamed: String
    /// The daemon's own code while it rides on the app's approval, kept to show if that approval does not carry it.
    private var held: PersonSignInCode?
    /// Whether the daemon is waiting on the app's approval to carry it in, with nothing shown to the person yet.
    @Published private(set) var riding = false
    private var watching: Task<Void, Never>?

    init(signIn: DaemonSignIn, unnamed: String = "you") {
        self.signIn = signIn
        self.unnamed = unnamed
    }

    /// Opens the daemon's sign in on the back of the app's waiting code and watches it quietly, so the one
    /// approval the person gives in the browser signs the daemon in too.
    func ride(on deviceCode: String, name: String) async {
        running?.cancel()
        let attempt = UUID()
        self.attempt = attempt
        switch await signIn.begin(name: name, companionOf: deviceCode) {
        case .started(let code):
            guard self.attempt == attempt else { return }
            held = code
            riding = true
            step = .starting
            watching = Task { [weak self, signIn] in
                let watched = await signIn.watch(code)
                guard let self, self.attempt == attempt else { return }
                self.riding = false
                self.held = nil
                self.settle(watched)
            }
        case .signedIn(let who): step = .signedIn(name: who)
        case .refused(let why): step = .failed(why)
        case .tooOld: step = .tooOld
        case .unreachable: step = .failed(DaemonSignInLines.unreachable)
        }
    }

    /// The approval did not carry the daemon, which a cloud from before riding along does, so its code is shown.
    func showHeldCode() {
        guard riding, let held else { return }
        riding = false
        step = .showingCode(held.userCode)
        if let page = held.page.flatMap(URL.init(string:)) { NSWorkspace.shared.open(page) }
    }

    /// Waits for the watch under way, if any, to end.
    func settled() async {
        await watching?.value
    }

    /// Asks a daemon already signed in to complete what it carries, which connects this Mac with no browser.
    func complete(name: String) async {
        _ = await signIn.begin(name: name)
        await refresh()
    }

    /// Reads again every few seconds until this Mac is connected, since the daemon connects it on its own.
    func follow() async {
        for _ in 0..<Self.followTries {
            await refresh()
            if isSignedIn { return }
            try? await Task.sleep(nanoseconds: Self.followStep)
        }
    }

    /// About half a minute, which a machine's own approval and its first poll take well within.
    private static let followTries = 10
    private static let followStep: UInt64 = 3_000_000_000

    private func settle(_ watched: DaemonSignInWatch) {
        switch watched {
        case .signedIn(let who): step = .signedIn(name: who)
        case .failed(let why): step = .failed(why)
        case .expired: step = .failed(WorkspaceLines.expired)
        }
    }

    var isSignedIn: Bool {
        if case .signedIn = step { return true }
        return false
    }

    /// Whether the daemon has it, asked fresh; nil when the daemon cannot say or does not know the question.
    func connected() async -> Bool? {
        await refresh()
        switch step {
        case .signedIn: return true
        case .unknown, .tooOld: return nil
        case .signedOut, .starting, .showingCode, .failed: return false
        }
    }

    /// Reads where the daemon stands, which is cheap, so the page is right whenever it opens.
    func refresh() async {
        if case .showingCode = step { return }
        if riding { return }
        guard let standing = await signIn.standing() else {
            // Nothing answered, or a daemon from before the question: the button is kept only where it can work.
            switch await signIn.isKnown() {
            case .some(true): step = .signedOut
            case .some(false): step = .tooOld
            case .none: step = .failed(DaemonSignInLines.unreachable)
            }
            return
        }
        if standing.signedIn {
            step = .signedIn(name: standing.name ?? unnamed)
        } else if let failed = standing.failed, !failed.isEmpty {
            step = .failed(failed)
        } else {
            step = .signedOut
        }
    }

    /// Asks the daemon for a code, opens the console on it, and waits for the person to approve it there; `then` runs
    /// once it ends, so this Mac's connection is followed once the daemon is in.
    func start(then: (@MainActor () async -> Void)? = nil) {
        running?.cancel()
        step = .starting
        let attempt = UUID()
        self.attempt = attempt
        let name = Host.current().localizedName ?? ServerPairingLines.thisMac
        running = Task { [weak self, signIn] in
            let start = await signIn.begin(name: name)
            guard let self, self.attempt == attempt else { return }
            switch start {
            case .started(let code):
                self.step = .showingCode(code.userCode)
                if let page = code.page.flatMap(URL.init(string:)) { NSWorkspace.shared.open(page) }
                let watched = await signIn.watch(code)
                guard self.attempt == attempt else { return }
                self.settle(watched)
            case .signedIn(let who): self.step = .signedIn(name: who)
            case .refused(let why): self.step = .failed(why)
            case .tooOld: self.step = .tooOld
            case .unreachable: self.step = .failed(DaemonSignInLines.unreachable)
            }
            self.running = nil
            await then?()
        }
    }

    func cancel() {
        running?.cancel()
        running = nil
        watching?.cancel()
        riding = false
        attempt = UUID()
        step = .signedOut
    }

    func signOut() {
        watching?.cancel()
        riding = false
        running?.cancel()
        attempt = UUID()
        Task { [weak self, signIn] in
            let out = await signIn.signOut()
            await MainActor.run { [weak self] in
                if out { self?.step = .signedOut } else { self?.step = .failed(DaemonSignInLines.unreachable) }
            }
        }
    }
}

/// The Account page: the person's name, the one sign in that gives this Mac everything, and what it turns on, said
/// as plain words since none of it is a choice of its own.
struct AccountPage: View {
    @ObservedObject var account: AccountModel
    /// The name lives here too, since the person's name and their sign in are the same person.
    @ObservedObject var setup: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xxLarge) {
            AccountGroup(title: "You") {
                SetupNameRow(model: setup)
            }
            AccountGroup(title: "Memnox Cloud") {
                if let daemon = account.daemon, let machine = account.machine {
                    SignInRow(account: account, daemon: daemon, machine: machine)
                } else {
                    SignInRow(account: account, daemon: nil, machine: nil)
                }
            }
            AccountGroup(title: "What signing in turns on") {
                IncludedList()
            }
        }
        .task(id: account.daemon.map(ObjectIdentifier.init)) {
            await account.daemon?.refresh()
            await account.machine?.refresh()
        }
    }
}

/// The page's measurements, outside the generic views since a generic type cannot hold a static.
private enum AccountLayout {
    static let codeSize: CGFloat = 26
    static let codeTracking: CGFloat = 2
}

/// A group's title over its card of rows, as Vorssaint heads its groups.
private struct AccountGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        SettingsSection(title: title) {
            VStack(spacing: 0) { content() }
                .surface()
        }
    }
}

/// One row of the page: where it stands, what it is and what it means, one control, and under them a code to approve
/// or a line saying what went wrong.
private struct AccountRow<Control: View>: View {
    let state: StepState
    let title: String
    let detail: String
    var code: String?
    @ViewBuilder let control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            HStack(alignment: .center, spacing: Memnox.Spacing.large) {
                StatusMark(state: state)
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                    // Wraps rather than cuts off, since a full name and a workspace together can be long.
                    Text(title)
                        .font(.system(size: SettingsMetrics.rowTextSize))
                        .foregroundStyle(Memnox.Palette.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.system(size: SettingsMetrics.captionSize))
                        .foregroundStyle(Memnox.Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Memnox.Spacing.medium)
                control().fixedSize(horizontal: true, vertical: false)
            }
            if let code {
                Text(code)
                    .font(.system(size: AccountLayout.codeSize, weight: .semibold, design: .monospaced))
                    .tracking(AccountLayout.codeTracking)
                    .foregroundStyle(Memnox.Palette.ink)
                    .textSelection(.enabled)
                Text(WorkspaceLines.enterCode(code))
                    .font(Memnox.sans(Memnox.TextSize.caption))
                    .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
            }
            if case .needs(let hint) = state {
                Label(hint, systemImage: "exclamationmark.circle")
                    .font(Memnox.sans(Memnox.TextSize.caption, .medium))
                    .foregroundStyle(Memnox.ink(Memnox.Ink.primary))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, Memnox.Spacing.xLarge)
        .padding(.vertical, Memnox.Spacing.large)
    }
}

/// The one sign in, standing for all three things it gives this Mac: the app's own, the daemon acting as the
/// person, and this Mac's place in the workspace. Signed in means all three, and anything missing is one button.
private struct SignInRow: View {
    @ObservedObject var account: AccountModel
    /// Optional, since a SwiftUI property cannot observe an optional; the app always builds both.
    private let daemon: DaemonAccountModel?
    private let machine: DaemonAccountModel?

    init(account: AccountModel, daemon: DaemonAccountModel?, machine: DaemonAccountModel?) {
        self.account = account
        self.daemon = daemon
        self.machine = machine
    }

    var body: some View {
        if let daemon, let machine {
            Observed(account: account, daemon: daemon, machine: machine)
        } else {
            AccountWholeRow(whole: AccountWhole.of(account.step, daemon: nil, machine: nil), account: account)
        }
    }

    /// The row redrawn whenever any of the three changes.
    private struct Observed: View {
        @ObservedObject var account: AccountModel
        @ObservedObject var daemon: DaemonAccountModel
        @ObservedObject var machine: DaemonAccountModel

        var body: some View {
            AccountWholeRow(whole: AccountWhole.of(account.step, daemon: daemon, machine: machine), account: account)
        }
    }
}

/// One row drawn from where the whole sign in stands.
private struct AccountWholeRow: View {
    let whole: AccountWhole
    @ObservedObject var account: AccountModel

    var body: some View {
        AccountRow(state: whole.state, title: whole.title, detail: whole.detail, code: whole.code) {
            switch whole {
            case .signedOut, .failed:
                Button("Sign in") { account.start() }.buttonStyle(KitButton(kind: .primary))
            case .working:
                ProgressView().controlSize(.small)
            case .showingCode:
                Button("Cancel") { account.cancel() }.buttonStyle(KitButton(kind: .secondary))
            case .incomplete:
                HStack(spacing: Memnox.Spacing.small) {
                    Button("Sign out") { account.signOut() }.buttonStyle(KitButton(kind: .secondary))
                    Button("Finish") { account.finish() }.buttonStyle(KitButton(kind: .primary))
                }
            case .tooOld(let model):
                UpdateButton(model: model)
            case .signedIn:
                Button("Sign out") { account.signOut() }.buttonStyle(KitButton(kind: .secondary))
            }
        }
    }
}

/// What signing in gives, as plain lines with no box to tick, since none of it is switched on apart.
private struct IncludedList: View {
    private static let lines: [(symbol: String, words: String)] = [
        ("bell.badge", "Calls your workspace routes to you show in the notch, and every yes asks for Touch ID."),
        ("person.wave.2", "Apps you already connected on this Mac move into your account with you."),
        ("desktopcomputer", "Your rules, workspace memory and phone pairing reach this Mac."),
    ]

    var body: some View {
        // One row each with its own tile and a rule between, so the three read as three things rather than a paragraph.
        VStack(alignment: .leading, spacing: SettingsMetrics.cardSpacing) {
            ForEach(Self.lines, id: \.symbol) { line in
                if line.symbol != Self.lines.first?.symbol { SettingsDivider() }
                SettingsRow(symbol: line.symbol, title: line.words)
            }
        }
        .padding(SettingsMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Update, for a row whose daemon is older than the app: the app updates and restarts it, so nobody is sent to a terminal.
struct UpdateButton: View {
    @ObservedObject var model: DaemonAccountModel

    var body: some View {
        if model.updating {
            ProgressView().controlSize(.small)
        } else if model.update != nil {
            Button("Update") { model.bringUpToDate() }.buttonStyle(KitButton(kind: .primary))
        }
    }
}
