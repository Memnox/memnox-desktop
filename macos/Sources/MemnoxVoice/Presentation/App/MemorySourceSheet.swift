import AppKit
import MemnoxVoiceCore
import SwiftUI

private enum SourceSheetLayout {
    static let width: CGFloat = 560
    static let minHeight: CGFloat = 420
}

/// Adds one place memory is read from. A key is never part of the form: it is named here, and set once through the
/// MCP Hub's secret store, so the source keeps only the name of the secret.
struct AddMemorySourceSheet: View {
    @ObservedObject var screen: MemoryScreen
    let hub: McpHubScreen?
    let close: () -> Void
    @State private var form = SourceForm(kind: .obsidian)
    @State private var problem: String?

    var body: some View {
        let place = MemoryLines.place(form.kind)
        let adding = screen.memory.busy == Memory.adding
        VStack(spacing: 0) {
            Text("Add a memory source")
                .font(Memnox.sans(Memnox.TextSize.headline, .semibold))
                .foregroundStyle(Memnox.Palette.foreground)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Memnox.Spacing.xxLarge)
                .frame(height: ShellMetrics.barHeight)
            ShellDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: Memnox.Spacing.xLarge) {
                    kinds
                    switch place {
                    case .folder, .repository: FolderField(form: $form, place: place)
                    case .secret:
                        if let hub {
                            SupermemoryKey(hub: hub, secret: $form.secret)
                        } else {
                            labelled("The name of the secret that holds the key") {
                                TextField("", text: $form.secret).kitField().font(Memnox.mono(Memnox.TextSize.footnote))
                            }
                        }
                    case .server:
                        if let hub { HubServerPick(hub: hub, form: $form) } else { MemoryQuiet("Reading the MCP Hub.") }
                    }
                    labelled("Name it, or leave it to be named for you") {
                        TextField("Team notes", text: $form.name).kitField()
                    }
                    labelled("Keep what it teaches") {
                        Picker("Keep what it teaches", selection: $form.scope) {
                            Text("In my personal memory").tag(MemoryScope.personal)
                            Text("With the project").tag(MemoryScope.project)
                        }
                        .labelsHidden()
                    }
                    if let problem { MemoryQuiet(problem, tint: Memnox.Palette.destructive) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Memnox.Spacing.xxLarge)
            }
            ShellDivider()
            HStack(spacing: Memnox.Spacing.medium) {
                MemoryQuiet("Your own agent reads it. Nothing it finds counts until you confirm it in Learn.")
                Spacer(minLength: Memnox.Spacing.medium)
                Button("Cancel", action: close).buttonStyle(KitButton(kind: .secondary)).keyboardShortcut(.cancelAction)
                Button(adding ? "Adding" : "Add", action: send)
                    .buttonStyle(KitButton(kind: .primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(adding)
            }
            .padding(.horizontal, Memnox.Spacing.xxLarge)
            .padding(.vertical, Memnox.Spacing.large)
        }
        .frame(width: SourceSheetLayout.width)
        .frame(minHeight: SourceSheetLayout.minHeight)
        .background(Memnox.Palette.background)
        .buttonStyle(QuietButton())
        .task(id: place) {
            if place == .server, let hub, hub.hub.hub == nil { await hub.hub.refresh() }
        }
    }

    private var kinds: some View {
        // Two rows of three, so the six kinds fit the sheet's width.
        Grid(alignment: .leading, horizontalSpacing: Memnox.Spacing.small, verticalSpacing: Memnox.Spacing.small) {
            ForEach([0, 3], id: \.self) { start in
                GridRow {
                    ForEach(MemoryLines.sourceKinds[start..<start + 3], id: \.kind) { each in
                        MemoryChip(title: each.label, on: form.kind == each.kind) {
                            form = SourceForm(kind: each.kind, name: form.name, scope: form.scope)
                            problem = nil
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Kind of source")
    }

    private func send() {
        problem = MemoryLines.sourceFormProblem(form)
        guard problem == nil else { return }
        let input = MemoryLines.sourceInput(form)
        Task {
            let outcome = await screen.memory.addSource(input)
            if case .failed(let why) = outcome {
                problem = why
                return
            }
            screen.note = outcome.note
            close()
        }
    }
}

/// A label over the field it names, as every form in the window has it.
private func labelled<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
        Text(label)
            .font(Memnox.sans(Memnox.TextSize.footnote, .medium))
            .foregroundStyle(Memnox.Palette.muted)
        content()
    }
}

/// The folder or repository to read, typed whole or chosen in Finder's own panel.
private struct FolderField: View {
    @Binding var form: SourceForm
    let place: SourcePlace

    var body: some View {
        labelled(place == .repository ? "The repository, from the top of the drive" : "The folder, from the top of the drive") {
            HStack(spacing: Memnox.Spacing.medium) {
                TextField(place == .repository ? "/Users/you/code/project" : "/Users/you/notes", text: $form.location)
                    .kitField()
                    .font(Memnox.mono(Memnox.TextSize.footnote))
                Button("Choose", systemImage: "folder", action: choose)
                    .buttonStyle(KitButton(kind: .secondary))
                    .help("Pick the folder in Finder")
            }
            if place == .repository { MemoryQuiet("Reads CLAUDE.md, AGENTS.md, GEMINI.md and .cursor/rules in it.") }
            if form.kind == .notionExport {
                MemoryQuiet("The folder a Notion export unzipped into. A third party wrote it, so it is read as untrusted.")
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Read this folder"
        if !form.location.isEmpty { panel.directoryURL = URL(fileURLWithPath: form.location) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        form.location = url.path
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
            TextField("", text: $secret).kitField().font(Memnox.mono(Memnox.TextSize.footnote))
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
                Picker("The hub server", selection: Binding(get: { form.server }, set: { name in
                    form.server = name
                    form.tool = ""
                })) {
                    Text("Choose a server").tag("")
                    ForEach(servers) { each in Text(each.name).tag(each.name) }
                }
                .labelsHidden()
            }
            if server != nil {
                labelled("The tool that reads its memory") {
                    if tools.isEmpty {
                        TextField("search_memory", text: $form.tool).kitField().font(Memnox.mono(Memnox.TextSize.footnote))
                    } else {
                        Picker("The tool that reads its memory", selection: $form.tool) {
                            Text("Choose a tool").tag("")
                            ForEach(tools, id: \.name) { each in Text(each.name).tag(each.name) }
                        }
                        .labelsHidden()
                    }
                }
            }
            MemoryQuiet("A server outside your own files is read as untrusted.")
        }
    }
}
