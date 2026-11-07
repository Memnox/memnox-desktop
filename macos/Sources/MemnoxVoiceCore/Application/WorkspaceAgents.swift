import Foundation

/// The agents a workspace reaches that no daemon here does: hosted, inside an app, or built elsewhere. Read only while
/// the person is signed in; with no account this holds nothing, so the local list is all there is and nothing is missing.
public final class WorkspaceAgents: @unchecked Sendable {
    private let reader: WorkspaceAgentsReader
    private let store: PersonCredentialStore
    private let lock = NSLock()
    private var kept: [Remote] = []
    private var busyWith: String?

    /// One workspace's agents as last read.
    public struct Remote: Equatable, Sendable {
        public let workspace: String
        public let profiles: [ProfileView]
        public let work: [AgentWork]
    }

    /// Told after anything here changed, on whatever thread that happened.
    public var changed: (@Sendable () -> Void)?

    public init(reader: WorkspaceAgentsReader, store: PersonCredentialStore) {
        self.reader = reader
        self.store = store
    }

    public var signedIn: Bool { store.load() != nil }
    public var remote: [Remote] { lock.withLock { kept } }
    public var busy: String? { lock.withLock { busyWith } }

    /// Every workspace's jobs and the person's work; a workspace that did not answer keeps what it showed.
    public func refresh() async {
        guard let credential = store.load() else {
            lock.withLock { kept = [] }
            changed?()
            return
        }
        var fresh: [Remote] = []
        for workspace in credential.workspaces {
            do {
                let profiles = try await reader.agentProfiles(in: workspace, token: credential.token)
                let mine = try await reader.myAgentWork(in: workspace, token: credential.token)
                fresh.append(Remote(workspace: workspace,
                                    profiles: profiles.map { WorkspaceAgentsLines.profileView($0, you: credential.personId) },
                                    work: mine.work.map {
                                        WorkspaceAgentsLines.work($0, handoffs: mine.handoffs, you: credential.personId, profiles: profiles)
                                    }
                                        + orphans(mine, you: credential.personId)))
            } catch WorkspaceInboxError.signedOut {
                lock.withLock { kept = [] }
                changed?()
                return
            } catch {
                diary.note("reading the workspace's agents for \(workspace) failed: \(error)")
                if let before = lock.withLock({ kept.first { $0.workspace == workspace } }) { fresh.append(before) }
            }
        }
        lock.withLock { kept = fresh }
        changed?()
    }

    /// Handoffs on work the person does not answer for still wait on them, so each stands on a piece of its own.
    private func orphans(_ mine: CloudMyWork, you: String?) -> [AgentWork] {
        let known = Set(mine.work.map(\.id))
        return mine.handoffs.filter { !known.contains($0.workId) }.map { handoff in
            AgentWork(id: handoff.workId, profileId: handoff.fromProfileId, responsiblePerson: "",
                      target: ExternalTaskRef(source: "", externalId: handoff.workId), status: WorkStatus.handoffRequested.rawValue,
                      handoffs: [WorkHandoff(id: handoff.id, from: HandoffParty(profileId: handoff.fromProfileId),
                                             to: HandoffParty(profileId: handoff.toProfileId,
                                                               person: WorkspaceAgentsLines.responsibleName(id: handoff.toPersonId, name: nil, you: you)),
                                             reason: handoff.reason, state: handoff.state, requestedAt: handoff.requestedAt)],
                      createdAt: handoff.requestedAt, updatedAt: handoff.requestedAt)
        }
    }

    /// The person's answer to a handoff, unsigned since it only moves who carries the work; the workspace decides.
    public func answer(_ handoff: String, in workspace: String, _ word: HandoffAnswerWord) async -> WorkOutcome {
        guard let credential = store.load() else { return .failed("Sign in to Memnox Cloud to answer this.") }
        lock.withLock { busyWith = handoff }
        changed?()
        defer {
            lock.withLock { busyWith = nil }
            changed?()
        }
        do {
            try await reader.answerHandoff(handoff, in: workspace, accept: word == .accept, token: credential.token)
        } catch WorkspaceInboxError.settled(let why), WorkspaceInboxError.notReached(let why), WorkspaceInboxError.notFound(let why) {
            return .failed(why)
        } catch {
            return .failed("The workspace did not take the answer: \(error)")
        }
        await refresh()
        return .done(AgentWorkLines.answered(word))
    }
}
