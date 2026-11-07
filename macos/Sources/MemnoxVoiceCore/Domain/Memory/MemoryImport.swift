import Foundation

/// What a kind's location may be, which decides what Finder's panel lets the person pick and what a drop takes.
public struct SourcePick: Equatable, Sendable {
    public let folders: Bool
    /// Extensions of the files it reads one by one, lowercased without the dot; empty when only a folder will do.
    public let fileExtensions: [String]
    /// Names it reads whatever their extension, such as CLAUDE.md.
    public let fileNames: [String]
    /// Takes a zip, which is unzipped beside itself before it is added.
    public let archives: Bool

    public var files: Bool { !fileExtensions.isEmpty || !fileNames.isEmpty || archives }

    /// The extensions Finder's panel lets through, a name such as .cursorrules counted by what follows its dot.
    public var panelExtensions: [String] {
        let named = fileNames.map { name -> String in
            let parts = name.split(separator: ".", omittingEmptySubsequences: true)
            return parts.last.map { $0.lowercased() } ?? name
        }
        var seen = Set<String>()
        return (fileExtensions + named + (archives ? [MemoryImport.zipExtension] : [])).filter { seen.insert($0).inserted }
    }
}

/// What a path is on this disk.
public enum PathKind: Equatable, Sendable {
    case missing
    case folder
    case file
    /// A socket, a device or anything else that is neither.
    case other
}

/// One path as the app found it on disk; the caller makes every outside read, so the rules here stay pure.
public struct PathLook: Equatable, Sendable {
    public let path: String
    public let kind: PathKind
    public let readable: Bool
    /// For a folder: the files under it its kind reads, relative to it, as far as the look went.
    public let found: [String]
    /// The look stopped at its bound, so more may be there.
    public let cut: Bool

    public init(path: String, kind: PathKind, readable: Bool = true, found: [String] = [], cut: Bool = false) {
        self.path = path
        self.kind = kind
        self.readable = readable
        self.found = found
        self.cut = cut
    }

    public var name: String { MemoryImport.lastPart(path) }
}

/// What the sheet says under the path before anything is added.
public struct ImportPreview: Equatable, Sendable {
    /// "12 Markdown files in labvanced".
    public let headline: String
    /// The first few names, so the person sees these are the notes they meant.
    public let names: [String]
    /// Found past the names shown, so a cut list never reads as whole.
    public let more: Int
    public let note: String?
}

public enum ImportCheck: Equatable, Sendable {
    /// Nothing typed or chosen yet.
    case nothing
    case problem(String)
    case ready(ImportPreview)
}

/// How one source of an import ended: its first read, or why it was not added.
public struct ImportResult: Equatable, Sendable {
    public let name: String
    public let summary: MemoryReadSummary?
    public let failure: String?

    public init(name: String, summary: MemoryReadSummary? = nil, failure: String? = nil) {
        self.name = name
        self.summary = summary
        self.failure = failure
    }
}

/// The rules of the Add source sheet's path: what may be picked, how a typed or dropped path is read, what the look on
/// disk says before adding, and how the first read is said after. Which notes count mirrors the runtime's
/// folder-sources.ts only to preview them; the runtime's own read is what counts, and it says what it passed over.
public enum MemoryImport {
    /// The extensions the runtime reads as Markdown.
    public static let markdownExtensions = ["md", "markdown", "mdc"]
    /// The files an instructions source reads at the top of a repository.
    public static let instructionNames = ["CLAUDE.md", "AGENTS.md", "GEMINI.md", ".cursorrules"]
    /// The folder of Cursor's rules inside a repository.
    public static let cursorRules = ".cursor/rules"
    /// Folders a walk never enters, as the runtime skips them.
    public static let skippedFolders: Set<String> = ["node_modules"]
    public static let zipExtension = "zip"
    /// Names shown under the headline, enough to recognise the notes without a scroll.
    public static let shownNames = 5

    public static func pick(_ kind: MemorySourceKind) -> SourcePick {
        switch kind {
        case .obsidian: SourcePick(folders: true, fileExtensions: [], fileNames: [], archives: false)
        case .markdown: SourcePick(folders: true, fileExtensions: markdownExtensions, fileNames: [], archives: false)
        case .instructions: SourcePick(folders: true, fileExtensions: ["mdc"], fileNames: instructionNames, archives: false)
        case .notionExport: SourcePick(folders: true, fileExtensions: markdownExtensions, fileNames: [], archives: true)
        case .supermemory, .mcp: SourcePick(folders: false, fileExtensions: [], fileNames: [], archives: false)
        }
    }

