import Foundation

/// The projects as the runtime keeps them: one repository, the agents seen in it, and what each agent opened there is
/// given. It holds no rule: instructions go at once, and what widens an agent waits on a signature on the island.
public final class Projects: @unchecked Sendable {
    private let link: DaemonLink
    private let ids: RequestIds
    private let lock = NSLock()
    private var view: [ProjectView]?
    private var failed = false
    private var busyWith: String?

    /// Told after anything here changed, on whatever thread that happened.
    public var changed: (@Sendable () -> Void)?

    public init(link: DaemonLink, ids: RequestIds = RequestIds()) {
        self.link = link
        self.ids = ids
    }

    public var projects: [ProjectView]? { lock.withLock { view } }

    /// The last read failed, so the page says so rather than drawing no projects.
    public var unreadable: Bool { lock.withLock { failed } }

    /// The project or folder a press is still working on, so its controls can say so.
    public var busy: String? { lock.withLock { busyWith } }

    public func refresh() async {
        let response = await ask(DaemonRequest(id: ids.next(), method: .projects))
        lock.withLock {
            failed = response?.ok != true
            if let projects = response?.projects { view = projects.projects }
        }
        changed?()
    }

    /// Takes a folder in as a project and applies it at once.
    public func open(_ path: String) async -> ProjectOutcome {
        var request = DaemonRequest(id: ids.next(), method: .projectOpen)
        request.projectPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return await change(path, request, done: "Opened. Its agents have its instructions.")
    }

    /// Writes the manifest a found project shows now, applying nothing until asked.
    public func put(_ path: String, draft: ProjectDraft) async -> ProjectOutcome {
        var request = DaemonRequest(id: ids.next(), method: .projectPut)
        request.projectPath = path
        request.projectDraft = draft
        return await change(path, request, done: "Saved \(draft.name) as a project in .memnox/project.toml. Commit it so every clone has it.")
    }

    public func apply(_ id: String) async -> ProjectOutcome {
        var request = DaemonRequest(id: ids.next(), method: .projectApply)
        request.projectId = id
        return await change(id, request, done: "Applied.")
    }

    private func change(_ subject: String, _ request: DaemonRequest, done: String) async -> ProjectOutcome {
        lock.withLock { busyWith = subject }
        changed?()
        let response = await ask(request)
        lock.withLock {
            busyWith = nil
            if let projects = response?.projects { view = projects.projects }
        }
        changed?()
        guard let response else { return .failed("The runtime is not answering.") }
        guard response.ok else { return .failed(response.error ?? "The runtime refused this.") }
        let note = response.projectApplied.map(ProjectLines.appliedLine) ?? done
        if let proposed = response.proposed { return .proposed(id: proposed, note: note) }
        return .done(note)
    }

    /// A runtime that went away is said by `unreadable` and the outcome, never thrown at the page.
    private func ask(_ request: DaemonRequest) async -> DaemonResponse? {
        try? await link.request(request)
    }
}
