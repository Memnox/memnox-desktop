import Foundation

/// How an Install ended: said in a line, since a skill only waits in My Skills and a pack only waits on the island.
public enum IndexOutcome: Equatable, Sendable {
    case done(String)
    case failed(String)
}

/// The rule packs the community index offers, as the runtime reads them for Rules. Nothing here installs anything
/// live: the runtime checks the digest and a pack's rules each wait for a Touch ID signature on the island.
public final class CommunityIndex: @unchecked Sendable {
    private let link: DaemonLink
    private let ids: RequestIds
    private let keyTitle: String
    private let lock = NSLock()
    private var packList: [IndexEntryView]?
    private var busyWith: String?

    /// Told after anything here changed, on whatever thread that happened.
    public var changed: (@Sendable () -> Void)?

    public init(link: DaemonLink, ids: RequestIds = RequestIds(), keyTitle: String = "Touch ID") {
        self.link = link
        self.ids = ids
        self.keyTitle = keyTitle
    }

    /// The rule packs, nil until read.
    public var packs: [IndexEntryView]? { lock.withLock { packList } }

    /// The pack an Install is still working on.
    public var busy: String? { lock.withLock { busyWith } }

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
        lock.withLock { busyWith = nil }
        changed?()
        guard let response else { return .failed("The runtime is not answering.") }
        guard response.ok else { return .failed(response.error ?? "The runtime refused this.") }
        guard let installed = response.indexInstalled else { return .done("\(name) is installed.") }
        return .done(IndexLines.installedNote(installed, keyTitle: keyTitle))
    }

    /// A runtime that went away is said by the outcome, never thrown at the page.
    private func ask(_ request: DaemonRequest) async -> DaemonResponse? {
        try? await link.request(request)
    }
}