    /// The words over the path field, saying what it takes.
    public static func fieldLabel(_ kind: MemorySourceKind) -> String {
        switch kind {
        case .obsidian: "The vault folder, from the top of the drive"
        case .markdown: "The notes or the folder, from the top of the drive"
        case .instructions: "The repository, or its CLAUDE.md or AGENTS.md"
        case .notionExport: "The export, as its zip or the folder it unzipped into"
        case .supermemory, .mcp: "Where it is read from"
        }
    }

    public static func placeholder(_ kind: MemorySourceKind) -> String {
        switch kind {
        case .instructions: "/Users/you/code/project"
        case .notionExport: "/Users/you/Downloads/Export.zip"
        case .obsidian, .markdown, .supermemory, .mcp: "/Users/you/notes"
        }
    }

    /// What Finder's panel says over its list, so the person knows a file may be picked as well as a folder.
    public static func panelMessage(_ kind: MemorySourceKind) -> String {
        switch kind {
        case .obsidian: "Choose the folder of your Obsidian vault."
        case .markdown: "Choose Markdown files, or a folder of them. Hold Command to choose several."
        case .instructions: "Choose a repository, or its CLAUDE.md, AGENTS.md, GEMINI.md or a Cursor rule."
        case .notionExport: "Choose the zip Notion sent, or the folder it unzipped into."
        case .supermemory, .mcp: ""
        }
    }

    /// Whether a file of this name is one the kind reads when picked on its own.
    public static func reads(file name: String, kind: MemorySourceKind) -> Bool {
        let pick = pick(kind)
        let base = lastPart(name)
        return pick.fileNames.contains(base) || pick.fileExtensions.contains(fileExtension(base))
    }

    public static func isZip(_ path: String) -> Bool { fileExtension(path) == zipExtension }

    /// Whether a file found under a folder is one the walk reads: Markdown, never under a dot folder or node_modules.
    public static func counts(relativePath: String, kind: MemorySourceKind) -> Bool {
        let parts = relativePath.split(separator: "/").map(String.init)
        guard let last = parts.last else { return false }
        if kind == .instructions {
            if parts.count == 1 { return instructionNames.contains(last) }
            return parts.dropLast().joined(separator: "/") == cursorRules && markdownExtensions.contains(fileExtension(last))
        }
        if parts.contains(where: { $0.hasPrefix(".") || skippedFolders.contains($0) }) { return false }
        return markdownExtensions.contains(fileExtension(last))
    }

