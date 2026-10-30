import Foundation

/// How an Install ended: said in a line, since a skill only waits in My Skills and a pack only waits on the island.
public enum IndexOutcome: Equatable, Sendable {
    case done(String)
    case failed(String)
}

/// What Discover asks the runtime for: words and a kind; the category is filtered by the window.
public struct IndexFilter: Equatable, Sendable {
    public var query = ""
    public var kind = IndexKindFilter.all

    public init(query: String = "", kind: IndexKindFilter = .all) {
        self.query = query
        self.kind = kind
    }
}

/// The community index as the runtime reads it. Nothing here installs anything live: the runtime checks the digest, a
/// skill waits in My Skills for acceptance and a pack's rules each wait for a Touch ID signature on the island.
public final class CommunityIndex: @unchecked Sendable {
    private let link: DaemonLink
    private let ids: RequestIds
    private let keyTitle: String
    private let lock = NSLock()
    private var view: CommunityIndexView?
    private var packList: [IndexEntryView]?
    private var shown = IndexFilter()
    private var failed = false
    private var busyWith: String?

    /// Told after anything here changed, on whatever thread that happened.
    public var changed: (@Sendable () -> Void)?

    /// What `busy` reads while a fresh read runs.
    public static let refreshing = "refresh"

    public init(link: DaemonLink, ids: RequestIds = RequestIds(), keyTitle: String = "Touch ID") {
        self.link = link
        self.ids = ids
        self.keyTitle = keyTitle
    }

    public var index: CommunityIndexView? { lock.withLock { view } }

    /// Rule packs alone, read for Governance > Policies without disturbing what Discover shows.
    public var packs: [IndexEntryView]? { lock.withLock { packList } }

    public var filter: IndexFilter { lock.withLock { shown } }

    /// The last read failed, so the page says so rather than drawing an empty index.
    public var unreadable: Bool { lock.withLock { failed } }

    /// The listing an Install, or `refreshing` for a fresh read, is still working on.
    public var busy: String? { lock.withLock { busyWith } }

    /// Reads with the filter given, or the one shown; `fresh` reads the index again rather than what was last read.
    public func refresh(_ filter: IndexFilter? = nil, fresh: Bool = false) async {
        let asked = filter ?? self.filter
        lock.withLock {
            shown = asked
            if fresh { busyWith = Self.refreshing }
        }
        changed?()
        var request = DaemonRequest(id: ids.next(), method: .indexList)
        let words = asked.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !words.isEmpty { request.indexQuery = words }
        if asked.kind != .all { request.indexKind = asked.kind.rawValue }
        if fresh { request.indexRefresh = true }
        let response = await ask(request)
        lock.withLock {
            if fresh { busyWith = nil }
            failed = response?.ok != true
            if let index = response?.communityIndex { view = index }
        }
        changed?()
    }

    public func readPacks() async {
        var request = DaemonRequest(id: ids.next(), method: .indexList)
        request.indexKind = IndexKind.rulePack.rawValue
        let response = await ask(request)
        lock.withLock {
            if let index = response?.communityIndex { packList = index.entries } else if response?.ok == true { packList = [] }
        }
        changed?()
    }

    /// Installs a version, or the newest not marked unsafe; the runtime refuses one marked unsafe either way.
    public func install(_ name: String, version: String? = nil) async -> IndexOutcome {
        lock.withLock { busyWith = name }
        changed?()
        var request = DaemonRequest(id: ids.next(), method: .indexInstall)
        request.indexName = name
        request.indexVersion = version
        let response = await ask(request)
        lock.withLock {
            busyWith = nil
            if let index = response?.communityIndex { view = index }
        }
        changed?()
        guard let response else { return .failed("The runtime is not answering.") }
        guard response.ok else { return .failed(response.error ?? "The runtime refused this.") }
        guard let installed = response.indexInstalled else { return .done("\(name) is installed.") }
        return .done(IndexLines.installedNote(installed, keyTitle: keyTitle))
    }

    /// A runtime that went away is said by `unreadable` and the outcome, never thrown at the page.
    private func ask(_ request: DaemonRequest) async -> DaemonResponse? {
        try? await link.request(request)
    }
}
