import Foundation

/// How one press on memory ended: done at once, a rule waiting for its signature on the island, or refused.
public enum MemoryOutcome: Equatable, Sendable {
    case done(String)
    case proposed(id: String, note: String)
    case failed(String)

    /// The outcome as the line under the press says it.
    public var note: String {
        switch self {
        case .done(let note), .proposed(_, let note): note
        case .failed(let why): why
        }
    }
}

/// Where an item or a source stands, said in a word beside its tone, since a colour alone says nothing.
public enum MemoryTone: Equatable, Sendable {
    case good
    case attention
    case bad
    case quiet
}

/// What the list shows: one status, one scope or both, or what a search found.
public struct MemoryFilter: Equatable, Sendable {
    public let status: MemoryStatus
    public let scope: MemoryScope?
    /// Searched by keyword over every status when it carries words.
    public let query: String?

    public init(status: MemoryStatus = .verified, scope: MemoryScope? = nil, query: String? = nil) {
        self.status = status
        self.scope = scope
        self.query = query
    }
}

/// What a source's location is, which decides what the Add source sheet asks for.
public enum SourcePlace: Equatable, Sendable {
    case folder
    case repository
    case secret
    case server
}

/// One kind the Add source sheet offers, with what its location is.
public struct SourceKindChoice: Equatable, Sendable {
    public let kind: MemorySourceKind
    public let label: String
    public let place: SourcePlace
}

/// The Add source form as it is typed, every field a string.
public struct SourceForm: Equatable, Sendable {
    public var kind: MemorySourceKind
    public var location: String
    public var name: String
    public var scope: MemoryScope
    public var secret: String
    public var server: String
    public var tool: String

    public init(kind: MemorySourceKind, location: String = "", name: String = "", scope: MemoryScope = .personal,
                secret: String? = nil, server: String = "", tool: String = "") {
        self.kind = kind
        self.location = location
        self.name = name
        self.scope = scope
        self.secret = secret ?? (kind == .supermemory ? MemoryLines.supermemorySecret : "")
        self.server = server
        self.tool = tool
    }
}

/// Memory as a person reads it, mirrored from shared/tauri-core's memory-lines.ts so the Mac, Windows and Linux say it
/// the same way. A statement is shown as it was written, never trimmed or reworded, and a confidence is always the
/// extractor's own: only a person's confirm makes a fact verified.
public enum MemoryLines {
    /// The status chips over the list, in the order a person settles them.
    public static let filters: [(status: MemoryStatus, label: String)] = [
        (.verified, "Verified"),
        (.candidate, "Candidate"),
        (.conflicting, "Conflicting"),
        (.outdated, "Outdated"),
        (.rejected, "Rejected"),
    ]

    /// The two scopes memory keeps, as the scope switch names them.
    public static let scopes: [(scope: MemoryScope, label: String)] = [
        (.personal, "Personal"),
        (.project, "Project"),
    ]

    /// The secret a Supermemory source names unless the person names another.
    public static let supermemorySecret = "SUPERMEMORY_API_KEY"

    public static let taintedLine = "Read from an untrusted source"

    private static let statusWords: [MemoryStatus: (word: String, tone: MemoryTone)] = [
        .verified: ("Verified", .good),
        .candidate: ("Waiting to be confirmed", .attention),
        .conflicting: ("Conflicts with another fact", .bad),
        .outdated: ("Outdated", .quiet),
        .rejected: ("Rejected", .quiet),
        .superseded: ("Restated by a newer fact", .quiet),
    ]

    /// A status in words beside its tone; one this app does not know yet is shown as the runtime wrote it.
    public static func statusWord(_ status: String) -> (word: String, tone: MemoryTone) {
        MemoryStatus(rawValue: status).flatMap { statusWords[$0] } ?? (status, .quiet)
    }

    private static let kindWords: [MemoryKind: String] = [.fact: "Fact", .convention: "Convention", .rule: "Rule"]

    public static func kindWord(_ kind: String) -> String {
        MemoryKind(rawValue: kind).flatMap { kindWords[$0] } ?? kind
    }

    /// The kinds the Add source sheet offers, each with what its location is.
    public static let sourceKinds: [SourceKindChoice] = [
        SourceKindChoice(kind: .obsidian, label: "Obsidian vault", place: .folder),
        SourceKindChoice(kind: .markdown, label: "Markdown folder", place: .folder),
        SourceKindChoice(kind: .instructions, label: "Agent instruction files", place: .repository),
        SourceKindChoice(kind: .notionExport, label: "Notion export", place: .folder),
        SourceKindChoice(kind: .supermemory, label: "Supermemory", place: .secret),
        SourceKindChoice(kind: .mcp, label: "MCP memory server", place: .server),
    ]

