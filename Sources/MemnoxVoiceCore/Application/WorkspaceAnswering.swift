import Foundation

/// What a poll of the inbox changed: calls that started waiting on the person, and calls that stopped.
public struct InboxChange: Equatable, Sendable {
    public var arrived: [WorkspaceHeldCall] = []
    /// The ids of calls answered, run out or withdrawn since the last poll.
    public var gone: [String] = []
    /// The workspace refused the credential, so the person has to sign in again.
    public var signedOut = false
    /// Of the calls gone, those the workspace said were answered by somebody else, with who and where, by id.
    public var answeredElsewhere: [String: String] = [:]

    public init(arrived: [WorkspaceHeldCall] = [], gone: [String] = [], signedOut: Bool = false,
                answeredElsewhere: [String: String] = [:]) {
        self.arrived = arrived
        self.gone = gone
        self.signedOut = signedOut
        self.answeredElsewhere = answeredElsewhere
    }
}

/// The held calls teammates' agents raised that the workspace routed to this person, and the answers to them.
/// A yes goes only with Touch ID over exactly that call and that answer; a deny goes unsigned, since saying
/// no can do no harm. Every answer goes through the workspace and never through any daemon link.
public final class WorkspaceAnswering: @unchecked Sendable {
    private let inbox: WorkspaceInbox
    private let store: PersonCredentialStore
    private let key: ConfirmKey
    private let now: () -> Date
    private let lock = NSLock()
    /// Every call shown and not yet settled, with the workspace that holds it, by id.
    private var open: [String: (workspace: String, call: WorkspaceHeldCall)] = [:]
    /// Calls answered here, so one the inbox still lists for a moment is not shown again.
    private var answeredHere = Set<String>()
    /// Far more than are ever answered between two polls, and still a bound on a set nothing else empties.
    static let answeredKept = 200

    public init(inbox: WorkspaceInbox, store: PersonCredentialStore, key: ConfirmKey, now: @escaping () -> Date = Date.init) {
        self.inbox = inbox
        self.store = store
        self.key = key
        self.now = now
    }

    /// Whether a subject is one of the workspace's calls, so its answer goes here rather than to a machine.
    public func owns(_ subject: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return open[subject] != nil
    }

    /// The call shown under a subject, nil when it is not the workspace's.
    public func call(_ subject: String) -> WorkspaceHeldCall? {
        lock.lock()
        defer { lock.unlock() }
        return open[subject]?.call
    }

    /// Every call still waiting on the person, oldest first, as an ask names them to the voice; empty once signed out.
    public func briefs() -> [TeamCallBrief] {
        lock.lock()
        defer { lock.unlock() }
        return open.values.map(\.call).sorted { ($0.askedAt, $0.id) < ($1.askedAt, $1.id) }
            .map { TeamCallBrief(id: $0.id, label: $0.who, what: $0.what) }
    }

    /// Reads every workspace's inbox once. A workspace that did not answer keeps what it showed, so a dropped
    /// poll never makes a call flicker off the island and back.
    public func refresh() async -> InboxChange {
        guard let credential = store.load() else { return InboxChange(gone: forgetAll()) }
        let moment = now()
        var fresh: [String: (workspace: String, call: WorkspaceHeldCall)] = [:]
        var answered = Set<String>()
        var settled: [String: String] = [:]
        for workspace in credential.workspaces {
            do {
                let calls = try await inbox.held(in: workspace, token: credential.token)
                answered.insert(workspace)
                for call in calls where call.isSettled { settled[call.id] = call.settledLine }
                // A yes already counted toward a quorum is this person's part done, so it stops asking them.
                for call in calls where !call.isSettled && !call.approvedByYou && (call.expiry.map { $0 > moment } ?? true) {
                    fresh[call.id] = (workspace, call)
                }
            } catch WorkspaceInboxError.signedOut {
                return InboxChange(gone: forgetAll(), signedOut: true)
            } catch {
                diary.note("reading the team inbox for \(workspace) failed: \(error)")
            }
        }
        return merge(fresh, answered: answered, settled: settled)
    }

    /// Puts a poll in place of what was open, and says what came and went and who answered what went.
    private func merge(_ polled: [String: (workspace: String, call: WorkspaceHeldCall)], answered: Set<String>,
                       settled: [String: String]) -> InboxChange {
        lock.lock()
        defer { lock.unlock() }
        var fresh = polled.filter { !answeredHere.contains($0.key) }
        for (id, entry) in open where !answered.contains(entry.workspace) { fresh[id] = entry }
        var change = InboxChange()
        change.gone = open.keys.filter { fresh[$0] == nil }.sorted()
        // Only calls this Mac was showing, since one answered here is gone from the open list already.
        change.answeredElsewhere = settled.filter { change.gone.contains($0.key) }
        change.arrived = fresh.values.map(\.call).filter { open[$0.id] == nil }.sorted { ($0.askedAt, $0.id) < ($1.askedAt, $1.id) }
        open = fresh
        return change
    }

    private func entry(_ subject: String) -> (workspace: String, call: WorkspaceHeldCall)? {
        lock.lock()
        defer { lock.unlock() }
        return open[subject]
    }

    /// Every call forgotten, for a sign out; returns the ids that were showing.
    @discardableResult
    public func forgetAll() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let ids = open.keys.sorted()
        open = [:]
        return ids
    }

    /// One answer: Touch ID over exactly this call and answer for a yes, nothing for a deny. `signed` is a signature
    /// over that same message already taken, so a yes the voice heard asks for one touch rather than two.
    public func answer(_ subject: String, _ answer: HoldAnswer, reason: String, signed: String? = nil) async -> HeldOutcome {
        guard let entry = entry(subject) else { return .failed(WorkspaceLines.gone) }
        guard let credential = store.load() else { return .failed(WorkspaceLines.signedOut) }
        var signature: String?
        if answer != .deny, let signed {
            signature = signed
        } else if answer != .deny {
            guard let signed = try? await key.sign(confirmationMessage(subject: subject, answer: answer.rawValue), reason: reason) else {
                return .cancelled
            }
            signature = signed
        }
        do {
            let reply = try await inbox.answer(subject, in: entry.workspace, answer: answer, deviceId: credential.deviceId,
                                               signature: signature, token: credential.token)
            settle(subject)
            diary.note("answered the team's \(subject) \(answer.rawValue): \(reply.status)")
            return .answered
        } catch WorkspaceInboxError.settled, WorkspaceInboxError.notFound {
            // Somebody else's answer, or the machine stopped waiting; the workspace no longer says which.
            settle(subject)
            return .answeredElsewhere(EarlierAnswer(word: nil))
        } catch WorkspaceInboxError.notReached {
            return .failed(WorkspaceLines.notReached)
        } catch WorkspaceInboxError.signedOut {
            return .failed(WorkspaceLines.signedOut)
        } catch {
            diary.note("answering the team's \(subject) failed: \(error)")
            return .failed(WorkspaceLines.unreachable)
        }
    }

    private func settle(_ subject: String) {
        lock.lock()
        open[subject] = nil
        if answeredHere.count >= Self.answeredKept { answeredHere.removeAll() }
        answeredHere.insert(subject)
        lock.unlock()
    }
}
