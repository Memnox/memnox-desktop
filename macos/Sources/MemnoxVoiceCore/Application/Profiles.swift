import Foundation

/// How a press on Profiles ended; applying is said in a line, since every piece it raises waits on the island.
public enum ProfileOutcome: Equatable, Sendable {
    case done(String)
    case failed(String)
}

/// Profiles as the runtime keeps them: named bundles of skills, servers and a rule pack. Keeping one grants nothing;
/// applying one raises the proposals each piece raises on its own, each signed with Touch ID on the island.
public final class Profiles: @unchecked Sendable {
    private let link: DaemonLink
    private let ids: RequestIds
    private let keyTitle: String
    private let lock = NSLock()
    private var list: [ProfileView]?
    private var catalog: [ProfileTemplate]?
    private var failed = false
    private var busyWith: String?

    /// Told after anything here changed, on whatever thread that happened.
    public var changed: (@Sendable () -> Void)?

    public init(link: DaemonLink, ids: RequestIds = RequestIds(), keyTitle: String = "Touch ID") {
        self.link = link
        self.ids = ids
        self.keyTitle = keyTitle
    }

    public var profiles: [ProfileView]? { lock.withLock { list } }

    /// The job descriptions with no agent behind them, nil until read.
    public var templates: [ProfileTemplate]? { lock.withLock { catalog } }

    /// The last read failed, so the page says so rather than drawing no profiles.
    public var unreadable: Bool { lock.withLock { failed } }

    /// The profile a press is still working on, so its controls can say so.
    public var busy: String? { lock.withLock { busyWith } }

    public func refresh() async {
        let response = await ask(DaemonRequest(id: ids.next(), method: .profiles))
        lock.withLock {
            failed = response?.ok != true
            if let profiles = response?.profiles { list = profiles }
        }
        changed?()
    }

    /// Keeps a new profile, or replaces the one of the same name when `editing`; either way it grants nothing.
    public func put(_ draft: ProfileDraft, editing: Bool = false) async -> ProfileOutcome {
        var request = DaemonRequest(id: ids.next(), method: .profilePut)
        request.profileDraft = draft
        return await change(draft.name, request) { _ in ProfileLines.saved(draft.name, editing: editing) }
    }

    public func remove(_ name: String) async -> ProfileOutcome {
        var request = DaemonRequest(id: ids.next(), method: .profileRemove)
        request.profileName = name
        return await change(name, request) { _ in "\(name) is forgotten. What it already gave stays where it was given." }
    }

    /// Reads the catalog of job descriptions, which ships with the runtime and needs no account.
    public func readTemplates() async {
        let response = await ask(DaemonRequest(id: ids.next(), method: .templates))
        lock.withLock { if let templates = response?.templates { catalog = templates } }
        changed?()
    }

    /// Puts an agent found here under a kept profile; its ledger key stays its own, so nothing it did is renamed.
    public func bind(_ profile: String, agent: String) async -> ProfileOutcome {
        var request = DaemonRequest(id: ids.next(), method: .profileBind)
        request.profileName = profile
        request.agentId = agent
        return await change(profile, request) { _ in "The agent now works under \(profile)." }
    }

    /// Takes the binding off, which puts the agent back on its own default profile.
    public func unbind(agent: String, from profile: String) async -> ProfileOutcome {
        var request = DaemonRequest(id: ids.next(), method: .profileUnbind)
        request.agentId = agent
        return await change(profile, request) { _ in "The agent is back on its own default, with no job." }
    }

    /// Keeps a job and binds an agent to it in one press, as Give it a job on an agent's card does.
    public func putAndBind(_ draft: ProfileDraft, agent: String) async -> ProfileOutcome {
        let kept = await put(draft)
        guard case .done = kept else { return kept }
        return await bind(draft.name, agent: agent)
    }

    /// Copies a template's job into a new profile, with only the suggested skills the person took; no rule is applied.
    public func fromTemplate(_ template: String, named name: String, skills: [String]) async -> ProfileOutcome {
        var request = DaemonRequest(id: ids.next(), method: .profileFromTemplate)
        request.templateId = template
        request.profileName = AgentWorkLines.filled(name)
        request.templateSkills = skills
        return await change(template, request) { _ in ProfileLines.copied(name) }
    }

    /// Proposes the profile's servers, skills and rules for an agent, in a project or its home folder.
    public func apply(_ name: String, agent: String, project: String) async -> ProfileOutcome {
        var request = DaemonRequest(id: ids.next(), method: .profileApply)
        request.profileName = name
        request.profileAgent = agent
        let folder = project.trimmingCharacters(in: .whitespacesAndNewlines)
        if !folder.isEmpty { request.profileProject = folder }
        let keyTitle = keyTitle
        return await change(name, request) { response in
            response.profileApplied.map { ProfileLines.applied($0, keyTitle: keyTitle) } ?? "\(name) is applied."
        }
    }

    private func change(_ subject: String, _ request: DaemonRequest, done: (DaemonResponse) -> String) async -> ProfileOutcome {
        lock.withLock { busyWith = subject }
        changed?()
        let response = await ask(request)
        lock.withLock {
            busyWith = nil
            if let profiles = response?.profiles { list = profiles }
        }
        changed?()
        guard let response else { return .failed("The runtime is not answering.") }
        guard response.ok else { return .failed(response.error ?? "The runtime refused this.") }
        return .done(done(response))
    }

    /// A runtime that went away is said by `unreadable` and the outcome, never thrown at the page.
    private func ask(_ request: DaemonRequest) async -> DaemonResponse? {
        try? await link.request(request)
    }
}
