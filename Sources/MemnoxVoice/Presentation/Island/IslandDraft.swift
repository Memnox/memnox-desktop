import AppKit
import MemnoxVoiceCore
import SwiftUI

/// A message the person's connected mail would send, laid out the way a mail app lays it out: who it
/// goes to, the subject and the words, typed in as it arrives. Nothing here edits it, since Send signs
/// exactly what the runtime drafted; Send takes Touch ID and closing it goes unsigned.
struct IslandDraftCard: View {
    @ObservedObject var model: IslandModel
    let card: DraftCard
    @State private var typed = 0

    private enum Layout {
        static let padding: CGFloat = 14
        static let rowHeight: CGFloat = 34
        static let chipHorizontal: CGFloat = 10
        static let chipVertical: CGFloat = 4
        static let markSide: CGFloat = 16
        static let closeSide: CGFloat = 24
        static let bodySize: CGFloat = 14
        static let bodyLineSpacing: CGFloat = 4
        static let caretWidth: CGFloat = 1.5
        static let caretHeight: CGFloat = 16
    }

    private enum Shade {
        static let veil = 0.38
        static let rule = 0.07
        static let chip = 0.1
        /// The answers dim while Touch ID is up, so a second press is not invited.
        static let sending = 0.55
    }

    private enum Symbol {
        static let mail = "envelope.fill"
        static let reply = "arrowshape.turn.up.left"
        static let close = "xmark"
        static let thread = "chevron.down"
        static let copy = "doc.on.doc"
        static let touchID = "touchid"
    }

    /// The pace the body types itself in at, quick enough that a long message is whole in about a second.
    private enum Typing {
        static let framesPerSecond: Double = 60
        static let wholeInSeconds: Double = 1.1
        static let fewestPerFrame = 2
        static let nanosecondsPerSecond: Double = 1_000_000_000
    }

    /// The red the mark is drawn in, so the card reads as mail at a glance.
    private static let mailRed = Color(hex: 0xEA4335)
    private static let sendBlue = Color(hex: 0x1A73E8)

    var body: some View {
        let draft = card.draft
        IslandCard(veil: Memnox.Palette.primary.opacity(Shade.veil)) {
            VStack(alignment: .leading, spacing: 0) {
                header
                rule
                if card.isReply, let thread = draft.thread, thread > 0 {
                    Label("View thread (\(thread))", systemImage: Symbol.thread)
                        .font(Memnox.sans(Memnox.TextSize.body, .medium))
                        .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
                        .frame(height: Layout.rowHeight)
                    rule
                }
                recipients("To", draft.to)
                if let cc = draft.cc, !cc.isEmpty {
                    rule
                    recipients("Cc", cc)
                }
                if let subject = draft.subject, !subject.isEmpty {
                    rule
                    Text(subject)
                        .font(Memnox.sans(Memnox.TextSize.callout, .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .frame(height: Layout.rowHeight)
                }
                rule
                bodyText
                footer
            }
            .padding(.horizontal, Layout.padding)
            .padding(.bottom, Layout.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task(id: card.subject) { await typeIn() }
    }

    private var header: some View {
        HStack(spacing: Memnox.Spacing.medium) {
            Image(systemName: Symbol.mail)
                .font(.system(size: Layout.markSide))
                .foregroundStyle(Self.mailRed)
            if card.isReply {
                Image(systemName: Symbol.reply).foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
            }
            Text(card.isReply ? "Reply" : "New Message")
                .font(Memnox.sans(Memnox.TextSize.callout, .semibold))
                .foregroundStyle(Color.white)
            Spacer()
            Button { answer(send: false) } label: {
                Image(systemName: Symbol.close)
                    .font(.system(size: Memnox.TextSize.footnote, weight: .bold))
                    .foregroundStyle(Color.white.opacity(Memnox.Ink.primary))
                    .frame(width: Layout.closeSide, height: Layout.closeSide)
                    .background(Circle().fill(Color.white.opacity(Shade.chip)))
            }
            .buttonStyle(PressableStyle())
            .help("Close without sending")
        }
        .frame(height: Layout.rowHeight + Memnox.Spacing.medium)
    }

    private var rule: some View {
        Rectangle().fill(Color.white.opacity(Shade.rule)).frame(height: Memnox.Stroke.hairline)
    }

    private func recipients(_ label: String, _ people: [String]) -> some View {
        HStack(spacing: Memnox.Spacing.medium) {
            Text(label)
                .font(Memnox.sans(Memnox.TextSize.body))
                .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
            ForEach(people, id: \.self) { person in
                Text(person)
                    .font(Memnox.sans(Memnox.TextSize.body, .medium))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .padding(.horizontal, Layout.chipHorizontal)
                    .padding(.vertical, Layout.chipVertical)
                    .background(Capsule().fill(Color.white.opacity(Shade.chip)))
            }
            Spacer(minLength: 0)
        }
        .frame(height: Layout.rowHeight)
    }

    private var bodyText: some View {
        let body = card.draft.body
        let shown = String(body.prefix(typed))
        return ScrollView(.vertical, showsIndicators: false) {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(shown)
                    .font(Memnox.sans(Layout.bodySize))
                    .lineSpacing(Layout.bodyLineSpacing)
                    .foregroundStyle(Color.white.opacity(Memnox.Ink.primary))
                    .fixedSize(horizontal: false, vertical: true)
                if typed < body.count {
                    Rectangle().fill(Color.white).frame(width: Layout.caretWidth, height: Layout.caretHeight)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Memnox.Spacing.regular)
        }
        .defaultScrollAnchor(typed < body.count ? .bottom : .top)
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: Memnox.Spacing.medium) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(card.draft.body, forType: .string)
            } label: { Image(systemName: Symbol.copy) }
                .buttonStyle(IslandButton(primary: false))
                .help("Copy the message")
            Spacer()
            Button { answer(send: true) } label: {
                HStack(spacing: Memnox.Spacing.small) {
                    Image(systemName: Symbol.touchID)
                    Text("Send")
                }
                .font(Memnox.sans(Memnox.TextSize.callout, .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, Memnox.Spacing.xLarge)
                .padding(.vertical, Memnox.Spacing.medium)
                .background(Capsule().fill(Self.sendBlue))
            }
            .buttonStyle(PressableStyle())
        }
        .disabled(model.sending)
        .opacity(model.sending ? Shade.sending : 1)
    }

    private func answer(send: Bool) {
        model.sending = send
        model.answerDraft(card, send)
    }

    /// Types the body in a few characters a frame, so a message of any length arrives in about the same second.
    private func typeIn() async {
        typed = 0
        let total = card.draft.body.count
        let frames = Typing.framesPerSecond * Typing.wholeInSeconds
        let step = max(Typing.fewestPerFrame, Int((Double(total) / frames).rounded(.up)))
        while typed < total, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(Typing.nanosecondsPerSecond / Typing.framesPerSecond))
            typed = min(total, typed + step)
        }
    }
}
