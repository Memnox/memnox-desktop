import MemnoxVoiceCore
import SwiftUI

/// Every session the island keeps, grouped by status in the order every surface reads them: what needs the person,
/// what Memnox stopped, what runs, what finished, and what is idle. A session picked opens its facts beside the list, with the way into its live window.
/// While the person is signed in, each session also names the issue the workspace matched it to.
struct SessionsDestination: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var island: IslandModel
    let width: WidthClass

    /// One group per status, in the order every surface lists them, so this page reads as the console's does.
    private static let groups: [(title: String, holds: [SessionStatus])] = SessionStatus.allCases.map { ($0.label, [$0]) }
    private static let logo: CGFloat = 28
    /// Issues move as runs work, so an open page asks again now and then; nothing is asked with no account.
    private static let workRefresh: TimeInterval = 15

    /// Which issue each listed session concerns, as the workspace last said.
    @State private var work: [WorkCorrelation] = []

    var body: some View {
        let cards = island.cards
        let picked = cards.first { $0.sessionId == shell.inspecting }
        InspectorLayout(width: width, title: picked?.agentName, close: { shell.inspecting = nil }) {
            ShellScroll(width: width) {
                if cards.isEmpty {
                    EmptyState(symbol: "cpu", title: "No sessions yet",
                               detail: "When an agent on this Mac starts working, its session shows here with what it is doing and what it touched.")
                }
                ForEach(Self.groups, id: \.title) { group in
                    let held = cards.filter { group.holds.contains($0.status) }
                    if !held.isEmpty {
                        ShellSection(title: "\(group.title) \u{00B7} \(held.count)") {
                            ShellPanel {
                                ForEach(Array(held.enumerated()), id: \.element.id) { index, card in
                                    if index > 0 { ShellDivider() }
                                    row(card)
                                }
                            }
                        }
                    }
                }
            }
        } detail: {
            if let picked {
                SessionFacts(card: picked, work: WorkCorrelationLines.forSession(work, picked.sessionId)) {
                    island.watchLive(picked.sessionId, picked.host)
                }
            }
        }
        .task(id: WorkCorrelationLines.asked(cards.map(\.sessionId))) { await followWork(cards.map(\.sessionId)) }
    }

    /// Reads the issues now and again while the page is open; a change in the sessions listed starts it over.
    private func followWork(_ sessionIds: [String]) async {
        guard let agents = shell.workspaceAgents?.agents else { return }
        while !Task.isCancelled {
            work = await agents.work(of: sessionIds)
            try? await Task.sleep(for: .seconds(Self.workRefresh))
        }
    }

    private func row(_ card: SessionCard) -> some View {
        let issues = WorkCorrelationLines.forSession(work, card.sessionId).map(WorkCorrelationLines.label).joined(separator: ", ")
        return ShellRow(title: card.title,
                 caption: [card.agentName, SessionReading.repository(card.repository), issues.isEmpty ? nil : issues,
                           SessionText.ago(card.lastActive, now: Date())]
                    .compactMap { $0 }.joined(separator: SessionText.separator),
                 chosen: card.sessionId == shell.inspecting,
                 action: { shell.inspecting = card.sessionId }) {
            BrandLogo(agent: card.agent, name: card.agentName, size: Self.logo)
        } trailing: {
            StatusWord(Tone(card.status), card.status.label)
        }
    }
}

/// What the session is, in facts, and the one button that opens it live.
private struct SessionFacts: View {
    let card: SessionCard
    /// The issues this session concerns, already cut to one per claim.
    let work: [WorkCorrelation]
    let open: () -> Void

    private static let logo: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xLarge) {
            HStack(spacing: Memnox.Spacing.large) {
                BrandLogo(agent: card.agent, name: card.agentName, size: Self.logo)
                VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                    Text(card.title)
                        .font(Memnox.Console.sans(Memnox.TextSize.body, .semibold))
                        .foregroundStyle(Memnox.Console.foreground)
                        .lineLimit(2)
                    StatusWord(Tone(card.status), card.status.label)
                }
            }
            FactList(facts: facts)
            if !work.isEmpty { SessionIssues(work: work) }
            Button("Open its live window", action: open)
                .buttonStyle(KitButton(kind: .primary))
        }
    }

    private var facts: [(String, String)] {
        let all: [(String, String?)] = [
            ("Status", card.status.label),
            ("Working on", SessionReading.readable(card.focus) ?? SessionReading.readable(card.task)),
            ("Repository", SessionReading.repository(card.repository)),
            ("Running in", card.runningIn),
            ("Last active", SessionText.ago(card.lastActive, now: Date())),
        ]
        return all.compactMap { name, value in value.map { (name, $0) } }
    }
}

/// The issues a session concerns, each saying what its match rests on, with the one rule behind every match.
private struct SessionIssues: View {
    let work: [WorkCorrelation]

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            Text(WorkCorrelationLines.heading)
                .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.Console.muted)
            ForEach(work) { each in
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                    if let link = WorkCorrelationLines.link(each) {
                        Button(WorkCorrelationLines.label(each), systemImage: "arrow.up.forward") { NSWorkspace.shared.open(link) }
                            .buttonStyle(.plain)
                            .pointingHand()
                            .font(Memnox.Console.sans(Memnox.TextSize.footnote, .medium))
                            .foregroundStyle(Memnox.Console.primary)
                    } else {
                        StatusWord(WorkCorrelationLines.shown(each) == .ambiguous ? .attention : .quiet, WorkCorrelationLines.label(each))
                    }
                    if let reason = WorkCorrelationLines.reason(each) { note(reason) }
                }
            }
            note(WorkCorrelationLines.explain)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
            .foregroundStyle(Memnox.Console.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
