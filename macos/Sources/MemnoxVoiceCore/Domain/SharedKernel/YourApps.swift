import Foundation

/// Where one tool stands for the person at this Mac, which decides the words on its card and its one button.
public enum YourAppStanding: Equatable, Sendable {
    /// Reached on this Mac itself, so there is nothing to connect or disconnect here.
    case onThisMac
    case connected
    /// Connected once and no longer working, so signing in again is what it needs.
    case signInAgain
    case available

    /// The one line under a tool's name.
    public var line: String {
        switch self {
        case .onThisMac: "Already on this Mac"
        case .connected: "Connected"
        case .signInAgain: "Sign in again to use it"
        case .available: "Sign in with your own account"
        }
    }
}

/// One card on the Your apps screen: a tool, the name it goes by, its logo where the catalogue has one, and where it stands.
public struct YourAppCard: Equatable, Identifiable, Sendable {
    public let slug: String
    public let name: String
    public let logo: String?
    public let standing: YourAppStanding

    public var id: String { slug }

    public init(slug: String, name: String, logo: String? = nil, standing: YourAppStanding) {
        self.slug = slug
        self.name = name
        self.logo = logo
        self.standing = standing
    }
}

/// The person's own tools as cards: those they have, then the catalogue's for what they typed, none of them twice.
public enum YourApps {
    public static func standing(_ connection: ToolConnection) -> YourAppStanding {
        if connection.isLocal { return .onThisMac }
        return connection.connected ? .connected : .signInAgain
    }

    /// What the person has, those on this Mac first and then by name, so the grid does not reorder as sign ins land.
    public static func yours(_ connections: [ToolConnection]) -> [YourAppCard] {
        var seen = Set<String>()
        return connections
            .filter { seen.insert($0.toolkit).inserted }
            .map { YourAppCard(slug: $0.toolkit, name: ToolkitName.of($0.toolkit), standing: standing($0)) }
            .sorted { rank($0) != rank($1) ? rank($0) < rank($1) : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The catalogue's tools for the search, each marked with where it stands, so a tool already connected says so.
    public static func catalogue(_ found: [ToolkitSummary], connections: [ToolConnection]) -> [YourAppCard] {
        let have = Dictionary(connections.map { ($0.toolkit, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        return found.filter { seen.insert($0.slug).inserted }.map { toolkit in
            YourAppCard(slug: toolkit.slug, name: toolkit.name, logo: toolkit.logo,
                        standing: have[toolkit.slug].map(standing) ?? .available)
        }
    }

    /// The catalogue as the screen offers it: what the search found, or the featured tools where it could not be read.
    public static func offered(found: [ToolkitSummary], searchFailed: Bool, query: String,
                               connections: [ToolConnection]) -> [YourAppCard] {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard searchFailed, typed.isEmpty else { return catalogue(found, connections: connections) }
        let featured = FeaturedToolkits.slugs.map { ToolkitSummary(slug: $0, name: ToolkitName.of($0)) }
        return catalogue(featured, connections: connections)
    }

    /// The count over the results, counted rather than estimated; the catalogue answers at most thirty a search.
    public static func countLine(_ count: Int, query: String) -> String {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let apps = count == 1 ? "1 app" : "\(count) apps"
        if typed.isEmpty { return count == 0 ? "No apps to show" : apps }
        return count == 0 ? "No app matches \u{201C}\(typed)\u{201D}" : "\(apps) \(count == 1 ? "matches" : "match") \u{201C}\(typed)\u{201D}"
    }

    private static func rank(_ card: YourAppCard) -> Int {
        switch card.standing {
        case .onThisMac: 0
        case .connected, .signInAgain: 1
        case .available: 2
        }
    }
}
