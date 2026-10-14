import AppKit
import MemnoxVoiceCore
import SwiftUI

/// The text column the held and finished cards share.
private enum CallLayout {
    /// Clears the orb, which sits over the card's left side.
    static let textLeading: CGFloat = 98
    static let textTrailing: CGFloat = 18
}

/// The held call: who is waiting, the command, and the three answers it takes.
struct IslandHeldCall: View {
    @ObservedObject var model: IslandModel
    let card: HeldCard

    private enum Layout {
        static let dotSide: CGFloat = 8
        static let commandRadius: CGFloat = 10
    }

    private enum Shade {
        static let veil = 0.42
        static let commandEdge = 0.08
        /// The answers dim while one is being signed, so a second press is not invited.
        static let answering = 0.55
    }

    private static let touchIDSymbol = "touchid"
    private static let olderSymbol = "chevron.left"
    private static let newerSymbol = "chevron.right"
    private static let settledSymbol = "checkmark.circle.fill"

    var body: some View {
        IslandCard(veil: (model.settledNote == nil ? IslandPalette.amber : IslandPalette.green).opacity(Shade.veil)) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.regular) {
                if let header = model.waiting.header { queueRow(header) }
                HStack(spacing: Memnox.Spacing.medium) {
                    Circle().fill(IslandPalette.color(card.agent)).frame(width: Layout.dotSide, height: Layout.dotSide).modifier(PulseEffect())
                    Text(card.who)
                        .font(Memnox.sans(Memnox.TextSize.callout, .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if let note = model.settledNote {
                        Label(note, systemImage: Self.settledSymbol)
                            .font(Memnox.sans(Memnox.TextSize.body))
                            .foregroundStyle(IslandPalette.green)
                            .lineLimit(1)
                    } else {
                        Text(card.why ?? "is waiting on you")
                            .font(Memnox.sans(Memnox.TextSize.body))
                            .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
                            .lineLimit(1)
                    }
                }
                Text(card.what)
                    .font(.system(size: Memnox.TextSize.body, design: .monospaced))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    // Cut in the middle to fit, so the whole command is one hover away before anything is allowed.
                    .help(card.what)
                    .padding(.horizontal, Memnox.Spacing.large)
                    .padding(.vertical, Memnox.Spacing.medium)
                    .background(RoundedRectangle(cornerRadius: Layout.commandRadius).fill(Color.white.opacity(Memnox.Ink.faintFill)))
                    .overlay(RoundedRectangle(cornerRadius: Layout.commandRadius).strokeBorder(Color.white.opacity(Shade.commandEdge), lineWidth: Memnox.Stroke.hairline))
                HStack(spacing: Memnox.Spacing.medium) {
                    Button("Deny") { press(.deny) }.buttonStyle(IslandButton(primary: false))
                    Button { press(.session) } label: { touchID("Allow this session") }
                        .buttonStyle(IslandButton(primary: false))
                    Button { press(.once) } label: { touchID("Allow once") }
                        .buttonStyle(IslandButton(primary: true))
                    // The answer that leaves a rule behind waits behind More, as on every other door.
                    Menu {
                        Button { press(.always) } label: { Label("Allow from now on", systemImage: "touchid") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .accessibilityLabel("More answers")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .pointingHand()
                }
                .disabled(model.answering || model.settledNote != nil)
                .opacity(model.answering || model.settledNote != nil ? Shade.answering : 1)
            }
            .padding(.leading, CallLayout.textLeading)
            .padding(.trailing, CallLayout.textTrailing)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .islandContentInset(model.notch)
    }

    private func press(_ answer: HoldAnswer) {
        model.answering = answer != .deny
        model.pressed = card.subject
        model.answer(card, answer)
    }

    /// How many wait and where, with the way to step through them, so a second call is never hidden behind the first.
    private func queueRow(_ header: String) -> some View {
        HStack(spacing: Memnox.Spacing.small) {
            Text(header)
                .font(Memnox.sans(Memnox.TextSize.footnote, .medium))
                .foregroundStyle(IslandPalette.amber)
                .lineLimit(1)
            Spacer(minLength: Memnox.Spacing.small)
            Button { model.step(1) } label: { Image(systemName: Self.olderSymbol) }
                .buttonStyle(PressableStyle())
                .disabled(!model.waiting.canStepOlder)
                .help("An older call")
                .accessibilityLabel("Older call")
            if let position = model.waiting.positionText {
                Text(position)
                    .font(Memnox.sans(Memnox.TextSize.footnote).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
            }
            Button { model.step(-1) } label: { Image(systemName: Self.newerSymbol) }
                .buttonStyle(PressableStyle())
                .disabled(!model.waiting.canStepNewer)
                .help("A newer call")
                .accessibilityLabel("Newer call")
        }
        .foregroundStyle(Color.white)
        .disabled(model.answering || model.settledNote != nil)
    }

    /// An allow that reaches outside the session is signed, so the button says so before it is pressed.
    private func touchID(_ title: String) -> some View {
        HStack(spacing: Memnox.Spacing.small) {
            if card.touchID {
                Image(systemName: Self.touchIDSymbol).font(.system(size: Memnox.TextSize.footnote, weight: .medium))
            }
            Text(title)
        }
    }
}

/// A session that just finished, with its summary and a way back to it.
struct IslandFinished: View {
    @ObservedObject var model: IslandModel
    let card: FinishedCard

    private static let veilOpacity = 0.5
    private static let summaryLines = 2
    private static let doneSymbol = "checkmark.circle.fill"

    var body: some View {
        IslandCard(veil: IslandPalette.green.opacity(Self.veilOpacity)) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.regular) {
                HStack(spacing: Memnox.Spacing.medium) {
                    Image(systemName: Self.doneSymbol).foregroundStyle(IslandPalette.green)
                    Text(card.who).font(Memnox.sans(Memnox.TextSize.callout, .semibold)).foregroundStyle(Color.white)
                    Text("finished").font(Memnox.sans(Memnox.TextSize.body)).foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
                }
                Text(card.summary)
                    .font(Memnox.sans(Memnox.TextSize.body))
                    .foregroundStyle(IslandPalette.soft)
                    .lineLimit(Self.summaryLines)
                HStack(spacing: Memnox.Spacing.medium) {
                    if let session = card.sessionId {
                        Button("Open") { model.openWindow(session, card.host) }.buttonStyle(IslandButton(primary: false))
                    }
                    Button("OK") {
                        model.finished = nil
                        model.settle()
                    }
                    .buttonStyle(IslandButton(primary: true))
                }
            }
            .padding(.leading, CallLayout.textLeading)
            .padding(.trailing, CallLayout.textTrailing)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .islandContentInset(model.notch)
    }
}

/// How `IslandCard` is drawn; at file scope because a generic type cannot hold static stored properties.
private enum CardStyle {
    static let cornerRadius: CGFloat = 20
    /// The glow's centre sits below the card, so only its upper reach rises into view.
    static let veilCenter = UnitPoint(x: 0.5, y: 1.3)
    static let veilReach: CGFloat = 360
    static let veilFade = Animation.easeInOut(duration: 0.4)
    /// Barely there, so the card's edge shows without framing it.
    static let edgeOpacity = 0.035
}

/// A dark card inside the open island, with a glow rising from its bottom edge in the colour of what is happening.
struct IslandCard<Content: View>: View {
    let veil: Color?
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CardStyle.cornerRadius, style: .continuous)
        content
            .background(
                shape.fill(IslandPalette.card)
                    .overlay {
                        // A fixed reach rather than one measured, since measuring inside a panel's own sizing pass crashed it.
                        if let veil {
                            RadialGradient(
                                colors: [veil, veil.opacity(0)],
                                center: CardStyle.veilCenter,
                                startRadius: 0,
                                endRadius: CardStyle.veilReach
                            )
                            .transition(.opacity)
                        }
                    }
                    .clipShape(shape)
                    .animation(CardStyle.veilFade, value: veil)
            )
            .overlay(shape.strokeBorder(Color.white.opacity(CardStyle.edgeOpacity), lineWidth: Memnox.Stroke.hairline))
    }
}
