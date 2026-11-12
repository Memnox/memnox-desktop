import MemnoxVoiceCore
import SwiftUI

/// A call waiting on the person, answered where it is read: who asks and the command, then Allow once and Deny, the
/// yes asking for Touch ID when the call reaches outside its session. It answers through the notch's own path, so a
/// yes from a window is signed exactly as a yes from the notch.
struct HeldStrip: View {
    @ObservedObject var model: IslandModel
    let card: HeldCard

    private enum Layout {
        static let commandRadius: CGFloat = 8
        static let logoSide: CGFloat = 22
    }

    /// The answers dim while one is being signed, so a second press is not invited.
    private static let answeringOpacity = 0.55

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.regular) {
            HStack(spacing: Memnox.Spacing.medium) {
                BrandLogo(agent: card.agent, name: card.who, size: Layout.logoSide)
                Text(card.who)
                    .font(Memnox.sans(Memnox.TextSize.body, .semibold))
                    .foregroundStyle(Memnox.Console.ink)
                Text(card.why ?? "is waiting on you")
                    .font(Memnox.sans(Memnox.TextSize.body))
                    .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(card.what)
                .font(.system(size: Memnox.TextSize.footnote, design: .monospaced))
                .foregroundStyle(Memnox.Console.ink)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Memnox.Spacing.medium)
                .background(RoundedRectangle(cornerRadius: Layout.commandRadius).fill(Memnox.ink(Memnox.Ink.faintFill)))
            if let impact = card.impact {
                HeldImpactLines(impact: impact)
            }
            HeldAnswers(size: .strip, touchID: card.touchID) { press($0) }
            .disabled(model.answering)
            .opacity(model.answering ? Self.answeringOpacity : 1)
        }
        .padding(SurfaceStyle.padding)
        .surface(accent: IslandPalette.amber.opacity(Memnox.Ink.secondary))
    }

    private func press(_ answer: HoldAnswer) {
        model.answering = answer != .deny
        model.pressed = card.subject
        model.answer(card, answer)
    }
}
