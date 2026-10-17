import MemnoxVoiceCore

/// Where the one sign in stands, read from the three credentials it gives this Mac: the app's own, the daemon acting
/// as the person, and this Mac's place in the workspace. Signed in only when all three are, so the page never says
/// signed in while the voice still cannot reach the person's tools.
enum AccountWhole {
    case signedOut
    case working(String)
    case showingCode(String)
    /// The app is signed in and the rest is not yet, which one button completes.
    case incomplete(name: String, why: String)
    /// The Memnox running here is older than the app, so the button updates it.
    case tooOld(DaemonAccountModel)
    case signedIn(name: String, workspace: String?)
    case failed(String)

    @MainActor
    static func of(_ app: AccountStep, daemon: DaemonAccountModel?, machine: DaemonAccountModel?) -> AccountWhole {
        switch app {
        case .signedOut: return .signedOut
        case .starting: return .working(AccountWholeLines.asking)
        case .showingCode(let code): return .showingCode(code)
        case .failed(let why): return .failed(why)
        case .signedIn(let name, _):
            return rest(name: name, daemon: daemon?.step, machine: machine?.step, models: [daemon, machine])
        }
    }

    /// The app is in, so the daemon and then this Mac's connection decide what is left.
    @MainActor
    private static func rest(name: String, daemon: DaemonAccountStep?, machine: DaemonAccountStep?,
                             models: [DaemonAccountModel?]) -> AccountWhole {
        // A Mac built without the daemon's models is signed in as far as this app can tell.
        guard let daemon, let machine else { return .signedIn(name: name, workspace: nil) }
        if let old = models.compactMap({ $0 }).first(where: { $0.step == .tooOld }) { return .tooOld(old) }
        for step in [daemon, machine] {
            if case .showingCode(let code) = step { return .showingCode(code) }
        }
        for step in [daemon, machine] {
            switch step {
            case .unknown, .starting: return .working(AccountWholeLines.settingUp)
            case .failed(let why): return .incomplete(name: name, why: why)
            case .signedOut: return .incomplete(name: name, why: AccountWholeLines.notYet)
            case .signedIn, .showingCode, .tooOld: continue
            }
        }
        if case .signedIn(let workspace) = machine, !workspace.isEmpty { return .signedIn(name: name, workspace: workspace) }
        return .signedIn(name: name, workspace: nil)
    }

    var state: StepState {
        switch self {
        case .signedIn: return .done
        case .failed(let why): return .needs(why)
        case .incomplete(_, let why): return .needs(why)
        case .tooOld: return .needs(DaemonSignInLines.tooOld)
        case .signedOut, .working, .showingCode: return .waiting
        }
    }

    var title: String {
        switch self {
        case .signedOut, .failed: return "Not signed in"
        case .working: return "Signing in"
        case .showingCode: return "Approve this Mac"
        case .incomplete(let name, _): return "Signed in as \(name)"
        case .tooOld: return "Memnox needs an update"
        case .signedIn(let name, let workspace):
            return workspace.map { "Signed in as \(name), \($0)" } ?? "Signed in as \(name)"
        }
    }

    var detail: String {
        switch self {
        case .signedOut, .failed:
            return "One approval in your browser signs in this app and Memnox on this Mac, and connects this Mac to your workspace."
        case .working(let doing): return doing
        case .showingCode: return "The console is open in your browser. Approve this Mac there, once."
        case .incomplete: return "Memnox on this Mac is not fully signed in yet. Finish completes it."
        case .tooOld: return "Update brings it up to date, with no terminal, and then signing in completes."
        case .signedIn: return "Signing out signs out this app and Memnox on this Mac, and keeps the rules already here."
        }
    }

    var code: String? {
        if case .showingCode(let code) = self { return code }
        return nil
    }
}

/// What the person reads while the sign in is under way.
enum AccountWholeLines {
    static let asking = "Asking Memnox Cloud for a code."
    static let settingUp = "Signing in Memnox on this Mac and connecting it to your workspace."
    static let notYet = "Memnox on this Mac is not signed in yet."
}
