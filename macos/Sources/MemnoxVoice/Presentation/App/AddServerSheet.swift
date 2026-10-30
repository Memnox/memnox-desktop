import Foundation
import MemnoxVoiceCore
import SwiftUI

/// Adding a server in three short steps, with no JSON unless asked for. A variable marked secret goes to this
/// computer's own store and the server is written with only its name, so no agent's config holds it. A remote server's
/// header kept as a secret goes the same way, sent as `memnox-secret:<name>` for the proxy to fill in.
struct AddServerSheet: View {
    @ObservedObject var screen: McpHubScreen
    let agents: [String]
    let close: () -> Void

    private struct Header: Identifiable {
        let id = UUID()
        var row = HeaderRow()
    }

    private struct Variable: Identifiable {
        let id = UUID()
        var name = ""
        var value = ""
        var secret = true
    }

    /// The server as it would be written, or what keeps it from being written.
    private enum Draft {
        case server(HubServer)
        case problem(String)
    }

    private static let steps = ["Server", "Variables", "Agents"]
    private static let width: CGFloat = 560
    private static let variableName: CGFloat = 180
    private static let preview: CGFloat = 190
    private static let logo: CGFloat = 20
    private static let minHeight: CGFloat = 420
    private static let removeSide: CGFloat = 26

