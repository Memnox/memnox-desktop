import Foundation

/// The tools Memnox Cloud's catalogue offers for a search, or why none could be read.
public enum ToolkitsAnswer: Equatable, Sendable {
    case toolkits([ToolkitSummary])
    /// The daemon said no in its own words, such as nobody signed in to Memnox Cloud yet.
    case refused(String)
    case unreachable
}

/// What became of asking to sign in to a tool: its sign in page, or why not.
public enum ConnectionSignInAnswer: Equatable, Sendable {
    /// The page to finish in; opened says whether the daemon already put it in the browser.
    case started(ConnectionSignIn)
    /// The daemon said no in its own words, such as the tool being connected already.
    case refused(String)
    case unreachable
}

/// Connects any tool the person uses and disconnects it again, with no admin in between: the daemon holds the
/// sign in and the cloud keeps it, so this only carries the person's wish and reads back where each tool stands.
public final class AppConnections {
    private let link: DaemonLink
    private let ids: RequestIds
    private let sleep: (TimeInterval) async throws -> Void

    /// How often the list is read while the browser sign in is under way.
    static let watchInterval: TimeInterval = 3
    /// Two minutes of reads, long enough for a sign in with a second factor and short enough to stop for one abandoned.
    static let watchReads = 40

    /// Said for a daemon that answers a method it does not know with a bare ok.
    private static let older = "This Memnox is older than the app"

    public init(link: DaemonLink, ids: RequestIds = RequestIds(),
                sleep: @escaping (TimeInterval) async throws -> Void = DaemonSignIn.taskSleep) {
        self.link = link
        self.ids = ids
        self.sleep = sleep
    }

    /// The person's connected tools as the daemon reads them now.
    public func list() async -> ConnectionsAnswer {
        guard let response = try? await link.request(DaemonRequest(id: ids.next(), method: .connectionsList)) else {
            return .unreachable
        }
        return Self.connections(response)
    }

    /// The catalogue's tools matching the words; blank words list its first page.
    public func search(_ words: String) async -> ToolkitsAnswer {
        var request = DaemonRequest(id: ids.next(), method: .toolkitsSearch)
        let query = words.trimmingCharacters(in: .whitespacesAndNewlines)
        request.query = query.isEmpty ? nil : query
        guard let response = try? await link.request(request) else { return .unreachable }
        if response.ok, let toolkits = response.toolkits { return .toolkits(toolkits) }
        return .refused(Self.why(response))
    }

    /// Opens the tool's own sign in; again asks for a fresh one where one already works, to use another account.
    public func signIn(_ toolkit: String, again: Bool = false) async -> ConnectionSignInAnswer {
        var request = DaemonRequest(id: ids.next(), method: .connectionsSignIn)
        request.toolkit = toolkit
        if again { request.again = true }
        guard let response = try? await link.request(request) else { return .unreachable }
        if response.ok, let signIn = response.signIn { return .started(signIn) }
        return .refused(Self.why(response))
    }

    /// Takes the tool's sign in away, answered with the list as it stands after.
    public func signOut(_ toolkit: String) async -> ConnectionsAnswer {
        var request = DaemonRequest(id: ids.next(), method: .connectionsSignOut)
        request.toolkit = toolkit
        guard let response = try? await link.request(request) else { return .unreachable }
        return Self.connections(response)
    }

    /// Reads the list while the person finishes in the browser, until it differs from the one before or time runs out,
    /// since the cloud only knows the sign in once the tool's own page has sent them back.
    public func watch(from before: [ToolConnection]) async -> ConnectionsAnswer {
        var last = ConnectionsAnswer.unreachable
        for _ in 0..<Self.watchReads {
            do { try await sleep(Self.watchInterval) } catch { return last }
            last = await list()
            if case .connections(let now) = last, now != before { return last }
        }
        return last
    }

    private static func connections(_ response: DaemonResponse) -> ConnectionsAnswer {
        if response.ok, let connections = response.connections { return .connections(connections) }
        return .refused(why(response))
    }

    private static func why(_ response: DaemonResponse) -> String {
        response.error ?? response.reason ?? older
    }
}
