import AppKit
import MemnoxVoiceCore
import SwiftUI

/// A profile's name by its id, so a card says which agent carries the work rather than an id.
struct WorkNames {
    private let names: [String: String]

    init(_ profiles: [ProfileView]) {
        names = Dictionary(profiles.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    func name(_ id: String) -> String? { names[id] }
}

/// One piece of open work, with the presses it offers: Accept and Decline on a handoff, Confirm on a done claim, and
/// Stop at any point. None is signed, since each only points or stops an agent.
struct AgentWorkCard: View {
    @ObservedObject var screen: AgentWorkScreen
    let work: AgentWork
    let names: WorkNames

    /// The agent by its job's name, who answers for it, and the tracker; a blank responsible person is left out.
    private var facts: [(String, String)] {
        var facts: [(String, String)] = [("Agent", AgentWorkLines.agentName(work, profileName: names.name))]
        if let responsible = AgentWorkLines.filled(work.responsiblePerson) { facts.append(("Answers to", responsible)) }
        facts.append(("Tracker", AgentWorkLines.trackerName(work.target.source)))
        return facts
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
        let busy = screen.desk.busy != nil
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            WorkLine(work: work)
            FactList(facts: facts)
            if let handoff = work.waitingHandoff {
                Text(AgentWorkLines.handoffLine(handoff, profileName: names.name))
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Console.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Memnox.Spacing.medium) {
                if let handoff = work.waitingHandoff {
                    Button("Accept") { press { await screen.desk.answer(handoff.id, .accept) } }.buttonStyle(KitButton(kind: .primary))
                    Button("Decline") { press { await screen.desk.answer(handoff.id, .decline) } }.buttonStyle(KitButton(kind: .secondary))
                } else if work.workStatus == .doneClaimed {
                    Button("Confirm") { press { await screen.desk.close(work.id) } }
                        .buttonStyle(KitButton(kind: .primary))
                        .help("Closes it as done, once you checked what the agent says it did")
                } else {
                    Button("Close as done") { press { await screen.desk.close(work.id) } }.buttonStyle(KitButton(kind: .secondary))
                }
                // Set apart, so stopping an agent is never pressed by a slip.
                Spacer(minLength: Memnox.Spacing.xxLarge)
                Button("Stop") { press { await screen.desk.stop(work.id) } }.buttonStyle(KitButton(kind: .secondary))
            }
            .disabled(busy)
        }
        .padding(Memnox.Spacing.xLarge)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Memnox.Console.card, in: shape)
        .overlay(shape.strokeBorder(AgentWorkLines.needsYou(work) ? Memnox.Console.warm.opacity(Self.attentionEdge) : Memnox.Console.panelEdge,
                                    lineWidth: Memnox.Stroke.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AgentWorkLines.issue(work))
    }

    private static let attentionEdge = 0.55

    private func press(_ action: @escaping () async -> WorkOutcome) {
        Task { screen.said(await action()) }
    }
}

/// The agent work that waits on the person, for Needs your attention: handoffs to answer and done claims to confirm.
struct WorkNeedingYou: View {
    @ObservedObject var screen: AgentWorkScreen
    let names: WorkNames

    var body: some View {
        let waiting = AgentWorkLines.open(screen.desk.work ?? []).filter(AgentWorkLines.needsYou)
        if !waiting.isEmpty {
            ShellSection(title: "Agent work \u{00B7} \(waiting.count)") {
                VStack(spacing: Memnox.Spacing.large) {
                    ForEach(waiting) { AgentWorkCard(screen: screen, work: $0, names: names) }
                }
            }
        }
    }
}