    @State private var step = 0
    @State private var name = ""
    @State private var about = ""
    @State private var remote = false
    @State private var launch = ""
    @State private var url = ""
    @State private var variables: [Variable] = []
    @State private var headers: [Header] = []
    @State private var given: Set<String> = []
    @State private var advanced = false
    @State private var problem: String?
    @State private var working = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ShellDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: Memnox.Spacing.xLarge) {
                    switch step {
                    case 0: serverStep
                    case 1: variablesStep
                    default: agentsStep
                    }
                    if let problem {
                        Text(problem)
                            .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                            .foregroundStyle(Memnox.Console.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Memnox.Spacing.xxLarge)
            }
            ShellDivider()
            footer
        }
        .frame(width: Self.width)
        .frame(minHeight: Self.minHeight)
        .background(Memnox.Console.background)
        .buttonStyle(QuietButton())
    }

    private var header: some View {
        HStack(spacing: Memnox.Spacing.large) {
            Text("Add a server")
                .font(Memnox.Console.sans(Memnox.TextSize.headline, .semibold))
                .foregroundStyle(Memnox.Console.foreground)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Memnox.Spacing.medium)
            Text("\(Self.steps[step]) \u{00B7} step \(step + 1) of \(Self.steps.count)")
                .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.Console.muted)
        }
        .padding(.horizontal, Memnox.Spacing.xxLarge)
        .frame(height: ShellMetrics.barHeight)
    }

    private var footer: some View {
        HStack(spacing: Memnox.Spacing.medium) {
            Button("Cancel", action: close).buttonStyle(KitButton(kind: .secondary)).keyboardShortcut(.cancelAction)
            if step > 0 {
                Button("Back") { step -= 1 }.buttonStyle(KitButton(kind: .secondary))
            }
            Spacer(minLength: Memnox.Spacing.medium)
            if step < Self.steps.count - 1 {
                Button("Continue", action: next).buttonStyle(KitButton(kind: .primary)).keyboardShortcut(.defaultAction)
            } else {
                Button("Add server") { Task { await finish() } }
                    .buttonStyle(KitButton(kind: .primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(working || screen.hub.busy != nil)
            }
        }
        .padding(.horizontal, Memnox.Spacing.xxLarge)
        .padding(.vertical, Memnox.Spacing.large)
    }

    @ViewBuilder private var serverStep: some View {
        labelled("Name") { TextField("github", text: $name).kitField() }
        labelled("What it is for, optional") { TextField("Issues and pull requests", text: $about).kitField() }
        HStack(spacing: Memnox.Spacing.medium) {
            choice(on: !remote, title: "On this computer", body: "Started by a command") { remote = false }
            choice(on: remote, title: "Remote", body: "Reached at an address") { remote = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("How it runs")
        if remote {
            labelled("Address") { TextField("https://mcp.example.com/mcp", text: $url).kitField() }
            headerRows
            quiet("Memnox stands in front of a remote server, so every call to it is ruled on and recorded. Plain http is only for one on this Mac.")
        } else {
            labelled("Command") {
                TextField("npx -y @modelcontextprotocol/server-github", text: $launch)
                    .kitField()
                    .font(Memnox.Console.code(Memnox.TextSize.body))
            }
        }
    }

    /// A remote server's headers, a credential kept as a secret from the moment its name is typed.
    @ViewBuilder private var headerRows: some View {
        Text("Headers, optional")
            .font(Memnox.Console.sans(Memnox.TextSize.footnote, .medium))
            .foregroundStyle(Memnox.Console.muted)
        ForEach($headers) { $header in
            HStack(spacing: Memnox.Spacing.medium) {
                TextField("Authorization", text: Binding(get: { header.row.name }, set: { typed in
                    header.row.name = typed
                    // A credential header starts kept, and is kept while its name says it is one.
                    if HeaderLines.isCredential(typed) { header.row.secret = true }
                }))
                .kitField()
                .font(Memnox.Console.code(Memnox.TextSize.body))
                .frame(width: Self.variableName)
                .accessibilityLabel("Header name")
                Group {
                    if header.row.secret {
                        SecureField("Bearer your token", text: $header.row.value)
                    } else {
                        TextField("", text: $header.row.value)
                    }
                }
                .kitField()
                .accessibilityLabel("Header value")
                Toggle("Keep as secret", isOn: $header.row.secret)
                    .toggleStyle(CheckboxStyle())
                    .disabled(HeaderLines.isCredential(header.row.name))
                    .help(HeaderLines.isCredential(header.row.name) ? "This header carries a credential, so it is always kept as a secret." : "")
                Button {
                    headers.removeAll { $0.id == header.id }
                } label: {
                    Image(systemName: "minus").frame(width: Self.removeSide, height: Self.removeSide).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Memnox.Console.muted)
                .hoverLight(radius: Memnox.radius, inset: 0)
                .help("Remove this header")
                .accessibilityLabel("Remove this header")
            }
        }
        Button { headers.append(Header()) } label: { Label("Add a header", systemImage: "plus") }
            .buttonStyle(KitButton(kind: .secondary))
    }

    @ViewBuilder private var variablesStep: some View {
        quiet("Mark a token or key as secret: this computer keeps it, and agents\u{2019} configs only name it.")
        ForEach($variables) { $variable in
            HStack(spacing: Memnox.Spacing.medium) {
                TextField("GITHUB_TOKEN", text: $variable.name)
                    .kitField()
                    .font(Memnox.Console.code(Memnox.TextSize.body))
                    .frame(width: Self.variableName)
                    .accessibilityLabel("Variable name")
                Group {
                    if variable.secret {
                        SecureField("", text: $variable.value)
                    } else {
                        TextField("", text: $variable.value)
                    }
                }
                .kitField()
                .accessibilityLabel("Value")
                Toggle("Secret", isOn: $variable.secret).toggleStyle(CheckboxStyle())
                Button {
                    variables.removeAll { $0.id == variable.id }
                } label: {
                    Image(systemName: "minus").frame(width: Self.removeSide, height: Self.removeSide).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Memnox.Console.muted)
                .hoverLight(radius: Memnox.radius, inset: 0)
                .help("Remove this variable")
                .accessibilityLabel("Remove this variable")
            }
        }
        Button { variables.append(Variable()) } label: { Label("Add a variable", systemImage: "plus") }
            .buttonStyle(KitButton(kind: .secondary))
    }

    @ViewBuilder private var agentsStep: some View {
        quiet("Choose who gets it. Each one waits for your signature with Touch ID.")
        if agents.isEmpty {
            Text("No agent with an MCP config was found yet. The server is kept, and you can give it later.")
                .font(Memnox.Console.sans(Memnox.TextSize.body))
                .foregroundStyle(Memnox.Console.muted)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
                ForEach(agents, id: \.self) { agent in
                    let label = McpHubLines.agentLabel(agent)
                    HStack(spacing: Memnox.Spacing.regular) {
                        Toggle(isOn: Binding(get: { given.contains(agent) }, set: { on in
                            if on { given.insert(agent) } else { given.remove(agent) }
                        })) {
                            HStack(spacing: Memnox.Spacing.regular) {
                                BrandLogo(agent: agent, name: label, size: Self.logo)
                                Text(label)
                            }
                        }
                        .toggleStyle(CheckboxStyle())
                    }
                }
            }
        }
        Button(advanced ? "Hide what will be written" : "Show what will be written") { advanced.toggle() }
            .buttonStyle(.plain)
            .font(Memnox.Console.sans(Memnox.TextSize.footnote))
            .foregroundStyle(Memnox.Console.muted)
            .underline()
            .pointingHand()
        if advanced {
            ScrollView {
                Text(previewText)
                    .font(Memnox.Console.code(Memnox.TextSize.micro))
                    .foregroundStyle(Memnox.Console.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(Memnox.Spacing.large)
            }
            .frame(maxHeight: Self.preview)
            .background(Memnox.Console.card, in: RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous))
        }
    }

    /// The server as JSON, secrets as names only, so the person sees exactly what each agent's config will be told.
    private var previewText: String {
        switch draft() {
        case .problem(let why): return why
        case .server(let server):
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            guard let data = try? encoder.encode(server), let text = String(data: data, encoding: .utf8) else { return "" }
            return text
        }
    }

    private func draft() -> Draft {
        let named = McpHubLines.serverName(from: name)
        if named.isEmpty { return .problem("Give the server a name.") }
        var env: [String: String] = [:]
        var secrets: [String: String] = [:]
        for each in variables {
            let variable = each.name.trimmingCharacters(in: .whitespaces)
            guard !variable.isEmpty else { continue }
            if each.secret {
                secrets[variable] = McpHubLines.secretName(server: named, variable: variable)
            } else {
                env[variable] = each.value
            }
        }
        let trimmed = about.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = trimmed.isEmpty ? nil : trimmed
        if remote {
            let address = url.trimmingCharacters(in: .whitespaces)
            if address.isEmpty { return .problem("Give the address the server answers on.") }
            let rows = headers.map(\.row)
            if let why = HeaderLines.addressProblem(address) ?? HeaderLines.problem(rows) { return .problem(why) }
            let sent = HeaderLines.headers(server: named, rows: rows).headers
            return .server(HubServer(name: named, description: description, transport: .http, url: address,
                                     headers: sent.isEmpty ? nil : sent, env: env, secrets: secrets))
        }
        guard let split = McpHubLines.splitCommand(launch) else { return .problem("Give the command that starts the server.") }
        return .server(HubServer(name: named, description: description, transport: .stdio, command: split.command,
                                 args: split.args, env: env, secrets: secrets))
    }

    private func next() {
        if step == 0, case .problem(let why) = draft() {
            problem = why
            return
        }
        problem = nil
        step += 1
    }

    private func finish() async {
        guard case .server(let server) = draft() else {
            if case .problem(let why) = draft() { problem = why }
            return
        }
        working = true
        defer { working = false }
        let hub = screen.hub
        // Secrets first, so the server never starts without its credential.
        let headerSecrets = remote ? HeaderLines.headers(server: server.name, rows: headers.map(\.row)).secrets : [:]
        for (secret, value) in headerSecrets.sorted(by: { $0.key < $1.key }) {
            if case .failed(let why) = await hub.setSecret(secret, value: value) {
                problem = why
                return
            }
        }
        for each in variables where each.secret && !each.value.isEmpty {
            let variable = each.name.trimmingCharacters(in: .whitespaces)
            guard let secret = server.secrets[variable] else { continue }
            if case .failed(let why) = await hub.setSecret(secret, value: each.value) {
                problem = why
                return
            }
        }
        let outcome = await hub.putServer(server)
        if case .failed(let why) = outcome {
            problem = why
            return
        }
        screen.said(outcome)
        // Each agent is asked for once the person has signed the server in, one signature each.
        hub.giveOnceAdded(server.name, agents: agents.filter(given.contains))
        close()
    }

    private func labelled<Field: View>(_ label: String, @ViewBuilder field: () -> Field) -> some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
            Text(label)
                .font(Memnox.Console.sans(Memnox.TextSize.footnote, .medium))
                .foregroundStyle(Memnox.Console.muted)
            field()
        }
    }

    private func choice(on: Bool, title: String, body: String, pick: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
        return Button(action: pick) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                Text(title)
                    .font(Memnox.Console.sans(Memnox.TextSize.body, .medium))
                    .foregroundStyle(Memnox.Console.foreground)
                Text(body)
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Console.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ShellMetrics.rowPaddingH)
            .padding(.vertical, Memnox.Spacing.large)
            .background(on ? Memnox.Console.hover : Color.clear, in: shape)
            .overlay(shape.strokeBorder(on ? Memnox.Console.primary : Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .pointingHand()
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func quiet(_ text: String) -> some View {
        Text(text)
            .font(Memnox.Console.sans(Memnox.TextSize.footnote))
            .foregroundStyle(Memnox.Console.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
