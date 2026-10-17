import MemnoxVoiceCore
import SwiftUI

/// The agents on this Mac that can think for the voice. Once one answers, the ones that cannot fold into a single
/// line, since they no longer stand in the way; until then each shows what its own account said back.
struct AgentChecks: View {
    @ObservedObject var setup: SetupModel
    @State private var showingStuck = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Layout {
        static let stackSide: CGFloat = 22
        static let stackOverlap: CGFloat = -8
        static let stackRim: CGFloat = 2
        static let quoteLines = 3
        static let quoteRadius: CGFloat = 8
        static let pillDot: CGFloat = 6
        /// Enough of the warm hue behind the pill to read as a status, not as a button.
        static let pillFill = 0.14
    }

    var body: some View {
        let installed = setup.agents.filter(\.installed)
        let stuck = installed.filter(AgentCheckText.notReady)
        let ready = installed.filter { !AgentCheckText.notReady($0) }
        let anyAnswers = ready.contains { $0.works == true }
        Group {
            ForEach(ready) { agent in
                if agent.id != ready.first?.id { KitDivider() }
                readyRow(agent)
            }
            if !stuck.isEmpty {
                if !ready.isEmpty { KitDivider() }
                if anyAnswers { fold(stuck) }
                if !anyAnswers || showingStuck {
                    ForEach(stuck) { agent in
                        if anyAnswers || agent.id != stuck.first?.id { KitDivider() }
                        stuckRow(agent)
                    }
                    footer
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: Memnox.Motion.standard), value: showingStuck)
    }

    private func readyRow(_ agent: VoiceAgentStatus) -> some View {
        KitRow(title: agent.label, detail: AgentCheckText.status(agent, checking: setup.checkingAgents), leading: {
            BrandLogo(agent: agent.kind, name: agent.label, size: Kit.tileSide)
        }, trailing: {
            if agent.chosen {
                CheckBox(state: .done)
            } else if agent.works == true {
                Button("Use", systemImage: "checkmark") { Task { await setup.useAgent(agent.kind) } }
                    .buttonStyle(KitButton(kind: .secondary))
            } else if setup.checkingAgents {
                ProgressView().controlSize(.small)
            }
        })
    }

    /// The agents that cannot answer, as one line under the one that can, with their logos stacked like a group.
    private func fold(_ stuck: [VoiceAgentStatus]) -> some View {
        let names = AgentCheckText.names(stuck.map(\.label))
        let chosen = setup.agents.first(where: \.chosen)?.label
        return KitRow(title: "\(names) can't answer yet",
                      detail: chosen.map { "Nothing to do now, since \($0) already answers for you." }
                        ?? "Nothing to do now, since another agent already answers for you.",
                      leading: { logoStack(stuck) }, trailing: {
            Button(showingStuck ? "Hide" : "Show why", systemImage: showingStuck ? "chevron.up" : "chevron.down") {
                showingStuck.toggle()
            }
            .buttonStyle(KitButton(kind: .secondary))
        })
    }

    private func logoStack(_ stuck: [VoiceAgentStatus]) -> some View {
        HStack(spacing: Layout.stackOverlap) {
            ForEach(stuck.prefix(3)) { agent in
                BrandLogo(agent: agent.kind, name: agent.label, size: Layout.stackSide)
                    .padding(Layout.stackRim)
                    .background(Circle().fill(Memnox.Palette.card))
            }
        }
        .frame(width: Kit.tileSide, height: Kit.tileSide)
        .accessibilityHidden(true)
    }

    /// The agent, a short reason, and its own account's words quoted under it, so nobody takes them for Memnox's.
    private func stuckRow(_ agent: VoiceAgentStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            KitRow(title: agent.label, detail: AgentCheckText.status(agent, checking: setup.checkingAgents), leading: {
                BrandLogo(agent: agent.kind, name: agent.label, size: Kit.tileSide)
            }, trailing: { notReadyPill })
            if let reply = AgentCheckText.reply(agent) { quote(reply, from: agent.label) }
        }
    }

    private var notReadyPill: some View {
        HStack(spacing: Memnox.Spacing.xSmall) {
            Circle().fill(Memnox.Palette.warm).frame(width: Layout.pillDot, height: Layout.pillDot)
            Text("Not ready")
                .font(Memnox.sans(Memnox.TextSize.footnote, .medium))
                .foregroundStyle(Memnox.Palette.warm)
        }
        .padding(.horizontal, Memnox.Spacing.medium)
        .padding(.vertical, Memnox.Spacing.xSmall)
        .background(Capsule().fill(Memnox.Palette.warm.opacity(Layout.pillFill)))
    }

    private func quote(_ reply: String, from label: String) -> some View {
        HStack(alignment: .top, spacing: Memnox.Spacing.small) {
            Image(systemName: "quote.opening")
                .font(.system(size: Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.ink(Memnox.Ink.tertiary))
            Text(reply)
                .font(.system(size: Memnox.TextSize.footnote, design: .monospaced))
                .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                .lineLimit(Layout.quoteLines)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .help(reply)
        }
        .padding(Memnox.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Layout.quoteRadius, style: .continuous).fill(Memnox.Palette.field))
        .padding(.leading, Kit.tileSide + Memnox.Spacing.large)
        .padding(.bottom, Memnox.Spacing.regular)
        .accessibilityLabel("\(label) replied: \(reply)")
    }

    /// The fix lives in the agent's own account, so the one thing to do here is ask again after.
    private var footer: some View {
        HStack(spacing: Memnox.Spacing.medium) {
            Text("Fix it in the agent's own account, then check again.")
                .font(Memnox.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
            Spacer(minLength: Memnox.Spacing.medium)
            if setup.checkingAgents { ProgressView().controlSize(.small) }
            Button("Check again", systemImage: "arrow.clockwise") { Task { await setup.loadAgents(recheck: true) } }
                .buttonStyle(KitButton(kind: .secondary))
                .disabled(setup.checkingAgents)
        }
        .padding(.leading, Kit.tileSide + Memnox.Spacing.large)
        .padding(.vertical, Memnox.Spacing.regular)
    }
}
