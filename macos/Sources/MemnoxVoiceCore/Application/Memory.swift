import Foundation

/// Which read failed, so each part of the page says its own.
public struct MemoryUnreadable: Equatable, Sendable {
    public var sources = false
    public var learn = false
    public var facts = false
}

/// Memory as the runtime keeps it: the sources a person pointed it at, the Learn queue read out of them, and the facts
/// a person confirmed. It holds no rule and no model: the runtime asks the person's own agent to read, a confirm is the
/// person's, and a rule a confirm raises waits for a signature on the island.
public final class Memory: @unchecked Sendable {
    private let link: DaemonLink
    private let ids: RequestIds
    private let lock = NSLock()
    private var sourceList: [MemorySourceView]?
    private var queue: MemoryItemsView?
    private var listed: MemoryItemsView?
    private var shown = MemoryFilter()
    /// Counts the filters asked, so an answer to an older one never overwrites a newer one.
    private var asked = 0
    private var reads: [String: MemoryReadSummary] = [:]
    private var failed = MemoryUnreadable()
    private var busyWith: String?
    private var searched: MemorySearch?

    /// Told after anything here changed, on whatever thread that happened.
    public var changed: (@Sendable () -> Void)?

    /// The subject a press on Add source works under, so the sheet's button can say so.
    public static let adding = "add"

    public init(link: DaemonLink, ids: RequestIds = RequestIds()) {
        self.link = link
        self.ids = ids
    }

    public var sources: [MemorySourceView]? { lock.withLock { sourceList } }
    public var learn: MemoryItemsView? { lock.withLock { queue } }
    public var facts: MemoryItemsView? { lock.withLock { listed } }
    public var filter: MemoryFilter { lock.withLock { shown } }
    public var unreadable: MemoryUnreadable { lock.withLock { failed } }
    /// How the last search was answered, by keyword or by meaning, and why it fell back; nil when the list is no search.
    public var search: MemorySearch? { lock.withLock { searched } }

    /// The source or item a press is still working on, so its controls can say so.
    public var busy: String? { lock.withLock { busyWith } }

    /// The last read of a source made here, said under its card.
    public func lastRead(_ sourceId: String) -> MemoryReadSummary? {
        lock.withLock { reads[sourceId] }
    }

    public func refreshSources() async {
        let response = await ask(DaemonRequest(id: ids.next(), method: .memorySources))
        lock.withLock {
            failed.sources = response?.ok != true
            take(response)
        }
        changed?()
    }

    public func refreshLearn() async {
        let response = await ask(DaemonRequest(id: ids.next(), method: .memoryLearn))
        lock.withLock {
            failed.learn = response?.ok != true
            take(response)
        }
        changed?()
    }

