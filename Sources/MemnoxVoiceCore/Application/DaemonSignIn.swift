import Foundation

/// How the daemon answered about the person signed in on its side.
public enum DaemonSignInStart: Equatable, Sendable {
    /// The daemon opened a sign in and this is the code to approve.
    case started(PersonSignInCode)
    /// Somebody was already signed in there.
    case signedIn(name: String)
    /// The daemon said no, and why.
    case refused(String)
    /// This Memnox is from before the daemon could sign a person in.
    case tooOld
    case unreachable
}

/// Where the daemon's sign in stands while its code is being approved.
public enum DaemonSignInWatch: Equatable, Sendable {
    case signedIn(name: String)
    case failed(String)
    case expired
}

/// Signs the daemon in as the person and out again. The daemon runs the code flow and keeps the credential,
/// since that is what the voice acts through and what `memnox inbox` answers with; this only carries the
/// person's wish and shows them the code. It is a credential apart from this app's own, because the
/// workspace binds one sign in to one device, but it rides on this app's approval so the person approves once.
public final class DaemonSignIn {
    private let link: DaemonLink
    private let side: DaemonSignInSide
    private let ids: RequestIds
    private let now: () -> Date
    private let sleep: (TimeInterval) async throws -> Void

    /// How often the daemon is asked whether the code was approved, close to the cloud's own five seconds.
    static let pollInterval: TimeInterval = 3

    public init(link: DaemonLink, side: DaemonSignInSide = .person, ids: RequestIds = RequestIds(),
                now: @escaping () -> Date = Date.init,
                sleep: @escaping (TimeInterval) async throws -> Void = DaemonSignIn.taskSleep) {
        self.link = link
        self.side = side
        self.ids = ids
        self.now = now
        self.sleep = sleep
    }

    public static func taskSleep(_ seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Where the sign in stands on the daemon's side, nil when the daemon cannot say or does not know the question.
    public func standing() async -> (any SignInStanding)? {
        (try? await link.request(newRequest(side.ask))).flatMap(side.standing)
    }

    /// Whether this daemon knows this sign in at all, false for one from before it could, nil when nothing answered,
    /// since a daemon that is down is not one that is too old and calling it so sent people to update for nothing.
    public func isKnown() async -> Bool? {
        guard let response = try? await link.request(newRequest(side.ask)) else { return nil }
        return !Self.unknownMethod(response)
    }

    /// Asks the daemon to open the sign in, named as the console will list it. `companionOf` is this app's own waiting
    /// device code, which the daemon's code then rides on, so the person approves once for both.
    public func begin(name: String? = nil, companionOf: String? = nil) async -> DaemonSignInStart {
        var request = newRequest(side.begin)
        request.name = name.flatMap { $0.isEmpty ? nil : $0 }
        request.companionOf = companionOf.flatMap { $0.isEmpty ? nil : $0 }
        diary.note("asking the daemon to sign in \(side.noun)")
        guard let response = try? await link.request(request) else {
            diary.note("the daemon did not answer \(side.begin.rawValue)")
            return .unreachable
        }
        if Self.unknownMethod(response) { return .tooOld }
        if response.ok, let standing = side.standing(response) {
            if let code = standing.code { return .started(code) }
            if standing.signedIn { return .signedIn(name: standing.name ?? side.fallbackName) }
        }
        let why = refusal(response)
        diary.note("the daemon's sign in was refused: \(why)")
        return .refused(why)
    }

    /// Asks every few seconds until the person approved the code, the daemon gave up, or the code ran out.
    public func watch(_ code: PersonSignInCode) async -> DaemonSignInWatch {
        let expiry = Date(timeIntervalSince1970: code.expiresAt / Self.millisecondsPerSecond)
        while now() < expiry {
            do {
                try await sleep(Self.pollInterval)
            } catch {
                return .failed(DaemonSignInLines.cancelled)
            }
            // A dropped request is asked again on the next interval, since the daemon is still polling.
            guard let standing = await standing() else { continue }
            if standing.signedIn { return .signedIn(name: standing.name ?? side.fallbackName) }
            if let failed = standing.failed, !failed.isEmpty { return .failed(failed) }
            // The daemon started another code or forgot this one, so this watch is over.
            if standing.code == nil { return .failed(DaemonSignInLines.stopped) }
        }
        return .expired
    }

    /// Signs out, or disconnects this machine; true when the daemon did.
    public func signOut() async -> Bool {
        guard let response = try? await link.request(newRequest(side.end)) else { return false }
        diary.note(response.ok ? "signed out \(side.noun) on the daemon" : "the daemon kept \(side.noun): \(refusal(response))")
        return response.ok
    }

    private static func unknownMethod(_ response: DaemonResponse) -> Bool {
        !response.ok && (response.error ?? "").hasPrefix(unknownMethodError)
    }

    /// What the daemon says about a method it does not have, the same prefix Conversation reads.
    private static let unknownMethodError = "no method"
    private static let millisecondsPerSecond: Double = 1_000

    private func refusal(_ response: DaemonResponse) -> String {
        for words in [response.reason, response.error] {
            if let words, !words.isEmpty { return words }
        }
        return DaemonSignInLines.refused
    }

    private func newRequest(_ method: DaemonMethod) -> DaemonRequest {
        DaemonRequest(id: ids.next(), method: method)
    }
}

/// Which of the daemon's two sign ins is driven: the person, or this machine's connection to its workspace. The two
/// answer in the same shape, so the one class carries both and only the methods and the words differ.
public enum DaemonSignInSide: Sendable {
    case person
    case machine

    /// The method that says where it stands.
    var ask: DaemonMethod {
        switch self {
        case .person: return .person
        case .machine: return .machine
        }
    }

    var begin: DaemonMethod {
        switch self {
        case .person: return .personSignIn
        case .machine: return .machineSignIn
        }
    }

    var end: DaemonMethod {
        switch self {
        case .person: return .personSignOut
        case .machine: return .machineSignOut
        }
    }

    /// The standing out of an answer, from the field this side answers in.
    func standing(_ response: DaemonResponse) -> (any SignInStanding)? {
        switch self {
        case .person: return response.person
        case .machine: return response.machine
        }
    }

    /// Who the sign in is for, in the diary.
    var noun: String {
        switch self {
        case .person: return "as the person"
        case .machine: return "this machine"
        }
    }

    /// Said when the daemon is in but has no name yet: the person, or a workspace not yet named.
    var fallbackName: String {
        switch self {
        case .person: return "you"
        case .machine: return "your workspace"
        }
    }
}

/// What the person reads about the daemon's sign in, in words they can act on.
public enum DaemonSignInLines {
    public static let refused = "Memnox would not start the sign in."
    public static let cancelled = "Signing in was stopped."
    public static let stopped = "Memnox stopped waiting on that code. Start again for a new one."
    public static let tooOld = "The Memnox running on this Mac is older than the app. Update brings it up to date, with no terminal."
    public static let machineTooOld = "The Memnox running on this Mac is older than the app. Update brings it up to date, with no terminal."
    public static let unreachable = "The Memnox daemon did not answer. Check Connection and try again."
}
