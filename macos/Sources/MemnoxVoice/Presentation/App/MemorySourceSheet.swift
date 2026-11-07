import AppKit
import MemnoxVoiceCore
import SwiftUI
import UniformTypeIdentifiers

private enum SourceSheetLayout {
    static let width: CGFloat = 560
    static let minHeight: CGFloat = 420
    /// The most lines the path field grows to before it scrolls, enough to see a few chosen files.
    static let pathLines = 4
    /// A pause after typing before the disk is looked at, so a path is not walked at every key.
    static let lookDelay: Duration = .milliseconds(300)
    static let dropWash = 0.08
}

/// Where the sheet is: the form, a source being added and read, or what the reads came to.
private enum SheetStage: Equatable {
    case form
    case working(String)
    case finished([ImportResult])
}

/// What the look on disk was made for, so a newer path or kind starts a fresh one.
private struct LookKey: Hashable {
    let kind: MemorySourceKind
    let location: String
}

/// Adds one place memory is read from. A key is never part of the form: it is named here, and set once through the
/// MCP Hub's secret store, so the source keeps only the name of the secret. A file source may be folders or files,
/// picked, dropped or typed, and the sheet shows what will be read before it adds and what was read after.
struct AddMemorySourceSheet: View {
    @ObservedObject var screen: MemoryScreen
    let hub: McpHubScreen?
    let close: () -> Void
    @State private var form = SourceForm(kind: .obsidian)
    @State private var problem: String?
    @State private var check = ImportCheck.nothing
    @State private var stage = SheetStage.form

    var body: some View {
        VStack(spacing: 0) {
            Text("Add a memory source")
                .font(Memnox.Console.sans(Memnox.Console.TextSize.large, .semibold))
                .foregroundStyle(Memnox.Console.foreground)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Memnox.Spacing.xxLarge)
                .frame(height: ShellMetrics.barHeight)
            ShellDivider()
            ScrollView {
                Group {
                    switch stage {
                    case .form: fields
                    case .working(let line): ImportWorking(line: line)
                    case .finished(let results): ImportFinished(results: results)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Memnox.Spacing.xxLarge)
            }
            ShellDivider()
            footer
                .padding(.horizontal, Memnox.Spacing.xxLarge)
                .padding(.vertical, Memnox.Spacing.large)
        }
        .frame(width: SourceSheetLayout.width)
        .frame(minHeight: SourceSheetLayout.minHeight)
        .background(Memnox.Console.card)
        .buttonStyle(QuietButton())
        .task(id: MemoryLines.place(form.kind)) {
            if MemoryLines.place(form.kind) == .server, let hub, hub.hub.hub == nil { await hub.hub.refresh() }
        }
        .task(id: LookKey(kind: form.kind, location: form.location)) { await look() }
    }

    private var fields: some View {
        let place = MemoryLines.place(form.kind)
        return VStack(alignment: .leading, spacing: Memnox.Spacing.xLarge) {
            kinds
            switch place {
            case .folder, .repository: PathField(form: $form, check: check)
            case .secret:
                if let hub {
                    SupermemoryKey(hub: hub, secret: $form.secret)
                } else {
                    labelled("The name of the secret that holds the key") {
                        TextField("", text: $form.secret).kitField().font(Memnox.Console.code(Memnox.TextSize.footnote))
                    }
                }
            case .server:
                if let hub { HubServerPick(hub: hub, form: $form) } else { MemoryQuiet("Reading the MCP Hub.") }
            }
            labelled("Name it, or leave it to be named for you") {
                TextField("Team notes", text: $form.name).kitField()
            }
            labelled("Keep what it teaches") {
                ConsoleSelect(label: "Keep what it teaches", selection: $form.scope, options: [
                    SelectOption(value: MemoryScope.personal, title: "In my personal memory"),
                    SelectOption(value: MemoryScope.project, title: "With the project"),
                ])
            }
            if let problem { MemoryQuiet(problem, tint: Memnox.Console.destructive) }
        }
    }

