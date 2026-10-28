import Foundation

/// How a press on the Layers view ended: written, refused with the runtime's reason, or the runtime gone.
public enum LayersOutcome: Equatable, Sendable {
    case written([String])
    case failed(String)
}

/// The memory layers as the runtime reads and writes them: each project's MEMORY.md, router files and skills, the
/// plan it previews, and the cold cache count. It decides nothing and writes nothing: the runtime builds the plan and
/// writes it only once the person confirmed the very plan shown, by its digest.
public final class MemoryLayers: @unchecked Sendable {
    private let link: DaemonLink
    private let ids: RequestIds
    private let lock = NSLock()
    private var view: MemoryLayersView?
    private var shownPlan: MemoryLayersPlan?
    /// What the shown plan was asked with, so apply sends the same and the digest matches.
    private var planAsk: (project: String, agent: String?, keep: [String])?
    private var cost: SessionCostView?
    private var failed = false
    private var busyWith: String?

    /// Told after anything here changed, on whatever thread that happened.
    public var changed: (@Sendable () -> Void)?

    public init(link: DaemonLink, ids: RequestIds = RequestIds()) {
        self.link = link
        self.ids = ids
    }

    public var layers: MemoryLayersView? { lock.withLock { view } }
    public var plan: MemoryLayersPlan? { lock.withLock { shownPlan } }
    public var sessionCost: SessionCostView? { lock.withLock { cost } }
    /// The last read failed or came from a runtime too old to answer it, so the view says so.
    public var unreadable: Bool { lock.withLock { failed } }
    /// The project a press is still working on.
    public var busy: String? { lock.withLock { busyWith } }

    public func refresh() async {
        let layers = await ask(DaemonRequest(id: ids.next(), method: .memoryLayers))
        let counted = await ask(DaemonRequest(id: ids.next(), method: .sessionCost))
        lock.withLock {
            failed = layers?.ok != true || layers?.memoryLayers == nil
            if let read = layers?.memoryLayers { view = read }
            if let read = counted?.sessionCost { cost = read }
        }
        changed?()
    }

    /// Asks the runtime for the map it would write; nothing is written by this.
    public func preview(project: String, agent: String? = nil, keep: [String]) async -> LayersOutcome? {
        var request = DaemonRequest(id: ids.next(), method: .memoryLayersPlan)
        request.memoryLayersProject = project
        request.memoryLayersAgent = agent
        request.memoryKeep = keep
        let response = await working(project) { await self.ask(request) }
        guard let response else { return .failed("The runtime is not answering.") }
        guard response.ok, let plan = response.memoryLayersPlan else {
            return .failed(response.error ?? "The runtime could not plan the layers.")
        }
        lock.withLock {
            shownPlan = plan
            planAsk = (project, agent, keep)
        }
        changed?()
        return nil
    }

    /// Writes the plan the person confirmed, sending its digest so a plan whose files changed is refused.
    public func confirm() async -> LayersOutcome {
        guard let (plan, asked) = lock.withLock({ shownPlan.flatMap { plan in planAsk.map { (plan, $0) } } }) else {
            return .failed("There is no plan to confirm.")
        }
        var request = DaemonRequest(id: ids.next(), method: .memoryLayersApply)
        request.memoryLayersProject = asked.project
        request.memoryLayersAgent = asked.agent
        request.memoryKeep = asked.keep
        request.memoryLayersDigest = plan.digest
        let response = await working(asked.project) { await self.ask(request) }
        guard let response else { return .failed("The runtime is not answering.") }
        guard response.ok else { return .failed(response.error ?? "The runtime refused this.") }
        lock.withLock {
            shownPlan = nil
            planAsk = nil
            if let updated = response.memoryLayers { view = merged(updated) }
        }
        changed?()
        return .written(response.memoryLayersApplied?.written ?? [])
    }

    /// The sheet closed without confirming, so the plan is forgotten.
    public func dismissPlan() {
        lock.withLock {
            shownPlan = nil
            planAsk = nil
        }
        changed?()
    }

    /// One project read again after apply, laid over the rest.
    private func merged(_ updated: MemoryLayersView) -> MemoryLayersView {
        guard let current = view else { return updated }
        let fresh = Dictionary(uniqueKeysWithValues: updated.projects.map { ($0.path, $0) })
        return MemoryLayersView(projects: current.projects.map { fresh[$0.path] ?? $0 }, value: updated.value)
    }

    private func working<T>(_ subject: String, _ body: () async -> T) async -> T {
        lock.withLock { busyWith = subject }
        changed?()
        let result = await body()
        lock.withLock { busyWith = nil }
        changed?()
        return result
    }

    /// A runtime that went away is said by the outcome, never thrown at the page.
    private func ask(_ request: DaemonRequest) async -> DaemonResponse? {
        try? await link.request(request)
    }
}
