import MemnoxVoiceCore
import SwiftUI

/// An agent's own question: who asks, what, and one button per choice, so a hand answers while the voice reads it.
struct IslandQuestion: View {
    @ObservedObject var model: IslandModel
    let card: AgentQuestionCard

    private enum Layout {
        /// Clears the orb, which sits over the card's left side, as on the held call.
        static let textLeading: CGFloat = 98
        static let textTrailing: CGFloat = 18
        static let optionRadius: CGFloat = 10
        static let optionSpacing: CGFloat = 6
        static let questionLines = 2
        static let detailLines = 1
    }

    private enum Shade {
        static let veil = 0.42
        static let optionFill = 0.06
        static let optionEdge = 0.08
        static let tickedFill = 0.16
    }

    private enum Symbol {
        static let ticked = "checkmark.circle.fill"
        static let unticked = "circle"
        static let failed = "exclamationmark.triangle.fill"
    }

    var body: some View {
        IslandCard(veil: IslandPalette.amber.opacity(Shade.veil)) {
            if let next = card.next {
                VStack(alignment: .leading, spacing: Memnox.Spacing.regular) {
                    heading(next.item)
                    Text(next.item.question)
                        .font(Memnox.sans(Memnox.TextSize.body, .medium))
                        .foregroundStyle(Color.white)
                        .lineLimit(Layout.questionLines)
                        .help(next.item.question)
                    ScrollView {
                        VStack(spacing: Layout.optionSpacing) {
                            ForEach(next.item.options, id: \.label) { option in
                                optionButton(option, number: next.number, item: next.item)
                            }
                        }
                    }
                    actions(number: next.number, item: next.item)
                }
                .padding(.leading, Layout.textLeading)
                .padding(.trailing, Layout.textTrailing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .islandContentInset(model.notch)
    }

    private func heading(_ item: AgentQuestionItem) -> some View {
        HStack(spacing: Memnox.Spacing.medium) {
            Text(card.who)
                .font(Memnox.sans(Memnox.TextSize.callout, .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
            if let error = model.questionError {
                Label(error, systemImage: Symbol.failed)
                    .font(Memnox.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(IslandPalette.red)
                    .lineLimit(1)
            } else {
                Text(item.header ?? "is asking you")
                    .font(Memnox.sans(Memnox.TextSize.body))
                    .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
                    .lineLimit(1)
            }
            Spacer(minLength: Memnox.Spacing.small)
            if let position = card.position {
                Text(position)
                    .font(Memnox.sans(Memnox.TextSize.footnote).monospacedDigit())
                    .foregroundStyle(IslandPalette.amber)
            }
        }
    }

    /// A choice is the answer itself, except where several are taken, when it ticks and Done sends them.
    private func optionButton(_ option: AgentQuestionOption, number: Int, item: AgentQuestionItem) -> some View {
        let ticked = model.ticked.contains(option.label)
        return Button {
            if item.multiSelect {
                if ticked { model.ticked.remove(option.label) } else { model.ticked.insert(option.label) }
            } else {
                model.answerQuestion(card, number, option.label)
            }
        } label: {
            HStack(spacing: Memnox.Spacing.medium) {
                if item.multiSelect {
                    Image(systemName: ticked ? Symbol.ticked : Symbol.unticked)
                        .foregroundStyle(ticked ? IslandPalette.amber : Color.white.opacity(Memnox.Ink.secondary))
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(option.label)
                        .font(Memnox.sans(Memnox.TextSize.body, .medium))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    if let detail = option.description {
                        Text(detail)
                            .font(Memnox.sans(Memnox.TextSize.footnote))
                            .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
                            .lineLimit(Layout.detailLines)
                            .help(detail)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Memnox.Spacing.large)
            .padding(.vertical, Memnox.Spacing.medium)
            .background(
                RoundedRectangle(cornerRadius: Layout.optionRadius)
                    .fill(Color.white.opacity(ticked ? Shade.tickedFill : Shade.optionFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Layout.optionRadius)
                    .strokeBorder(Color.white.opacity(Shade.optionEdge), lineWidth: Memnox.Stroke.hairline)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(option.description.map { "\(option.label), \($0)" } ?? option.label)
    }

    /// Skip only puts the card away; the agent's own picker still opens on screen when nobody answers.
    private func actions(number: Int, item: AgentQuestionItem) -> some View {
        HStack(spacing: Memnox.Spacing.medium) {
            Button("Answer on screen") {
                model.question = nil
                model.ticked = []
                model.questionError = nil
                model.settle()
            }
            .buttonStyle(IslandButton(primary: false))
            if item.multiSelect {
                Button("Done") { model.answerQuestion(card, number, AgentQuestionCard.joined(model.ticked, from: item)) }
                    .buttonStyle(IslandButton(primary: true))
                    .disabled(model.ticked.isEmpty)
            }
        }
    }
}
