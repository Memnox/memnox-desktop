import MemnoxVoiceCore
import SwiftUI

/// The answers to a held call, one component wherever a call is answered: the contract's words in its order with Deny
/// last, so a hand reaching for the usual place never lands on a refusal, and Touch ID beside a yes that reaches outside
/// the session. Always allow writes a rule, so it waits behind More where one can be signed.
struct HeldAnswers: View {
    /// The island on the dark notch, a strip in a narrow list, or a card on a page.
    enum Size {
        case island
        case strip
        case card
    }

    let size: Size
    /// Whether a yes is signed with Touch ID, which the daemon decides and the card carries.
    let touchID: Bool
    /// Offers Always allow behind More, where a rule can be signed.
    var always = false
    let press: (HoldAnswer) -> Void

    private static let touchIDSymbol = "touchid"

    var body: some View {
        HStack(spacing: Memnox.Spacing.medium) {
            ForEach(shown, id: \.rawValue) { answer in
                // Set apart on a card, so a refusal is never pressed by a slip.
                if answer == .deny, size == .card { Spacer(minLength: Memnox.Spacing.xxLarge) }
                button(answer)
            }
            if always { more }
        }
    }

    /// A strip is narrow, so it offers the narrowest yes and Deny; the island and a card offer every answer.
    private var shown: [HoldAnswer] {
        size == .strip ? AnswerWords.order.filter { $0 != .session } : AnswerWords.order
    }

    @ViewBuilder private func button(_ answer: HoldAnswer) -> some View {
        let label = HStack(spacing: Memnox.Spacing.small) {
            if touchID, answer != .deny {
                Image(systemName: Self.touchIDSymbol).font(.system(size: Memnox.TextSize.footnote, weight: .medium))
            }
            Text(AnswerWords.label(answer))
        }
        // No Return shortcut anywhere, since a stray keypress must never allow an agent's command.
        switch size {
        case .island:
            Button { press(answer) } label: { label }.buttonStyle(IslandButton(primary: answer == .once))
        case .strip, .card:
            Button { press(answer) } label: { label }.buttonStyle(KitButton(kind: answer == .once ? .primary : .secondary))
        }
    }

    private var more: some View {
        Menu {
            Button { press(.always) } label: { Label(AnswerWords.label(.always), systemImage: Self.touchIDSymbol) }
        } label: {
            Image(systemName: "ellipsis").accessibilityLabel("More answers")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .pointingHand()
    }
}