    public static func place(_ kind: MemorySourceKind) -> SourcePlace {
        // Every kind is listed above, so the lookup always lands.
        sourceKinds.first { $0.kind == kind }!.place
    }

    public static func sourceKindLabel(_ kind: String) -> String {
        sourceKinds.first { $0.kind.rawValue == kind }?.label ?? kind
    }

    /// Trust said in words beside its tone.
    public static func trustWord(_ trust: String) -> (word: String, tone: MemoryTone) {
        if trust == SourceTrust.trusted.rawValue { return ("Trusted: your own files", .good) }
        return ("Untrusted: written outside your own files", .attention)
    }

    /// "3 verified, 2 to confirm": what a source taught, counted by where each item stands, zeros left out.
    public static func sourceCountsLine(_ counts: MemorySourceCounts) -> String {
        let parts = [
            (counts.verified, "verified"),
            (counts.candidate, "to confirm"),
            (counts.conflicting, "conflicting"),
            (counts.outdated, "outdated"),
            (counts.rejected, "rejected"),
        ].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
        return parts.isEmpty ? "Taught nothing yet" : parts.joined(separator: ", ")
    }

    /// When it was last read, and whether it is read again on its own or only when asked.
    public static func lastReadLine(_ source: MemorySourceView, now: Date) -> String {
        let read = SessionText.ago(source.lastReadAt, now: now).map { "Read \($0)" } ?? "Not read yet"
        return "\(read). \(source.watched ? "Read again when a file in it changes." : "Read when you ask.")"
    }

    /// Whether a source that needs a key can be read, never the key itself.
    public static func keyLine(_ keyHeld: Bool?) -> String? {
        guard let keyHeld else { return nil }
        return keyHeld ? "Its key is kept by this Mac." : "Its key is not set on this Mac, so it cannot be read."
    }

    /// One read, said so an empty read and a failed one are told apart.
    public static func readSummaryLine(_ summary: MemoryReadSummary) -> String {
        if let error = summary.error { return "The read failed: \(error)" }
        let found = "Read \(ProjectLines.counted(summary.documents, "document", "documents")) and "
            + ProjectLines.counted(summary.passages, "passage", "passages")
        var parts = ["\(summary.added) added", "\(summary.merged) merged into what was known"]
        if summary.droppedCitations > 0 {
            parts.append("\(ProjectLines.counted(summary.droppedCitations, "citation", "citations")) dropped for naming no passage")
        }
        if summary.rejectedBefore > 0 { parts.append("\(summary.rejectedBefore) you rejected before, not proposed again") }
        if summary.outdated > 0 { parts.append("\(summary.outdated) now outdated") }
        return "\(found): \(parts.joined(separator: ", ")). \(extractorLine(summary.extractor))"
    }

    /// Whether the person's own agent read the passages, and what to do when none could.
    public static func extractorLine(_ state: String) -> String {
        switch ExtractorState(rawValue: state) {
        case .answered: "Your agent read the new passages."
        case .unavailable:
            "No agent on this Mac could read the new passages, so they wait for the next read. Sign in to Claude Code and read again."
        case .unreadable: "Your agent answered in a shape Memnox could not read, so nothing was learned from these passages."
        case .idle, nil: "Nothing new to read."
        }
    }

    /// The extractor's own confidence, labelled as the extractor's so it never reads as a check.
    public static func confidenceLine(_ confidence: Double?) -> String? {
        guard let confidence else { return nil }
        let percent = Int((min(1, max(0, confidence)) * 100).rounded())
        return "The extractor\u{2019}s own confidence: \(percent)%"
    }

    /// Who put it in the queue: an agent through memnox_suggest, the extractor reading a source, or a person.
    public static func originLine(origin: String, suggestedBy: String?) -> String {
        if origin == MemoryOrigin.agent.rawValue {
            return "Suggested by \(suggestedBy.map(McpHubLines.agentLabel) ?? "an agent") through memnox_suggest"
        }
        if origin == MemoryOrigin.person.rawValue { return "Written by a person" }
        return "Read out of a source by your agent"
    }

    public static func originLine(_ item: MemoryItemView) -> String {
        originLine(origin: item.origin, suggestedBy: item.suggestedBy)
    }

    /// The earlier item a candidate restates, quoted whole.
    public static func duplicateLine(_ statement: String) -> String {
        "Restates \u{201C}\(statement)\u{201D}"
    }

    /// Where one piece of evidence sits, and whether it still says what it did.
    public static func evidenceLine(_ evidence: MemoryEvidenceView) -> String {
        "\(evidence.ref) in \(evidence.source)\(evidence.stale ? ", changed since it was read" : "")"
    }

