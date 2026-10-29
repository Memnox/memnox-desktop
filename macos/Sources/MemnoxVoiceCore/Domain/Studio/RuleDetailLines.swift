import Foundation

/// A rule said the way the console's rule panel says it: the actions as a title, then one plain sentence for whoever
/// has to decide whether it is right, before the code for whoever has to recognise it in their own file.
public enum RuleDetailLines {
    /// Actions the runtime ships with, in the words the work is actually described in.
    private static let named: [String: String] = [
        "code.modify": "Change code", "code.read": "Read code", "data.export": "Export data",
        "database.delete": "Delete database records", "database.migrate": "Run a database migration",
        "database.read": "Read from the database", "database.truncate": "Empty a database table",
        "deploy.service": "Deploy a service", "filesystem.delete": "Delete a file", "filesystem.read": "Read a file",
        "filesystem.write": "Write a file", "git.commit": "Commit code", "llm.spend": "Spend on AI usage",
        "mcp.delete_repository": "Delete a repository", "mcp.merge_pull_request": "Merge a pull request",
        "mcp.search_issues": "Search issues", "shell.execute": "Run a shell command", "test.run": "Run tests",
        "ticket.read": "Read a support ticket", "ticket.reply": "Reply to a support ticket",
    ]

    /// Namespaces that say how a thing was called, not what was done.
    private static let namespaces: Set<String> = ["mcp", "api", "rpc", "tool", "fn"]
    /// Last segments that are the verb, so the phrase can be turned around.
    private static let verbs: Set<String> = [
        "create", "commit", "delete", "deploy", "execute", "export", "import", "merge", "migrate", "modify", "read",
        "reply", "run", "search", "spend", "truncate", "update", "write",
    ]
    /// What the runtime names a command its verb table does not cover.
    private static let unknownVerb = ".unknown"
    private static let fallback = "Automated action"
    private static let anyAgent = "any agent"

    /// A machine action name as a person would say it: a named action in its own phrase, anything else verb first
    /// where that reads and sentence cased where it does not.
    public static func phrase(_ action: String) -> String {
        if let named = named[action] { return named }
        if action.hasSuffix(unknownVerb), !action.contains("/") {
            return "A \(action.dropLast(unknownVerb.count)) command Memnox does not recognise"
        }
        // A path or an address is never shown, whatever else it might contain.
        if action.isEmpty || action.contains(where: { "/:@".contains($0) }) { return fallback }
        var words = action.split { !($0.isLetter || $0.isNumber) }.map(String.init)
        if words.count > 1, namespaces.contains(words[0].lowercased()) { words.removeFirst() }
        if words.count > 1, let last = words.last?.lowercased(), verbs.contains(last) {
            words = [last] + words.dropLast()
        }
        guard let first = words.first?.first else { return fallback }
        let joined = words.joined(separator: " ")
        return first.uppercased() + joined.dropFirst()
    }

    /// The actions as the panel's title.
    public static func title(_ actions: [String]) -> String {
        actions.map(phrase).joined(separator: ", ")
    }

    /// What the effect does to the agent, as the end of a sentence about it.
    public static func then(_ effect: RuleEffect) -> String {
        switch effect {
        case .allow: "goes ahead on its own"
        case .ask: "waits for a person to say yes"
        case .deny: "is refused and told what to do instead"
        }
    }

    /// The rule as one sentence: who, what, where, and what happens then.
    public static func sentence(agents: [String]?, actions: [String], targets: [String]?, effect: RuleEffect,
                                agentName: (String) -> String) -> String {
        let who = agents.flatMap { $0.isEmpty ? nil : $0.map(agentName).joined(separator: ", ") } ?? anyAgent
        let what = title(actions).lowercased()
        let on = targets.flatMap { $0.isEmpty ? nil : " on \($0.joined(separator: ", "))" } ?? ""
        return "When \(who) tries to \(what)\(on), it \(then(effect))."
    }
}
