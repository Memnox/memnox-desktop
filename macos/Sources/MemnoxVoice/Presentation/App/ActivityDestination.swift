import AppKit
import MemnoxVoiceCore
import SwiftUI

/// What the agents did, newest first: what was decided beside what happened, and why any one of it came out as it did.
/// Names only, never arguments or file contents.
struct ActivityDestination: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var screen: ActivityScreen
    let width: WidthClass

    @State private var effect: RuleEffect?
    @State private var kind: ActivityKind?
    @State private var text = ""

    private static let kinds: [(ActivityKind?, String)] = [
        (nil, "Everything"), (.command, "Commands"), (.file, "Files"), (.mcp, "MCP tools"), (.tool, "Other tools"),
    ]
    private static let searchWidth: CGFloat = 280
    private static let kindWidth: CGFloat = 150
    private static let logo: CGFloat = 24

    var body: some View {
        let activity = screen.activity
        let decision = shell.inspecting == nil ? nil : activity.decision
        InspectorLayout(width: width, title: decision == nil ? nil : "Why", close: close) {
            ShellScroll(width: width) {
                toolbar
                if let note = screen.note { QuietLine(note) }
                list
                if activity.more {
                    Button(activity.loading ? "Reading" : "Show older") { Task { await activity.readOn() } }
                        .buttonStyle(KitButton(kind: .secondary))
                        .disabled(activity.loading)
                }
            }
        } detail: {
            if let decision { DecisionDetail(view: decision) { shell.go(WindowRoute(.governance, tab: "policies")) } }
        }
        .task(id: filter) { await activity.show(filter) }
    }

    private var filter: ActivityFilter {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return ActivityFilter(effect: effect, kind: kind, text: words.isEmpty ? nil : words)
    }

    private var toolbar: some View {
        HStack(spacing: Memnox.Spacing.medium) {
            SearchField(prompt: "Search actions and targets", text: $text).frame(maxWidth: Self.searchWidth)
            HStack(spacing: Memnox.Spacing.small) {
                FilterChip(title: "Any", chosen: effect == nil) { effect = nil }
                ForEach(RuleEffect.allCases, id: \.self) { each in
                    FilterChip(title: StudioLines.words(each).title, chosen: effect == each) { effect = each }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Decided")
            Picker("Kind", selection: $kind) {
                ForEach(Self.kinds, id: \.1) { each in
                    Text(each.1).tag(each.0)
                }
            }
            .labelsHidden()
            .frame(maxWidth: Self.kindWidth)
            .accessibilityLabel("Kind")
            Spacer(minLength: Memnox.Spacing.medium)
            Button(action: copyRecord) { Label("Copy signed record", systemImage: "doc.on.doc") }
                .buttonStyle(KitButton(kind: .secondary))
                .help("Copy what this view shows as a signed record that memnox verify checks")
        }
    }

    @ViewBuilder private var list: some View {
        let activity = screen.activity
        let rows = activity.rows
        if activity.unreadable, rows.isEmpty {
            ReadFailed(what: "the activity") { Task { await activity.show(filter) } }
        } else if rows.isEmpty, !activity.loading {
            EmptyState(symbol: "clock.arrow.circlepath", title: "Nothing here yet",
                       detail: "What your agents do on this computer appears here as it happens, with what your rules decided.")
        } else {
            ShellPanel {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { ShellDivider() }
                    rowView(row)
                }
            }
        }
    }

    private func rowView(_ row: ActivityRow) -> some View {
        let caption = [row.agentName, SessionText.ago(row.at, now: Date()), row.rule,
                       StudioLines.answeredWords(by: row.answeredBy, how: row.answeredHow)]
            .compactMap { $0 }.joined(separator: SessionText.separator)
        return CodeRow(title: StudioLines.activityLine(operation: row.operation, target: row.target), caption: caption,
                       chosen: shell.inspecting == row.id, action: { open(row.id) }) {
            BrandLogo(agent: row.agent, name: row.agentName, size: Self.logo)
        } trailing: {
            HStack(spacing: Memnox.Spacing.large) {
                if let failed = row.failed { StatusWord(.bad, "Failed, exit \(failed)") }
                StatusWord(Tone(effect: row.effect), StudioLines.title(row.effect))
            }
        }
    }

    private func open(_ id: String) {
        shell.inspecting = id
        Task { await screen.activity.open(id) }
    }

    private func close() {
        shell.inspecting = nil
        screen.activity.close()
    }

    private func copyRecord() {
        Task {
            guard let bundle = await screen.activity.exportBundle() else {
                screen.note = "The runtime did not hand over a record."
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(bundle, forType: .string)
            screen.note = "Copied the signed record of what this view shows. memnox verify checks it."
        }
    }
}

/// Why one action came out as it did: its rule, who it acted for, what was known, what led up to it, and what ran.
private struct DecisionDetail: View {
    let view: DecisionView
    let change: () -> Void

    var body: some View {
        let row = view.row
        VStack(alignment: .leading, spacing: Memnox.Spacing.xxLarge) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
                Text(StudioLines.activityLine(operation: row.operation, target: row.target))
                    .font(Memnox.mono(Memnox.TextSize.body))
                    .foregroundStyle(Memnox.Palette.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                StatusWord(Tone(effect: row.effect), StudioLines.says(row.effect))
                Text(row.reason)
                    .font(Memnox.sans(Memnox.TextSize.body))
                    .foregroundStyle(Memnox.Palette.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let instead = view.alternative { QuietLine("Instead: \(instead)") }
            }
            if let rule = view.rule {
                ShellSection(title: "The rule") {
                    Text(rule.name)
                        .font(Memnox.sans(Memnox.TextSize.body))
                        .foregroundStyle(Memnox.Palette.foreground)
                    let from = rule.source.map { StudioLines.sourceWords($0, decidedBy: rule.decidedBy, file: rule.file) }
                    let words = [from, rule.newerSince == true ? "It has changed since." : nil].compactMap { $0 }.joined(separator: " ")
                    if !words.isEmpty { QuietLine(words) }
                    Button("Change this rule", action: change).buttonStyle(KitButton(kind: .secondary))
                }
            }
            if !view.chain.isEmpty {
                ShellSection(title: "Who it acted for") { QuietLine(view.chain) }
            }
            if !view.context.isEmpty {
                ShellSection(title: "What was known") {
                    ShellPanel {
                        ForEach(Array(view.context.enumerated()), id: \.offset) { index, part in
                            if index > 0 { ShellDivider() }
                            ShellRow(title: part.domain, caption: part.facts.joined(separator: SessionText.separator)) {
                                EmptyView()
                            } trailing: {
                                if part.decided { StatusWord(.attention, "Decided it") }
                            }
                        }
                    }
                }
            }
            if !view.before.isEmpty {
                ShellSection(title: "What led up to it") {
                    ShellPanel {
                        ForEach(Array(view.before.enumerated()), id: \.offset) { index, step in
                            if index > 0 { ShellDivider() }
                            CodeRow(title: StudioLines.activityLine(operation: step.operation, target: step.target),
                                    caption: SessionText.ago(step.at, now: Date())) {
                                EmptyView()
                            } trailing: {
                                StatusWord(Tone(effect: step.effect), StudioLines.title(step.effect))
                            }
                        }
                    }
                }
            }
            ShellSection(title: "What happened") { FactList(facts: happened) }
        }
    }

    private var happened: [(String, String)] {
        var facts = [("Ran as", view.trace.mode)]
        if let exit = view.trace.exitCode { facts.append(("Exit", String(exit))) }
        if let approver = view.trace.approvedBy { facts.append(("Approved by", approver)) }
        return facts
    }
}
