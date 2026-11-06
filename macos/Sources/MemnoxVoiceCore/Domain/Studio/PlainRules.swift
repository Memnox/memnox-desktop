import Foundation

/// The kind of protection a rule is, recognised from how it is written, so a family is said in the words of what it
/// protects rather than the action names it matches.
public enum RuleFamily: String, CaseIterable, Sendable {
    case secrets
    case destructiveGit
    case deletes
    case mcpTools
    case webRequests
    case cloudTools
    case databaseWrites
    /// Every action but the local ones a coding agent works with all day.
    case outsideCodingTools
    case everything
    case other
}

/// A rule as a person reads it in a list: a short title naming what it covers, the same words Windows and Linux use,
/// and one line saying why. The effect is said beside it, so the title never repeats it.
public struct PlainRule: Equatable, Sendable {
    public let title: String
    public let why: String?
    public let family: RuleFamily
    /// The agents the rule is for, said apart from the title; nil for every agent.
    public let only: String?

    public init(title: String, why: String?, family: RuleFamily, only: String? = nil) {
        self.title = title
        self.why = why
        self.family = family
        self.only = only
    }

    /// The row's caption: who it is for, where it is only for some agents, and why.
    public var caption: String? {
        let parts = [only.map { "Only for \($0)." }, why].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

/// Rules that read the same and do the same, shown once with how many stand behind the row.
public struct PlainRuleGroup: Equatable, Identifiable, Sendable {
    public let plain: PlainRule
    public let effect: String
    /// Never empty, since a group is made from the rule that opened it.
    public let rules: [PolicyRuleView]

    public var id: String { rules.first?.name ?? plain.title }
    public var count: Int { rules.count }
}

/// Turns a rule's match into plain words, as the console's `plainRule` does: the action names and glob patterns are
/// how a rule is written, not what it means to the person deciding whether it is right. Nothing here decides anything.
public enum PlainRules {
    private static let exclude: Character = "!"
    private static let namesShown = 3

    /// The family titles, word for word what Windows and Linux say.
    private static func title(_ family: RuleFamily) -> String? {
        switch family {
        case .secrets: "Reading secrets and credentials"
        case .destructiveGit: "Force-pushing and hard resets"
        case .deletes: "Deleting files"
        case .mcpTools: "MCP tools that change something"
        case .webRequests: "Web requests that change something"
        case .cloudTools: "Cloud, deploy and publish commands"
        case .databaseWrites: "Database changes"
        case .outsideCodingTools: "Anything outside the usual coding tools"
        case .everything: "Every action"
        case .other: nil
        }
    }

    /// Why each family exists, said where the rule carries no reason of its own.
    private static func why(_ family: RuleFamily) -> String? {
        switch family {
        case .secrets: "Almost no task needs the key itself, and a leaked one is hard to take back."
        case .destructiveGit: "It rewrites history somebody else may already have pulled."
        case .deletes: "Sometimes it really is the build folder, so a person should look first."
        case .mcpTools: "Other people see what these calls change, while a tool that only reads is how an agent finds its way."
        case .webRequests: "A request that posts or deletes changes somebody else\u{2019}s system."
        case .cloudTools: "A deploy, a merge or a delete lands on somebody else\u{2019}s system."
        case .databaseWrites: "A statement with no WHERE, a TRUNCATE or a DROP takes every row at once."
        case .outsideCodingTools: "Files, the shell, git and tests stay with the agent, and this covers the rest."
        case .everything, .other: nil
        }
    }

    /// Single actions in the console's own words, so a rule of one reads as the web says it.
    private static let actionWords: [String: String] = [
        "filesystem.read": "Reading files", "filesystem.write": "Changing files", "shell.*": "Shell commands",
        "shell.execute": "Shell commands", "git.push": "Pushing", "git.tag": "Tagging a release", "git.commit": "Committing",
        "git.merge": "Merging", "test.run": "Running tests", "code.modify": "Changing code", "code.read": "Reading code",
    ]

    /// Where credentials sit, as rule targets name them.
    private static let secretMarkers = [
        ".ssh", "id_rsa", "id_ed25519", ".aws", ".gcloud", ".kube", ".azure", ".env", ".gnupg", ".netrc", ".npmrc",
        "_KEY", "_SECRET", "_TOKEN", "_PASSWORD", "_CREDENTIALS", "DATABASE_URL", "MONGODB_URI", "REDIS_URL",
    ]
    /// Git verbs that throw away or rewrite work.
    private static let gitVerbs: Set<String> = [
        "push-force", "push-f", "push-force-with-lease", "reset-hard", "reset", "branch-d", "branch-delete-force", "branch-delete",
        "push-delete", "clean", "clean-f", "clean-fd", "clean-force", "stash-clear", "stash-drop", "reflog-expire", "reflog-delete",
        "filter-branch", "filter-repo", "gc-prune-now",
    ]
    private static let deleteActions: Set<String> = ["filesystem.delete", "file.delete", "fs.delete"]
    private static let webActions: Set<String> = ["http.request", "http.*", "web.request", "web.*", "fetch.*"]
    private static let databaseClients: Set<String> = ["psql", "pgcli", "mysql", "mariadb", "mycli", "mongosh", "sqlite3", "database"]
    private static let cloudClients: Set<String> = [
        "aws", "gcloud", "az", "gh", "kubectl", "terraform", "vercel", "railway", "fly", "heroku", "netlify", "stripe", "deploy",
    ]
    private static let outwardVerbs: Set<String> = ["docker.push", "npm.publish", "npm.unpublish"]
    /// The words the runtime writes before a setup answer's reason, which the effect already says.
    private static let chosenPrefix = "you chose to "

    public static func plain(_ rule: PolicyRuleView, agentName: (String) -> String = McpHubLines.agentLabel) -> PlainRule {
        plain(match: rule.match, effect: rule.ruleEffect, reason: rule.reason, agentName: agentName)
    }

    public static func plain(match: PolicyRuleMatch, effect: RuleEffect?, reason: String?,
                             agentName: (String) -> String = McpHubLines.agentLabel) -> PlainRule {
        let family = family(of: match)
        let only = match.agents.flatMap { $0.isEmpty ? nil : oneOf($0.map(agentName)) }
        let said = title(family) ?? fallback(match)
        let because = reasonLine(reason) ?? why(family) ?? effect.map { "\(StudioLines.words($0).says)." }
        return PlainRule(title: said, why: because, family: family, only: only)
    }

    /// The rules once each by what they say, do and whom they are for, in the order they came, so five rules that read
    /// alike are one row.
    public static func grouped(_ rules: [PolicyRuleView], agentName: (String) -> String = McpHubLines.agentLabel) -> [PlainRuleGroup] {
        var order: [String] = []
        var found: [String: (plain: PlainRule, effect: String, rules: [PolicyRuleView])] = [:]
        for rule in rules {
            let plain = plain(rule, agentName: agentName)
            let key = [rule.effect, plain.title, plain.only ?? ""].joined(separator: "\u{0}")
            if found[key] == nil {
                order.append(key)
                found[key] = (plain, rule.effect, [rule])
            } else {
                found[key]?.rules.append(rule)
            }
        }
        return order.compactMap { key in found[key].map { PlainRuleGroup(plain: $0.plain, effect: $0.effect, rules: $0.rules) } }
    }

    /// "3 rules say this", beside a row standing for more than one.
    public static func countLine(_ count: Int) -> String? {
        count > 1 ? "\(count) rules say this" : nil
    }

    /// The label of the disclosure holding the rule's own actions and patterns.
    public static let asWritten = "Show the rule as written"

    /// The rule's actions and targets as the runtime holds them, for whoever wants the pattern itself.
    public static func written(_ match: PolicyRuleMatch) -> [(label: String, value: String)] {
        var lines = [(label: "Actions", value: match.actions.joined(separator: ", "))]
        if let targets = match.targets, !targets.isEmpty { lines.append(("Targets", targets.joined(separator: ", "))) }
        if let agents = match.agents, !agents.isEmpty { lines.append(("Agents", agents.joined(separator: ", "))) }
        if let folders = match.workingDirectories, !folders.isEmpty { lines.append(("Folders", folders.joined(separator: ", "))) }
        if let branches = match.branches, !branches.isEmpty { lines.append(("Branches", branches.joined(separator: ", "))) }
        if let classes = match.classes, !classes.isEmpty { lines.append(("Kinds of call", classes.joined(separator: ", "))) }
        return lines
    }

    // MARK: Recognising

    public static func family(of match: PolicyRuleMatch) -> RuleFamily {
        let actions = match.actions.map { $0.lowercased() }
        let wanted = actions.filter { $0.first != exclude }
        let unwanted = actions.filter { $0.first == exclude }
        let targets = (match.targets ?? []).filter { $0.first != exclude }
        guard !wanted.isEmpty else { return .other }
        if targets.contains(where: { target in secretMarkers.contains { target.localizedCaseInsensitiveContains($0) } }) {
            return .secrets
        }
        if wanted.allSatisfy({ namespace($0) == "git" }),
           wanted.contains(where: { gitVerbs.contains(String($0.dropFirst("git.".count))) }) {
            return .destructiveGit
        }
        if wanted.allSatisfy(deleteActions.contains) { return .deletes }
        if wanted.contains("mcp.*"), wanted.allSatisfy({ namespace($0) == "mcp" }) { return .mcpTools }
        if wanted.allSatisfy(webActions.contains), targets.isEmpty { return .webRequests }
        if wanted.allSatisfy({ databaseClients.contains(namespace($0)) }) { return .databaseWrites }
        if wanted.allSatisfy({ cloudClients.contains(namespace($0)) || outwardVerbs.contains($0) }) { return .cloudTools }
        if wanted == ["*"] { return unwanted.isEmpty ? .everything : .outsideCodingTools }
        return .other
    }

    /// Any other rule: one action in the console's words, else at most three by name and the rest counted, and where.
    private static func fallback(_ match: PolicyRuleMatch) -> String {
        let wanted = match.actions.filter { $0.first != exclude }
        let places = placesLine(match.targets ?? []).map { " in \($0)" } ?? ""
        if wanted.count == 1, let only = wanted.first, let words = actionWords[only.lowercased()] {
            let branches = (match.branches ?? []).filter { $0.first != exclude }
            if only.lowercased() == "git.push", !branches.isEmpty { return "\(words) to \(counted(branches))\(places)" }
            return "\(words)\(places)"
        }
        var phrases: [String] = []
        for action in wanted {
            let phrase = RuleDetailLines.phrase(action)
            if !phrases.contains(phrase) { phrases.append(phrase) }
        }
        guard let first = phrases.first else { return "What this rule names\(places)" }
        let rest = phrases.dropFirst().map(lowerFirst)
        return "\(counted([first] + rest))\(places)"
    }

    // MARK: Saying

    /// A setup answer's reason without the words saying it was chosen, as a sentence.
    private static func reasonLine(_ reason: String?) -> String? {
        guard var line = reason?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else { return nil }
        if line.lowercased().hasPrefix(chosenPrefix) {
            guard let colon = line.firstIndex(of: ":") else { return nil }
            line = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard let first = line.first else { return nil }
        line = first.uppercased() + line.dropFirst()
        return line.hasSuffix(".") ? line : "\(line)."
    }

    /// Targets as places a person recognises: `**/.ssh/**` is `.ssh`, and an exclusion or a bare star names nothing.
    private static func placesLine(_ targets: [String]) -> String? {
        var places: [String] = []
        for target in targets where target.first != exclude {
            var place = target
            if place.hasPrefix("**/") { place.removeFirst(3) }
            if place.hasSuffix("/**") { place.removeLast(3) }
            if place.hasSuffix(".*") { place.removeLast(2) }
            if place.isEmpty || place.allSatisfy({ $0 == "*" }) || places.contains(place) { continue }
            places.append(place)
        }
        return places.isEmpty ? nil : counted(places)
    }

    /// "a, b and c", or "a, b, c and 4 more" past three.
    private static func counted(_ items: [String]) -> String {
        guard items.count > namesShown else { return oneOf(items) }
        return "\(items.prefix(namesShown).joined(separator: ", ")) and \(items.count - namesShown) more"
    }

    private static func oneOf(_ items: [String]) -> String {
        guard items.count > 1, let last = items.last else { return items.joined() }
        return "\(items.dropLast().joined(separator: ", ")) and \(last)"
    }

    private static func namespace(_ action: String) -> String {
        action.split(separator: ".", maxSplits: 1).first.map(String.init) ?? action
    }

    private static func lowerFirst(_ phrase: String) -> String {
        guard let first = phrase.first else { return phrase }
        // An acronym such as MCP keeps its capitals.
        if phrase.count > 1, phrase.dropFirst().first?.isUppercase == true { return phrase }
        return first.lowercased() + phrase.dropFirst()
    }
}