    /// The paths in what was typed, pasted or dropped: one a line, quotes and a file link undone, `~` as home.
    public static func paths(_ text: String, home: String) -> [String] {
        var seen = Set<String>()
        return text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            var path = line.trimmingCharacters(in: .whitespaces)
            for quote in ["\"", "'"] where path.count > 1 && path.hasPrefix(quote) && path.hasSuffix(quote) {
                path = String(path.dropFirst().dropLast())
            }
            if path.hasPrefix("file://"), let url = URL(string: path), url.isFileURL { path = url.path }
            if path == "~" || path.hasPrefix("~/") { path = home + path.dropFirst() }
            // A trailing slash names the same folder, so the runtime is sent one spelling of it.
            while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
            guard !path.isEmpty, seen.insert(path).inserted else { return nil }
            return path
        }
    }

    /// The paths again as the field holds them, one a line.
    public static func field(_ paths: [String]) -> String { paths.joined(separator: "\n") }

    /// What stops a path from being added, or what will be read from it.
    public static func check(_ looks: [PathLook], kind: MemorySourceKind) -> ImportCheck {
        guard !looks.isEmpty else { return .nothing }
        for look in looks {
            if let problem = problem(look, kind: kind) { return .problem(problem) }
        }
        return .ready(preview(looks, kind: kind))
    }

    private static func problem(_ look: PathLook, kind: MemorySourceKind) -> String? {
        guard LaunchLines.isAbsoluteFolder(look.path) else { return "Give the whole path, from the top of the drive." }
        switch look.kind {
        case .missing: return "\(look.path) is not on this Mac."
        case .other: return "\(look.name) is neither a folder nor a file."
        case .folder, .file: break
        }
        guard look.readable else {
            return "Memnox cannot open \(look.name). Pick it with Choose, so macOS lets Memnox read it."
        }
        let pick = pick(kind)
        if look.kind == .folder {
            if look.found.isEmpty { return kind == .instructions ? noInstructions(look.name) : "No Markdown files in \(look.name)." }
            return nil
        }
        if !pick.files { return "An Obsidian vault is a folder: choose the vault rather than one note." }
        if pick.archives, isZip(look.path) { return nil }
        if reads(file: look.path, kind: kind) { return nil }
        if kind == .instructions { return "\(look.name) is not an instruction file. Choose CLAUDE.md, AGENTS.md, GEMINI.md, a Cursor rule, or the repository." }
        return "\(look.name) is not Markdown. Choose a .md or .markdown file, or a folder."
    }

    private static func noInstructions(_ name: String) -> String {
        "No CLAUDE.md, AGENTS.md, GEMINI.md or Cursor rules in \(name)."
    }

    private static func preview(_ looks: [PathLook], kind: MemorySourceKind) -> ImportPreview {
        let noun = kind == .instructions ? ("instruction file", "instruction files") : ("Markdown file", "Markdown files")
        let several = looks.count > 1 ? "Each is added as its own source, and read now." : nil
        if looks.count == 1, let look = looks.first, look.kind == .folder {
            let count = ProjectLines.counted(look.found.count, noun.0, noun.1)
            return ImportPreview(headline: "\(look.cut ? "At least " : "")\(count) in \(look.name)",
                                 names: Array(look.found.prefix(shownNames)),
                                 more: max(0, look.found.count - shownNames),
                                 note: kind == .notionExport ? notionNote : nil)
        }
        if looks.count == 1, let look = looks.first, isZip(look.path) {
            return ImportPreview(headline: "A Notion export zip, \(look.name)", names: [], more: 0,
                                 note: "It is unzipped into a folder beside it, and that folder is read. \(notionNote)")
        }
        let files = looks.filter { $0.kind == .file }.count
        let folders = looks.count - files
        var parts: [String] = []
        if files > 0 { parts.append(ProjectLines.counted(files, noun.0, noun.1)) }
        if folders > 0 { parts.append(ProjectLines.counted(folders, "folder", "folders")) }
        let names = looks.map(\.name)
        return ImportPreview(headline: "\(parts.joined(separator: " and ")) chosen", names: Array(names.prefix(shownNames)),
                             more: max(0, names.count - shownNames), note: several)
    }

    private static let notionNote = "A third party wrote it, so it is read as untrusted."

    /// The sources the runtime lists now that it did not before, which an add just made.
    public static func added(before: [String], after: [MemorySourceView]) -> [MemorySourceView] {
        let known = Set(before)
        return after.filter { !known.contains($0.id) }
    }

    /// One source per path, the name kept only when a single path is added, since one name cannot fit several.
    public static func inputs(_ form: SourceForm, home: String) -> [MemorySourceInput] {
        let paths = paths(form.location, home: home)
        guard paths.count > 1 else {
            var single = form
            single.location = paths.first ?? form.location
            return [MemoryLines.sourceInput(single)]
        }
        return paths.map { path in
            var each = form
            each.location = path
            each.name = ""
            return MemoryLines.sourceInput(each)
        }
    }

    /// What a read passed over, said by reason, or nil when it read everything it holds.
    public static func skippedLine(_ skipped: [MemorySkippedDocument]?) -> String? {
        guard let skipped, !skipped.isEmpty else { return nil }
        var parts: [String] = []
        let large = skipped.filter { $0.skipReason == .tooLarge }.map(\.document)
        if !large.isEmpty { parts.append("\(ProjectLines.counted(large.count, "file", "files")) too large to be notes (\(listed(large)))") }
        let unreadable = skipped.filter { $0.skipReason == .unreadable }.map(\.document)
        if !unreadable.isEmpty { parts.append("\(ProjectLines.counted(unreadable.count, "file", "files")) that could not be opened (\(listed(unreadable)))") }
        let other = skipped.filter { $0.skipReason == nil }.count
        if other > 0 { parts.append(ProjectLines.counted(other, "file", "files") + " for a reason this app does not know yet") }
        var line = parts.isEmpty ? "" : "Passed over \(parts.joined(separator: " and "))."
        if skipped.contains(where: { $0.skipReason == .pastLimit }) {
            line += (line.isEmpty ? "" : " ") + "Stopped at the most notes one source reads, so the rest were not read."
        }
        return line
    }

    /// The result of one source's first read as the sheet says it.
    public static func resultLine(_ result: ImportResult) -> String {
        if let failure = result.failure { return "\(result.name) was not added: \(failure)" }
        guard let summary = result.summary else { return "\(result.name) was added. Memnox is reading it now." }
        return MemoryLines.readSummaryLine(summary)
    }

    /// Said while the first read runs, since the person's agent can take a minute over many notes.
    public static func readingLine(_ name: String, step: Int, of total: Int) -> String {
        let place = total > 1 ? " (\(step) of \(total))" : ""
        return "Your agent is reading \(name)\(place). This can take a minute, and closing this keeps it reading."
    }

    private static func listed(_ documents: [String]) -> String {
        let shown = documents.prefix(shownNames).joined(separator: ", ")
        let more = documents.count - shownNames
        return more > 0 ? "\(shown) and \(more) more" : shown
    }

    public static func lastPart(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    private static func fileExtension(_ name: String) -> String {
        let base = lastPart(name)
        guard let dot = base.lastIndex(of: "."), dot != base.startIndex else { return "" }
        return base[base.index(after: dot)...].lowercased()
    }
}
