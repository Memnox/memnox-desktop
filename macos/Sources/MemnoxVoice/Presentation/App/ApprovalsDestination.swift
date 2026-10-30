import MemnoxVoiceCore
import SwiftUI

/// What waits on the person, oldest first, each saying exactly what the agent wants to do. Every answer goes through
/// the island's own path, so a yes that reaches outside the session is signed with Touch ID exactly as on the island.
struct ApprovalsDestination: View {
    @ObservedObject var island: IslandModel
    let width: WidthClass

    var body: some View {
        let waiting = island.waiting.entries
        ShellScroll(width: width) {
            NoticesSwitch(notifier: HeldNotifier.shared)
            if waiting.isEmpty {
                EmptyState(symbol: "checkmark.shield", title: "Nothing is waiting on you",
                           detail: "When an agent asks before doing something your rules hold, it waits here and on the island.")
            } else {
                Text("\(waiting.count) waiting, oldest first.")
                    .font(Memnox.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Palette.muted)
                VStack(spacing: Memnox.Spacing.large) {
                    ForEach(waiting, id: \.subject) { entry in
                        HeldCallCard(card: entry.card, busy: island.answering || island.settledNote != nil) { answer in
                            answerHeld(entry.card, answer)
                        }
                    }
                }
            }
        }
    }

    /// The same three steps the island's buttons take, so its bookkeeping and Touch ID sheet behave as for a tap there.
    private func answerHeld(_ card: HeldCard, _ answer: HoldAnswer) {
        island.answering = answer != .deny
        island.pressed = card.subject
        island.answer(card, answer)
    }
}

private struct HeldCallCard: View {
    let card: HeldCard
    let busy: Bool
    let answer: (HoldAnswer) -> Void

    private static let logo: CGFloat = 26

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            HStack(spacing: Memnox.Spacing.regular) {
                BrandLogo(agent: card.agent, name: card.who, size: Self.logo)
                Text(card.who)
                    .font(Memnox.sans(Memnox.TextSize.body, .semibold))
                    .foregroundStyle(Memnox.Palette.foreground)
                    .lineLimit(1)
                Spacer(minLength: Memnox.Spacing.medium)
                StatusWord(.attention, "Asks first")
            }
            Text(card.what)
                .font(Memnox.sans(Memnox.TextSize.body))
                .foregroundStyle(Memnox.Palette.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            FactList(facts: facts)
            HStack(spacing: Memnox.Spacing.medium) {
                Button("Allow once") { answer(.once) }.buttonStyle(KitButton(kind: .primary))
                Button("Allow this session") { answer(.session) }.buttonStyle(KitButton(kind: .secondary))
                // Set apart from the yeses, so a refusal is never pressed by a slip.
                Spacer(minLength: Memnox.Spacing.xxLarge)
                Button("Deny") { answer(.deny) }.buttonStyle(KitButton(kind: .secondary))
            }
            .disabled(busy)
        }
        .padding(Memnox.Spacing.xLarge)
        .background(Memnox.Palette.card, in: shape)
        .overlay(shape.strokeBorder(Memnox.Palette.panelEdge, lineWidth: Memnox.Stroke.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(card.who) asks first")
    }

    private var facts: [(String, String)] {
        var facts: [(String, String)] = []
        if let why = card.why { facts.append(("Why it asks", why)) }
        facts.append(("Signed", HeldSigning.line(touchID: card.touchID, actionDigest: card.actionDigest)))
        return facts
    }
}

/// Whether a held call the island is not showing is also said by the system; turning it on asks the system once.
private struct NoticesSwitch: View {
    @ObservedObject var notifier: HeldNotifier

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
            Toggle(isOn: $notifier.on) {
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                    Text(HeldNotices.title)
                        .font(Memnox.sans(Memnox.TextSize.body, .medium))
                        .foregroundStyle(Memnox.Palette.foreground)
                    Text(HeldNotices.detail)
                        .font(Memnox.sans(Memnox.TextSize.footnote))
                        .foregroundStyle(Memnox.Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            if notifier.on, notifier.refused {
                StatusWord(.attention, HeldNotices.denied)
            }
        }
    }
}
