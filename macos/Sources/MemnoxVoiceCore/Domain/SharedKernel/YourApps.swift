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

/// One card on the Your apps screen, drawn as the console's connector card: a tool, its name, its logo, the catalogue's
/// words and tags for it where the cloud sent them, and where it stands.
public struct YourAppCard: Equatable, Identifiable, Sendable {
    public let slug: String
    public let name: String
    public let logo: String?
    public let standing: YourAppStanding
    /// The provider's own words for it, nil where the catalogue had none or was not asked.
    public let description: String?
    /// The provider's tags, as written, which the categories rail counts.
    public let categories: [String]
    public let kind: ToolkitKind?
    public let support: ToolkitSupport?
    /// When its working sign in was made, for "Connected since".
    public let connectedSince: Date?
    /// The agents that worked in it through Memnox lately, newest first, as the daemon's ledger names them.
    public let uses: [AppUse]
    /// Where the catalogue says it comes from, for the order chip; nil from a runtime that does not say.
    public let source: ConnectorSource?
    public let weight: Int?

    public var id: String { slug }
    /// The order chip, such as Official 4, or nil where the runtime did not say where it comes from.
    public var orderChip: String? {
        guard let source else { return nil }
        return weight.map { "\(ConnectorOrderLines.chip(source)) \($0)" } ?? ConnectorOrderLines.chip(source)
    }

    public init(slug: String, name: String, logo: String? = nil, standing: YourAppStanding, description: String? = nil,
                categories: [String] = [], kind: ToolkitKind? = nil, support: ToolkitSupport? = nil,
                connectedSince: Date? = nil, uses: [AppUse] = [], source: ConnectorSource? = nil, weight: Int? = nil) {
        self.source = source
        self.weight = weight
        self.uses = uses
        self.slug = slug
        self.name = name
        self.logo = logo
        self.standing = standing
        self.description = description
        self.categories = categories
        self.kind = kind
        self.support = support
        self.connectedSince = connectedSince
    }

    /// The line under the name, in the console's words for the cloud's reading; nil where the cloud sent none.
    public var kindLine: String? {
        switch kind {
        case .record: "System of record"
        case .conversation: "System of conversation"
        case .other: "Other"
        case nil: nil
        }
    }

    /// The pill beside the name, in the console's words; nil where the cloud did not say how fully it reads it.
    public var supportPill: String? {
        switch support {
        case .full: "Fully supported"
        case .partial: "Limited support"
        case nil: nil
        }
    }

    /// The status line, as the console's card says it.
    public var statusLine: String {
        switch standing {
        case .onThisMac: "On this Mac"
        case .connected: connectedSince.map { "Connected since \(YourApps.since($0))" } ?? "Connected"
        case .signInAgain: standing.line
        case .available: "Not connected"
        }
    }

    /// Said on a connected app, since the person's agents reach it through Memnox rather than holding its sign in.
    public static let throughMemnoxLine = "Your agents can use it through Memnox"

    /// The line under the status on a connected app: that agents reach it, and which did lately where any did.
    public func agentsLine(name: (String) -> String) -> String? {
        guard standing == .connected else { return nil }
        let named = uses.map { name($0.agent) }
        guard !named.isEmpty else { return Self.throughMemnoxLine }
        return "\(Self.throughMemnoxLine). Used lately by \(YourApps.listed(named))"
    }

    /// The card with the catalogue's words and tags laid on it, so a card made from a connection alone still reads fully.
    func described(by toolkit: ToolkitSummary?) -> YourAppCard {
        guard let toolkit else { return self }
        return YourAppCard(slug: slug, name: name, logo: logo ?? toolkit.logo, standing: standing,
                           description: description ?? YourApps.trimmed(toolkit.description),
                           categories: categories.isEmpty ? (toolkit.categories ?? []) : categories,
                           kind: kind ?? toolkit.toolkitKind, support: support ?? toolkit.supportLevel,
                           connectedSince: connectedSince, uses: uses, source: source ?? toolkit.connectorSource,
                           weight: weight ?? toolkit.weight)
    }
}

/// One row of the categories rail: the folded tag a card is matched on, the spelling a person reads, and how many.
public struct YourAppCategory: Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let count: Int

    public init(id: String, label: String, count: Int) {
        self.id = id
        self.label = label
        self.count = count
    }
}

/// The person's own tools as cards: those they have, then the catalogue's for what they typed, none of them twice.
public enum YourApps {
    public static func standing(_ connection: ToolConnection) -> YourAppStanding {
        if connection.isLocal { return .onThisMac }
        return connection.connected ? .connected : .signInAgain
    }

