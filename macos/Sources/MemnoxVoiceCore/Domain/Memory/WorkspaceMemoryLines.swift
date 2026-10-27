import Foundation

// What the Memory page says about the workspace's memory: where a decision stands, the tool it was read from and who
// said it, as the console says it, and what to do while there is none. Words only; nothing here decides anything.

public enum WorkspaceMemoryLines {
    /// The detail under a workspace tool's name, so it is never mistaken for an app this Mac signed in to.
    public static let toolDetail = "A tool your workspace reads from"
    public static let personDetail = "Named in your workspace's memory"
    /// The filter chips, in the order they stand.
    public static let filters: [(filter: MemoryHomeFilter, label: String)] = [
        (.everything, "Everything"), (.thisMac, "This Mac"), (.workspace, "Workspace"),
    ]
    /// A date written as the control plane writes it, read by its day.
    private static let dayLength = 10

    /// The hosts that name one product outright, keyed to the toolkit slug the marks are drawn from, as the console's
    /// memory map reads them. A company's own domain names no tool, so it is absent rather than guessed.
    private static let hosts: [(host: String, slug: String)] = [
        ("github.com", "github"), ("gitlab.com", "gitlab"), ("bitbucket.org", "bitbucket"), ("slack.com", "slack"),
        ("notion.so", "notion"), ("linear.app", "linear"), ("figma.com", "figma"), ("atlassian.net", "jira"),
        ("zendesk.com", "zendesk"), ("docs.google.com", "googledocs"), ("drive.google.com", "googledrive"),
        ("mail.google.com", "gmail"), ("dropbox.com", "dropbox"), ("asana.com", "asana"), ("trello.com", "trello"),
        ("monday.com", "monday"), ("intercom.com", "intercom"), ("hubspot.com", "hubspot"),
        ("salesforce.com", "salesforce"), ("sentry.io", "sentry"), ("pagerduty.com", "pagerduty"),
        ("confluence.com", "confluence"), ("clickup.com", "clickup"), ("discord.com", "discord"),
    ]

    /// How a person writes a tool's name, the runtime's own list, and the slug itself for one it does not know.
    private static let toolNames: [String: String] = [
        "slack": "Slack", "notion": "Notion", "linear": "Linear", "github": "GitHub", "jira": "Jira", "gmail": "Gmail",
        "email": "Email", "discord": "Discord", "confluence": "Confluence", "document": "A document", "meeting": "A meeting",
        "calendar": "A calendar", "googledocs": "Google Docs", "googledrive": "Google Drive", "figma": "Figma",
    ]

    /// Where something was said that is no product with a logo of its own.
    private static let plainSources: Set<String> = ["document", "meeting", "calendar", "email"]

    /// The tool a link lives in, where its host names one; subdomains count, since a workspace lives at `acme.slack.com`.
    public static func toolOf(_ link: String) -> String? {
        guard let host = URL(string: link)?.host?.lowercased() else { return nil }
        return hosts.first { host == $0.host || host.hasSuffix("." + $0.host) }?.slug
    }

    public static func toolName(_ slug: String) -> String {
        toolNames[slug] ?? slug.prefix(1).uppercased() + slug.dropFirst()
    }

    /// Whether a source is a product drawn with its logo rather than a plain place such as a meeting.
    public static func isTool(_ slug: String) -> Bool { !plainSources.contains(slug) }

    /// What a decision is, under its words: its kind once settled, and that nobody approved it while it is a candidate.
    public static func standing(_ entry: WorkspaceEntry) -> String {
        switch entry {
        case .settled(let fact): kindWord(fact.kind)
        case .unconfirmed: "Not approved by anyone"
        }
    }

    public static func kindWord(_ kind: String) -> String {
        switch WorkspaceFactKind(rawValue: kind) {
        case .decision: "Decision"
        case .policy: "Policy"
        case .authority: "Approval authority"
        case .responsibility: "Ownership"
        case .relationship: "Relationship"
        case nil: kind.prefix(1).uppercased() + kind.dropFirst()
        }
    }