    @ViewBuilder private var footer: some View {
        HStack(spacing: Memnox.Spacing.medium) {
            switch stage {
            case .form:
                MemoryQuiet("Your own agent reads it. Nothing it finds counts until you confirm it in Learn.")
                Spacer(minLength: Memnox.Spacing.medium)
                Button("Cancel", action: close).buttonStyle(KitButton(kind: .secondary)).keyboardShortcut(.cancelAction)
                Button("Add", action: send)
                    .buttonStyle(KitButton(kind: .primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(blocked)
            case .working:
                MemoryQuiet("The new source is in the list already.")
                Spacer(minLength: Memnox.Spacing.medium)
                Button("Close", action: close).buttonStyle(KitButton(kind: .secondary)).keyboardShortcut(.cancelAction)
            case .finished:
                Spacer(minLength: Memnox.Spacing.medium)
                Button("Add another") {
                    form = SourceForm(kind: form.kind, scope: form.scope)
                    problem = nil
                    stage = .form
                }
                .buttonStyle(KitButton(kind: .secondary))
                Button("Done", action: close).buttonStyle(KitButton(kind: .primary)).keyboardShortcut(.defaultAction)
            }
        }
    }

    /// A path the look found wrong keeps Add from sending what the runtime would refuse.
    private var blocked: Bool {
        guard isFiles else { return false }
        if case .problem = check { return true }
        return false
    }

    private var isFiles: Bool {
        switch MemoryLines.place(form.kind) {
        case .folder, .repository: true
        case .secret, .server: false
        }
    }

    private var kinds: some View {
        // Two rows of three, so the six kinds fit the sheet's width.
        Grid(alignment: .leading, horizontalSpacing: Memnox.Spacing.small, verticalSpacing: Memnox.Spacing.small) {
            ForEach([0, 3], id: \.self) { start in
                GridRow {
                    ForEach(MemoryLines.sourceKinds[start..<start + 3], id: \.kind) { each in
                        MemoryChip(title: each.label, on: form.kind == each.kind) {
                            // A path stays when the next kind reads files too, so a wrong first chip costs nothing.
                            let keep = isFiles && each.place != .secret && each.place != .server
                            form = SourceForm(kind: each.kind, location: keep ? form.location : "", name: form.name, scope: form.scope)
                            problem = nil
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Kind of source")
    }

    private func look() async {
        guard isFiles else {
            check = .nothing
            return
        }
        let paths = MemoryImport.paths(form.location, home: NSHomeDirectory())
        guard !paths.isEmpty else {
            check = .nothing
            return
        }
        do { try await Task.sleep(for: SourceSheetLayout.lookDelay) } catch { return }
        let looks = await MemorySourceDisk.look(paths, kind: form.kind)
        guard !Task.isCancelled else { return }
        check = MemoryImport.check(looks, kind: form.kind)
    }

    private func send() {
        problem = MemoryLines.sourceFormProblem(form)
        guard problem == nil else { return }
        if isFiles, case .problem(let why) = check {
            problem = why
            return
        }
        let sent = form
        Task { await add(sent) }
    }

    private func add(_ sent: SourceForm) async {
        var sent = sent
        let paths = MemoryImport.paths(sent.location, home: NSHomeDirectory())
        if isFiles, paths.contains(where: MemoryImport.isZip) {
            stage = .working("Unzipping the Notion export.")
            var unzipped: [String] = []
            for path in paths {
                guard MemoryImport.isZip(path) else {
                    unzipped.append(path)
                    continue
                }
                switch await MemorySourceDisk.unzip(path) {
                case .success(let folder): unzipped.append(folder)
                case .failure(let failure):
                    stage = .form
                    problem = failure.reason
                    return
                }
            }
            sent.location = MemoryImport.field(unzipped)
        }
        let inputs = MemoryImport.inputs(sent, home: NSHomeDirectory())
        var results: [ImportResult] = []
        for (index, input) in inputs.enumerated() {
            let label = input.name ?? input.location.map(MemoryImport.lastPart) ?? MemoryLines.sourceKindLabel(input.kind)
            stage = .working("Adding \(label).")
            let before = (screen.memory.sources ?? []).map(\.id)
            let outcome = await screen.memory.addSource(input)
            if case .failed(let why) = outcome {
                // A single source refused goes back to its form, where the person can fix the path.
                if inputs.count == 1 {
                    stage = .form
                    problem = why
                    return
                }
                results.append(ImportResult(name: label, failure: why))
                continue
            }
            guard let added = MemoryImport.added(before: before, after: screen.memory.sources ?? []).first else {
                results.append(ImportResult(name: label))
                continue
            }
            stage = .working(MemoryImport.readingLine(added.name, step: index + 1, of: inputs.count))
            let read = await screen.memory.readNow(added.id)
            let summary = screen.memory.lastRead(added.id)
            if summary == nil, case .failed(let why) = read {
                results.append(ImportResult(name: added.name, failure: why))
            } else {
                results.append(ImportResult(name: added.name, summary: summary))
            }
        }
        screen.note = "Added. What your agent found waits in Learn."
        stage = .finished(results)
    }
}

/// A label over the field it names, as every form in the window has it.
private func labelled<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
        Text(label)
            .font(Memnox.Console.sans(Memnox.TextSize.footnote, .medium))
            .foregroundStyle(Memnox.Console.muted)
        content()
    }
}

/// The folders or files to read: typed or pasted whole, one a line, dropped from Finder, or chosen in Finder's panel,
/// with what the look on disk found said under it.
private struct PathField: View {
    @Binding var form: SourceForm
    let check: ImportCheck
    @State private var dropping = false

    var body: some View {
        labelled(MemoryImport.fieldLabel(form.kind)) {
            HStack(alignment: .top, spacing: Memnox.Spacing.medium) {
                TextField(MemoryImport.placeholder(form.kind), text: $form.location, axis: .vertical)
                    .lineLimit(1...SourceSheetLayout.pathLines)
                    .kitField()
                    .font(Memnox.Console.code(Memnox.TextSize.footnote))
                    .accessibilityLabel(MemoryImport.fieldLabel(form.kind))
                Button("Choose", systemImage: "folder", action: choose)
                    .buttonStyle(KitButton(kind: .secondary))
                    .help(MemoryImport.panelMessage(form.kind))
            }
            .padding(dropping ? Memnox.Spacing.xSmall : 0)
            .background(dropping ? Memnox.Console.primary.opacity(SourceSheetLayout.dropWash) : Color.clear,
                        in: RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous))
            .dropDestination(for: URL.self) { urls, _ in
                let paths = urls.filter(\.isFileURL).map(\.path)
                guard !paths.isEmpty else { return false }
                form.location = MemoryImport.field(paths)
                return true
            } isTargeted: { dropping = $0 }
            MemoryQuiet("Drop files or a folder here, or paste a path, one a line.")
            ImportCheckView(check: check)
            if form.kind == .instructions, case .nothing = check {
                MemoryQuiet("Reads CLAUDE.md, AGENTS.md, GEMINI.md and .cursor/rules in it.")
            }
            if form.kind == .notionExport, case .nothing = check {
                MemoryQuiet("The zip Notion sent, or the folder it unzipped into. A third party wrote it, so it is read as untrusted.")
            }
        }
    }

    private func choose() {
        let pick = MemoryImport.pick(form.kind)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = pick.folders
        panel.canChooseFiles = pick.files
        panel.allowsMultipleSelection = true
        panel.message = MemoryImport.panelMessage(form.kind)
        panel.prompt = "Choose"
        if pick.files {
            panel.allowedContentTypes = pick.panelExtensions.compactMap { UTType(filenameExtension: $0) } + [.folder]
        }
        let current = MemoryImport.paths(form.location, home: NSHomeDirectory())
        if let first = current.first {
            panel.directoryURL = URL(fileURLWithPath: first).deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        form.location = MemoryImport.field(panel.urls.map(\.path))
    }
}

/// What the look on disk found: why the path will not do, or what will be read from it.
private struct ImportCheckView: View {
    let check: ImportCheck

    var body: some View {
        switch check {
        case .nothing: EmptyView()
        case .problem(let why):
            Label(why, systemImage: "exclamationmark.circle")
                .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.Console.destructive)
                .fixedSize(horizontal: false, vertical: true)
        case .ready(let preview):
            let shape = RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous)
            VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
                Label(preview.headline, systemImage: "doc.text")
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                    .foregroundStyle(Memnox.Console.foreground)
                ForEach(preview.names, id: \.self) { name in
                    Text(name)
                        .font(Memnox.Console.code(Memnox.Console.TextSize.meta))
                        .foregroundStyle(Memnox.Console.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let more = MemoryLines.moreLine(preview.more) { MemoryQuiet(more) }
                if let note = preview.note { MemoryQuiet(note) }
            }
            .padding(Memnox.Spacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Memnox.Console.background, in: shape)
            .overlay(shape.strokeBorder(Memnox.Console.border, lineWidth: Memnox.Stroke.hairline))
            .accessibilityElement(children: .combine)
        }
    }
}

/// A source being added and read, said while the person's agent works.
private struct ImportWorking: View {
    let line: String

    var body: some View {
        HStack(alignment: .top, spacing: Memnox.Spacing.large) {
            ProgressView().controlSize(.small)
            Text(line)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
                .foregroundStyle(Memnox.Console.foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// What each first read came to: what was read, what it passed over and why, or why a source was not added.
private struct ImportFinished: View {
    let results: [ImportResult]

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xLarge) {
            ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                let failed = result.failure != nil || result.summary?.error != nil
                VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
                    HStack(spacing: Memnox.Spacing.medium) {
                        Text(result.name)
                            .font(Memnox.Console.sans(Memnox.TextSize.body, .semibold))
                            .foregroundStyle(Memnox.Console.foreground)
                            .lineLimit(1)
                        Spacer(minLength: Memnox.Spacing.small)
                        StatusWord(failed ? .bad : .good, failed ? "Not read" : "Read")
                    }
                    MemoryQuiet(MemoryImport.resultLine(result), tint: failed ? Memnox.Console.destructive : Memnox.Console.foreground)
                    if let skipped = MemoryImport.skippedLine(result.summary?.skipped) {
                        MemoryQuiet(skipped, tint: Memnox.Console.warm)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            MemoryQuiet("What your agent found waits in Learn, where you confirm it. Each source is read again when a file in it changes.")
        }
    }
}


/// The secret's name goes with the source; the key itself goes once into the hub's store and is cleared here.
private struct SupermemoryKey: View {
    @ObservedObject var hub: McpHubScreen
    @Binding var secret: String
    @State private var key = ""
    @State private var note: String?

    var body: some View {
        labelled("The name of the secret that holds the key") {
            TextField("", text: $secret).kitField().font(Memnox.Console.code(Memnox.TextSize.footnote))
        }
        labelled("Set the key") {
            HStack(spacing: Memnox.Spacing.medium) {
                SecureField("Paste the Supermemory key", text: $key)
                    .kitField()
                    .accessibilityLabel("Set the key")
                Button("Set the key", systemImage: "key", action: save)
                    .buttonStyle(KitButton(kind: .secondary))
                    .disabled(key.isEmpty || name.isEmpty || hub.hub.busy == name)
            }
            MemoryQuiet(note ?? "Kept by this Mac\u{2019}s own store with the MCP Hub\u{2019}s secrets. The source keeps only its name, and it is read as untrusted.")
        }
    }

    private var name: String { secret.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        guard !name.isEmpty, !key.isEmpty else { return }
        let name = self.name, value = key
        // The key leaves this view at once and nothing here keeps a copy.
        key = ""
        Task {
            switch await hub.hub.setSecret(name, value: value) {
            case .failed(let why): note = why
            case .proposed: note = "Waiting for your signature on the island before the key is kept."
            case .done: note = "\(name) is kept by this Mac now."
            }
        }
    }
}

/// A server from the hub and the tool that reads its memory, typed when the hub has not listed its tools.
private struct HubServerPick: View {
    @ObservedObject var hub: McpHubScreen
    @Binding var form: SourceForm

    var body: some View {
        let view = hub.hub.hub
        let servers = view?.servers ?? []
        if view == nil, hub.hub.unreadable {
            ReadFailed(what: "the MCP Hub") { Task { await hub.hub.refresh() } }
        } else if servers.isEmpty {
            MemoryQuiet(view == nil ? "Reading the MCP Hub." : "The MCP Hub on this Mac has no servers yet. Add the memory server there first.")
        } else {
            let server = servers.first { $0.name == form.server }
            let tools = server?.tools ?? []
            labelled("The hub server") {
                ConsoleSelect(label: "The hub server", selection: Binding(get: { form.server }, set: { name in
                    form.server = name
                    form.tool = ""
                }), options: [SelectOption(value: "", title: "Choose a server")] + servers.map { SelectOption(value: $0.name, title: $0.name) })
            }
            if server != nil {
                labelled("The tool that reads its memory") {
                    if tools.isEmpty {
                        TextField("search_memory", text: $form.tool).kitField().font(Memnox.Console.code(Memnox.TextSize.footnote))
                    } else {
                        ConsoleSelect(label: "The tool that reads its memory", selection: $form.tool,
                                      options: [SelectOption(value: "", title: "Choose a tool")] + tools.map { SelectOption(value: $0.name, title: $0.name) })
                    }
                }
            }
            MemoryQuiet("A server outside your own files is read as untrusted.")
        }
    }
}