    /// What the person has, those on this Mac first and then by name, so the grid does not reorder as sign ins land,
    /// each described by the catalogue where it answered for that tool.
    public static func yours(_ connections: [ToolConnection], found: [ToolkitSummary] = []) -> [YourAppCard] {
        let named = bySlug(found)
        var seen = Set<String>()
        return connections
            .filter { seen.insert($0.toolkit).inserted }
            .map { connection in
                YourAppCard(slug: connection.toolkit, name: named[connection.toolkit]?.name ?? ToolkitName.of(connection.toolkit),
                            standing: standing(connection), connectedSince: date(connection.connectedAt),
                            uses: connection.usedBy ?? [])
                    .described(by: named[connection.toolkit])
            }
            .sorted { rank($0) != rank($1) ? rank($0) < rank($1) : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The catalogue's tools for the search, each marked with where it stands, so a tool already connected says so.
    public static func catalogue(_ found: [ToolkitSummary], connections: [ToolConnection]) -> [YourAppCard] {
        let have = Dictionary(connections.map { ($0.toolkit, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        return found.filter { seen.insert($0.slug).inserted }.map { toolkit in
            let connection = have[toolkit.slug]
            return YourAppCard(slug: toolkit.slug, name: toolkit.name, logo: toolkit.logo,
                               standing: connection.map(standing) ?? .available,
                               connectedSince: date(connection?.connectedAt), uses: connection?.usedBy ?? [])
                .described(by: toolkit)
        }
    }

    /// Every category on these cards, commonest first, each card counted once however it spells a tag, as the console counts.
    public static func categories(_ cards: [YourAppCard]) -> [YourAppCategory] {
        var found: [String: (label: String, count: Int)] = [:]
        for card in cards {
            var counted = Set<String>()
            for raw in card.categories {
                let id = fold(raw)
                guard !id.isEmpty, counted.insert(id).inserted else { continue }
                let held = found[id]
                found[id] = (label: held.map { bestLabel($0.label, raw) } ?? raw, count: (held?.count ?? 0) + 1)
            }
        }
        return found
            .map { YourAppCategory(id: $0.key, label: asWritten($0.value.label), count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.label.localizedCompare($1.label) == .orderedAscending }
    }

    /// Whether a card carries the category, by its folded tag; nil is every card.
    public static func inCategory(_ card: YourAppCard, _ category: String?) -> Bool {
        guard let category else { return true }
        return card.categories.contains { fold($0) == category }
    }

    /// The count beside the search, as the console's: those shown of those in the tab before a category narrows it.
    public static func showingLine(_ showing: Int, of total: Int) -> String {
        "\(showing) of \(total)"
    }

    /// What the page and the Connect button say while nobody is signed in to Memnox Cloud, which connecting needs.
    public static let signInTitle = "Sign in to Memnox Cloud to connect"
    public static let signInDetail = "Connecting your apps needs a Memnox Cloud account. It is what connects them and what works in them as you."
    public static let signInButton = "Sign in to connect"
    /// Said when the sign in was left unfinished, so the person knows nothing was connected.
    public static let signInStopped = "Signing in to Memnox Cloud did not finish, so nothing was connected."

    /// A date as the console's card writes it: Oct 2, 2026.
    public static func since(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year().locale(Locale(identifier: "en_US")))
    }

    /// An instant as the cloud writes it, with or without fractions of a second; nil for anything that is no date.
    static func date(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) { return date }
        return try? Date.ISO8601FormatStyle().parse(text)
    }

    static func trimmed(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private static func bySlug(_ found: [ToolkitSummary]) -> [String: ToolkitSummary] {
        Dictionary(found.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The provider spells one category several ways, "Team Chat" and "team-chat", so both fold to one before counting.
    static func fold(_ category: String) -> String {
        let lowered = category.lowercased().replacingOccurrences(of: "&", with: "and")
        var folded = ""
        var gap = false
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar), scalar.isASCII {
                if gap, !folded.isEmpty { folded.append("-") }
                folded.unicodeScalars.append(scalar)
                gap = false
            } else {
                gap = true
            }
        }
        return folded
    }

    /// A spelling with capitals is the written one, CRM over crm.
    private static func bestLabel(_ current: String, _ candidate: String) -> String {
        if hasCapital(current) || !hasCapital(candidate) { return current }
        return candidate
    }

    private static func hasCapital(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.uppercaseLetters.contains($0) }
    }

    /// Words read rather than typed, so these stay in capitals.
    private static let acronyms: Set<String> = ["ai", "api", "cms", "crm", "erp", "hr", "it", "lms", "seo", "sms"]

    /// A tag that arrived lowercase is cased here, as the console cases it; one already capitalised is left alone.
    private static func asWritten(_ label: String) -> String {
        if hasCapital(label) { return label }
        return label.split(separator: " ").map { word in
            let text = String(word)
            return acronyms.contains(text) ? text.uppercased() : text.prefix(1).uppercased() + text.dropFirst()
        }.joined(separator: " ")
    }

    /// The catalogue as the screen offers it: what the search found, or the featured tools where it could not be read.
    public static func offered(found: [ToolkitSummary], searchFailed: Bool, query: String,
                               connections: [ToolConnection]) -> [YourAppCard] {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard searchFailed, typed.isEmpty else { return catalogue(found, connections: connections) }
        let featured = FeaturedToolkits.slugs.map { ToolkitSummary(slug: $0, name: ToolkitName.of($0)) }
        return catalogue(featured, connections: connections)
    }

    /// What may be done in those apps a month, said before anybody meets the limit; the cloud enforces the numbers, and
    /// nothing is done in them before a Memnox Cloud sign in.
    public static let allowanceLine = "Free includes 500 actions a month in your apps once you sign in to Memnox Cloud. Paid plans have no limit."

    /// The count over the results, counted rather than estimated; the catalogue answers at most thirty a search.
    public static func countLine(_ count: Int, query: String) -> String {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let apps = count == 1 ? "1 app" : "\(count) apps"
        if typed.isEmpty { return count == 0 ? "No apps to show" : apps }
        return count == 0 ? "No app matches \u{201C}\(typed)\u{201D}" : "\(apps) \(count == 1 ? "matches" : "match") \u{201C}\(typed)\u{201D}"
    }

    /// Names joined as a sentence says them: "A", "A and B", "A, B and C".
    static func listed(_ names: [String]) -> String {
        guard let last = names.last else { return "" }
        let rest = names.dropLast()
        return rest.isEmpty ? last : "\(rest.joined(separator: ", ")) and \(last)"
    }

    private static func rank(_ card: YourAppCard) -> Int {
        switch card.standing {
        case .onThisMac: 0
        case .connected, .signInAgain: 1
        case .available: 2
        }
    }
}