    /// What the person a fact names is to it.
    public static func principalWord(_ kind: String) -> String {
        switch WorkspaceFactKind(rawValue: kind) {
        case .responsibility: "Owner"
        case .authority: "Approver"
        case .relationship: "Party"
        case .decision, .policy, nil: "Names"
        }
    }

    /// The details of one workspace record, row by row, as the console says them: what it is about, its source, who
    /// said it or confirmed it, and when.
    public static func rows(_ entry: WorkspaceEntry) -> [(String, String)] {
        switch entry {
        case .settled(let fact):
            var rows = [("Kind", kindWord(fact.kind))]
            if !fact.subject.isEmpty { rows.append(("About", fact.subject)) }
            if let principal = fact.principal { rows.append((principalWord(fact.kind), principal)) }
            if let capability = fact.capability { rows.append(("Covers", capability)) }
            if let object = fact.object { rows.append(("With", object)) }
            if let confirmed = fact.verifiedBy {
                rows.append(("Confirmed by", confirmed))
            } else if let provenance = fact.provenance {
                rows.append(("From", provenanceWord(provenance)))
            }
            if let settled = fact.settledAt { rows.append(("Settled", day(settled))) }
            if let ref = fact.sourceRef { rows.append(("Source", sourceLine(ref))) }
            if let scope = fact.scope { rows.append(("Scope", scope)) }
            return rows
        case .unconfirmed(let candidate):
            var rows = [("Standing", "Not approved by anyone, so agents weigh it as context and never as a decision")]
            if !candidate.subject.isEmpty { rows.append(("About", candidate.subject)) }
            let tools = candidate.sources.map { toolName($0.lowercased()) }
            rows.append(("Read from", tools.isEmpty ? "A connected tool" : tools.joined(separator: " and ")))
            if !candidate.saidBy.isEmpty { rows.append(("Said by", candidate.saidBy.joined(separator: ", "))) }
            if let principal = candidate.principal { rows.append((principalWord(candidate.kind), principal)) }
            if let seen = candidate.detectedAt { rows.append(("Seen", day(seen))) }
            if let ref = candidate.sourceRef { rows.append(("Source", sourceLine(ref))) }
            if candidate.untrusted { rows.append(("Trust", "Written by somebody your workspace does not know")) }
            return rows
        }
    }

    /// A link said with the tool it lives in, so the row reads as where it came from.
    public static func sourceLine(_ ref: String) -> String {
        guard let tool = toolOf(ref) else { return ref }
        return "\(toolName(tool)), \(ref)"
    }

    public static func provenanceWord(_ provenance: String) -> String {
        switch WorkspaceProvenance(rawValue: provenance) {
        case .declared: "Written down by a person"
        case .authoritative: "A system of record"
        case .observed: "Read from a conversation"
        case nil: provenance
        }
    }

    /// What the workspace side of the map says while it has nothing to draw, or nil once it does. A Mac not joined to a
    /// workspace is told how to join one; a joined one that has pulled nothing yet is told it is on its way.
    public static func emptyLine(joined: Bool?, memory: WorkspaceMemoryView?) -> String? {
        if joined == false, memory == nil {
            return "This Mac is not joined to a workspace. Sign in and join one under Account to see what your team settled beside what this Mac learned."
        }
        guard let memory else {
            return joined == true ? "Joined. Your workspace's memory arrives with this Mac's next pull." : nil
        }
        if memory.facts.isEmpty, memory.unconfirmed.isEmpty {
            return memory.withheld > 0 ? withheldLine(memory.withheld) : "Your workspace has settled nothing yet."
        }
        return nil
    }

    /// What the clearance kept back, always said, or a partial set reads as whole.
    public static func withheldLine(_ withheld: Int) -> String {
        withheld == 1 ? "1 more your workspace keeps from this Mac." : "\(withheld) more your workspace keeps from this Mac."
    }

    /// When this Mac last heard from the workspace, by the day; nil for a pull that names no time.
    public static func pulledLine(_ memory: WorkspaceMemoryView) -> String? {
        memory.syncedAt.isEmpty ? nil : "Pulled from your workspace \(day(memory.syncedAt))"
    }

    private static func day(_ stamp: String) -> String {
        String(stamp.prefix(dayLength))
    }
}