    /// Reads the list again under a filter, a search when it carries words.
    public func show(_ filter: MemoryFilter) async {
        let ticket = lock.withLock {
            shown = filter
            asked += 1
            return asked
        }
        let query = (filter.query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var request = DaemonRequest(id: ids.next(), method: query.isEmpty ? .memoryFacts : .memorySearch)
        if query.isEmpty { request.memoryStatus = filter.status.rawValue } else { request.memoryQuery = query }
        request.memoryScope = filter.scope?.rawValue
        let response = await ask(request)
        let current = lock.withLock {
            // A newer filter chosen while this one was asked wins.
            guard ticket == asked else { return false }
            failed.facts = response?.ok != true
            listed = response?.memoryFacts ?? (response?.ok == true ? MemoryItemsView(items: []) : listed)
            searched = MemorySearch(query: query, response: response)
            return true
        }
        if current { changed?() }
    }

    /// Kept at once; the runtime reads it in the background, so what it taught arrives on the next look.
    public func addSource(_ input: MemorySourceInput) async -> MemoryOutcome {
        var request = DaemonRequest(id: ids.next(), method: .memorySourceAdd)
        request.memorySource = input
        return await change(Self.adding, request) { _ in "Added. Memnox is reading it now, and what it finds waits in Learn." }
    }

    public func removeSource(_ id: String) async -> MemoryOutcome {
        var request = DaemonRequest(id: ids.next(), method: .memorySourceRemove)
        request.memorySourceId = id
        return await change(id, request) { _ in "Removed. What it taught is kept as outdated rather than lost." }
    }

    public func readNow(_ id: String) async -> MemoryOutcome {
        var request = DaemonRequest(id: ids.next(), method: .memorySourceRead)
        request.memorySourceId = id
        return await change(id, request) { [self] response in
            guard let summary = response.memoryRead else { return "Read." }
            lock.withLock { reads[id] = summary }
            return MemoryLines.readSummaryLine(summary)
        }
    }

    public func confirm(_ id: String, keyTitle: String) async -> MemoryOutcome {
        var request = DaemonRequest(id: ids.next(), method: .memoryConfirm)
        request.memoryItemId = id
        return await change(id, request) { response in
            MemoryLines.confirmedLine(kind: response.memoryItem?.kind ?? MemoryKind.fact.rawValue, proposed: response.proposed != nil,
                                      keyTitle: keyTitle)
        }
    }

    public func reject(_ id: String) async -> MemoryOutcome {
        var request = DaemonRequest(id: ids.next(), method: .memoryReject)
        request.memoryItemId = id
        return await change(id, request) { _ in "Rejected. The same words are never proposed again." }
    }

    /// New words before it is confirmed, kept exactly as typed.
    public func edit(_ id: String, statement: String) async -> MemoryOutcome {
        var request = DaemonRequest(id: ids.next(), method: .memoryEdit)
        request.memoryItemId = id
        request.memoryEdit = MemoryEditInput(statement: statement)
        return await change(id, request) { _ in "Saved. Confirm it when it says what you mean." }
    }

    public func forget(_ id: String) async -> MemoryOutcome {
        var request = DaemonRequest(id: ids.next(), method: .memoryForget)
        request.memoryItemId = id
        let outcome = await change(id, request) { _ in "Forgotten, with its evidence." }
        if case .done = outcome {
            let removed = lock.withLock {
                guard let list = listed else { return false }
                listed = MemoryItemsView(items: list.items.filter { $0.id != id }, more: list.more)
                return true
            }
            if removed { changed?() }
        }
        return outcome
    }

    /// Takes what an answer carries; called with the lock held.
    private func take(_ response: DaemonResponse?) {
        if let sources = response?.memorySources { sourceList = sources }
        if let learn = response?.memoryLearn { queue = learn }
    }

    private func change(_ subject: String, _ request: DaemonRequest, done: (DaemonResponse) -> String) async -> MemoryOutcome {
        lock.withLock { busyWith = subject }
        changed?()
        let response = await ask(request)
        lock.withLock {
            busyWith = nil
            take(response)
        }
        guard let response else {
            changed?()
            return .failed("The runtime is not answering.")
        }
        guard response.ok else {
            changed?()
            return .failed(response.error ?? "The runtime refused this.")
        }
        let note = done(response)
        changed?()
        if let proposed = response.proposed { return .proposed(id: proposed, note: note) }
        return .done(note)
    }

    /// A runtime that went away is said by `unreadable` and the outcome, never thrown at the page.
    private func ask(_ request: DaemonRequest) async -> DaemonResponse? {
        try? await link.request(request)
    }
}

/// How a search was answered, as the runtime says it.
public struct MemorySearch: Equatable, Sendable {
    public let mode: MemorySearchMode
    /// Why it was keyword only although search by meaning is on.
    public let note: String?

    public init(mode: MemorySearchMode, note: String? = nil) {
        self.mode = mode
        self.note = note
    }

    /// Nil for a list that is no search; an older runtime that names no mode searched by keyword.
    init?(query: String, response: DaemonResponse?) {
        guard !query.isEmpty, let response, response.ok else { return nil }
        mode = response.memorySearchMode.flatMap(MemorySearchMode.init(rawValue:)) ?? .keyword
        note = response.memorySearchNote
    }
}
