import MemnoxVoiceCore
import SwiftUI

/// Every session the island keeps, in the order they are read in: what needs the person, then what runs, then what is
/// idle, then what is done. A session picked opens its facts beside the list, with the way into its live window.
struct SessionsDestination: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var island: IslandModel
    let width: WidthClass

    private static let groups: [(title: String, holds: [SessionStatus])] = [
        ("Needs you", [.needsYou, .waitingOnYou, .paused]),
        ("Running", [.working, .thinking]),
        ("Idle", [.quiet]),
        ("Finished", [.ended]),
    ]
    private static let logo: CGFloat = 28

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
            if let picked { SessionFacts(card: picked) { island.watchLive(picked.sessionId, picked.host) } }
        }
    }

    private func row(_ card: SessionCard) -> some View {
        ShellRow(title: card.title,
                 caption: [card.agentName, SessionReading.repository(card.repository), SessionText.ago(card.lastActive, now: Date())]
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
    let open: () -> Void

    private static let logo: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xLarge) {
            HStack(spacing: Memnox.Spacing.large) {
                BrandLogo(agent: card.agent, name: card.agentName, size: Self.logo)
                VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                    Text(card.title)
                        .font(Memnox.sans(Memnox.TextSize.body, .semibold))
                        .foregroundStyle(Memnox.Palette.foreground)
                        .lineLimit(2)
                    StatusWord(Tone(card.status), card.status.label)
                }
            }
            FactList(facts: facts)
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
