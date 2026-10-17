import MemnoxVoiceCore
import SwiftUI

/// An agent's own question: its logo and name with what the question is about, the question, and one numbered
/// button per choice, so a hand or a number key answers while the voice reads it.
struct IslandQuestion: View {
    @ObservedObject var model: IslandModel
    let card: AgentQuestionCard

    private enum Layout {
        static let padding: CGFloat = 16
        static let logoSide: CGFloat = 34
        static let logoScale: CGFloat = 0.56
        static let optionRadius: CGFloat = 12
        static let optionSpacing: CGFloat = 6
        static let questionLines = 3
        static let detailLines = 2
        static let numberSide: CGFloat = 22
        /// Number keys answer the first nine choices, as a picker in a terminal does.
        static let keyedChoices = 9
    }

    private enum Shade {
        static let veil = 0.42
        static let optionFill = 0.06
        static let optionEdge = 0.08
        static let tickedFill = 0.16
        static let numberFill = 0.1
        static let topicFill = 0.16
    }

    private enum Symbol {
        static let ticked = "checkmark.circle.fill"
        static let unticked = "circle"
        static let failed = "exclamationmark.triangle.fill"
        static let screen = "macwindow"
    }

    var body: some View {
        IslandCard(veil: IslandPalette.amber.opacity(Shade.veil)) {
            if let next = card.next {
                VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
                    heading(next.item)
                    Text(next.item.question)
                        .font(Memnox.sans(Memnox.TextSize.callout, .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(Layout.questionLines)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(next.item.question)
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: Layout.optionSpacing) {
                            ForEach(Array(next.item.options.enumerated()), id: \.element.label) { index, option in
                                optionButton(option, index: index, number: next.number, item: next.item)
                            }
                        }
                    }
                    actions(number: next.number, item: next.item)
                }
                .padding(Layout.padding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .islandContentInset(model.notch)
    }

    /// The agent's logo on its colour, its name and what it is asking about, and how far along when there are several.
    private func heading(_ item: AgentQuestionItem) -> some View {
        HStack(spacing: Memnox.Spacing.regular) {
            AgentLogo(kind: IslandPalette.kind(card.agent), name: card.who)
                .frame(width: Layout.logoSide * Layout.logoScale, height: Layout.logoSide * Layout.logoScale)
                .frame(width: Layout.logoSide, height: Layout.logoSide)
                .background(Circle().fill(IslandPalette.color(card.agent)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                Text(card.who)
                    .font(Memnox.sans(Memnox.TextSize.body, .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                if let error = model.questionError {
                    Label(error, systemImage: Symbol.failed)
                        .font(Memnox.sans(Memnox.TextSize.caption))
                        .foregroundStyle(IslandPalette.red)
                        .lineLimit(1)
                } else {
                    Text("is asking you")
                        .font(Memnox.sans(Memnox.TextSize.caption))
                        .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
                }
            }
            Spacer(minLength: Memnox.Spacing.small)
            if let topic = item.header {
                Text(topic)
                    .font(Memnox.sans(Memnox.TextSize.caption, .semibold))
                    .foregroundStyle(IslandPalette.amber)
                    .lineLimit(1)
                    .padding(.horizontal, Memnox.Spacing.medium)
                    .padding(.vertical, Memnox.Spacing.xSmall)
                    .background(Capsule().fill(IslandPalette.amber.opacity(Shade.topicFill)))
            }
            if let position = card.position {
                Text(position)
                    .font(Memnox.sans(Memnox.TextSize.footnote).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
            }
        }
    }

    /// A choice is the answer itself, except where several are taken, when it ticks and Done sends them.
    private func optionButton(_ option: AgentQuestionOption, index: Int, number: Int, item: AgentQuestionItem) -> some View {
        let ticked = model.ticked.contains(option.label)
        let key = index < Layout.keyedChoices ? KeyEquivalent(Character(String(index + 1))) : nil
        return Button {
            if item.multiSelect {
                if ticked { model.ticked.remove(option.label) } else { model.ticked.insert(option.label) }
            } else {
                model.answerQuestion(card, number, option.label)
            }
        } label: {
            HStack(alignment: .top, spacing: Memnox.Spacing.regular) {
                Group {
                    if item.multiSelect {
                        Image(systemName: ticked ? Symbol.ticked : Symbol.unticked)
                            .foregroundStyle(ticked ? IslandPalette.amber : Color.white.opacity(Memnox.Ink.secondary))
                    } else {
                        Text("\(index + 1)")
                            .font(Memnox.sans(Memnox.TextSize.caption, .semibold).monospacedDigit())
                            .foregroundStyle(Color.white.opacity(Memnox.Ink.primary))
                            .frame(width: Layout.numberSide, height: Layout.numberSide)
                            .background(RoundedRectangle(cornerRadius: Memnox.radius, style: .continuous).fill(Color.white.opacity(Shade.numberFill)))
                    }
                }
                .frame(width: Layout.numberSide, height: Layout.numberSide)
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                    Text(option.label)
                        .font(Memnox.sans(Memnox.TextSize.body, .medium))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    if let detail = option.description {
                        Text(detail)
                            .font(Memnox.sans(Memnox.TextSize.footnote))
                            .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
                            .lineLimit(Layout.detailLines)
                            .fixedSize(horizontal: false, vertical: true)
                            .help(detail)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Memnox.Spacing.large)
            .padding(.vertical, Memnox.Spacing.regular)
            .background(
                RoundedRectangle(cornerRadius: Layout.optionRadius, style: .continuous)
                    .fill(Color.white.opacity(ticked ? Shade.tickedFill : Shade.optionFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Layout.optionRadius, style: .continuous)
                    .strokeBorder(ticked ? IslandPalette.amber : Color.white.opacity(Shade.optionEdge), lineWidth: Memnox.Stroke.hairline)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .keyboardShortcut(key.map { KeyboardShortcut($0, modifiers: []) })
        .help(key == nil ? option.label : "Press \(index + 1)")
        .accessibilityLabel(option.description.map { "\(option.label), \($0)" } ?? option.label)
    }

    /// Skip only puts the card away; the agent's own picker still opens on screen when nobody answers.
    private func actions(number: Int, item: AgentQuestionItem) -> some View {
        HStack(spacing: Memnox.Spacing.medium) {
            Button("Answer on screen", systemImage: Symbol.screen) {
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
            Spacer(minLength: Memnox.Spacing.small)
            Text(item.multiSelect ? "Tick what applies, then Done" : "Pick one, or say your answer")
                .font(Memnox.sans(Memnox.TextSize.caption))
                .foregroundStyle(Color.white.opacity(Memnox.Ink.tertiary))
                .lineLimit(1)
        }
    }
}