    /// The whole path of a piece of evidence, from its source's folder when that source is still here.
    public static func evidencePath(_ evidence: MemoryEvidenceView, sources: [MemorySourceView]?) -> String {
        guard let source = sources?.first(where: { $0.name == evidence.source || $0.id == evidence.source }) else {
            return evidence.document
        }
        var folder = source.location
        while folder.hasSuffix("/") || folder.hasSuffix("\\") { folder.removeLast() }
        return "\(folder)/\(evidence.document)"
    }

    /// Who settled it and when, for a verified or rejected item.
    public static func decidedLine(_ item: MemoryItemView, now: Date) -> String? {
        guard let when = SessionText.ago(item.decidedAt, now: now) else { return nil }
        let verb = item.status == MemoryStatus.rejected.rawValue ? "Rejected" : "Confirmed"
        return "\(verb)\(item.decidedBy.map { " by \($0)" } ?? "") \(when)"
    }

    /// Where an item is kept, as the inspector says it.
    public static func keptLine(_ item: MemoryItemView) -> String {
        guard item.scope == MemoryScope.project.rawValue else { return "In your personal memory" }
        return "With the project\(item.project.map { " \($0)" } ?? "")"
    }

    /// "Fact · Personal · 2 pieces of evidence", the line under a row of the list.
    public static func rowCaption(_ item: MemoryItemView) -> String {
        let scope = item.scope == MemoryScope.project.rawValue ? "Project" : "Personal"
        let evidence = item.evidence.count == 1 ? "1 piece of evidence" : "\(item.evidence.count) pieces of evidence"
        return [kindWord(item.kind), scope, evidence].joined(separator: SessionText.separator)
    }

    /// The queue as Learn shows it, oldest first, so nothing waits behind what came after it.
    public static func oldestFirst(_ items: [MemoryItemView]) -> [MemoryItemView] {
        items.enumerated().sorted { a, b in
            a.element.createdAt == b.element.createdAt ? a.offset < b.offset : a.element.createdAt < b.element.createdAt
        }.map(\.element)
    }

    /// "1 thing to confirm in Learn", the row Home shows while the queue holds anything.
    public static func learnWaitingLine(_ count: Int) -> String {
        "\(ProjectLines.counted(count, "thing", "things")) to confirm in Learn"
    }

    /// A cut list never reads as whole.
    public static func moreLine(_ more: Int) -> String? {
        more > 0 ? "\(more) more not shown" : nil
    }

    /// How a search was answered, said under the box so keyword alone never passes for both.
    public static func searchModeLine(_ mode: MemorySearchMode) -> String {
        mode == .semantic ? "Searched by meaning, and by keyword" : "Searched by keyword"
    }

    /// The command that turns search by meaning on, a CLI setting rather than one this window keeps.
    public static let embeddingCommand = "memnox config set embeddingModel <model>"
    public static let meaningSearchTitle = "Search memory by meaning"
    /// What Settings says about it, the command shown after these words.
    public static let meaningSearchLine = "Memory is searched by keyword. To search it by meaning as well, with an embedding model running on this Mac such as nomic-embed-text in Ollama, run this in a terminal:"

    /// What a confirm did: a fact is verified at once, a rule waits for its signature on the island.
    public static func confirmedLine(kind: String, proposed: Bool, keyTitle: String) -> String {
        if proposed || kind == MemoryKind.rule.rawValue {
            return "The rule waits for your signature on the island. Confirm it with \(keyTitle) and it holds."
        }
        return "Confirmed. The \(kind) is verified now, and your agents are handed it."
    }

    /// What stops the form from being sent, said before it goes.
    public static func sourceFormProblem(_ form: SourceForm) -> String? {
        switch place(form.kind) {
        case .folder, .repository:
            let location = form.location.trimmingCharacters(in: .whitespacesAndNewlines)
            if location.isEmpty {
                return place(form.kind) == .repository ? "Choose the repository whose instruction files it reads." : "Choose the folder it reads."
            }
            return LaunchLines.isAbsoluteFolder(location) ? nil : "Give the whole path, from the top of the drive."
        case .secret:
            return trimmed(form.secret).isEmpty ? "Name the secret that holds the key." : nil
        case .server:
            if trimmed(form.server).isEmpty { return "Choose the hub server it reads." }
            return trimmed(form.tool).isEmpty ? "Choose the tool that reads its memory." : nil
        }
    }

    /// The form as the wire carries it: a key by its secret's name only, never its value.
    public static func sourceInput(_ form: SourceForm) -> MemorySourceInput {
        let place = place(form.kind)
        let name = trimmed(form.name)
        return MemorySourceInput(
            kind: form.kind,
            location: place == .folder || place == .repository ? trimmed(form.location) : nil,
            name: name.isEmpty ? nil : name,
            scope: form.scope,
            secret: place == .secret ? trimmed(form.secret) : nil,
            server: place == .server ? trimmed(form.server) : nil,
            tool: place == .server ? trimmed(form.tool) : nil
        )
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
