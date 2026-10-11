import MemnoxVoiceCore
import SwiftUI

/// What is about to go out in the person's name, laid out the way its own tool lays it out: a Slack
/// message, a GitHub or Linear comment, a mail. It names the account it goes out as and shows every
/// argument, since Send signs exactly what the runtime proposed; closing it goes unsigned.
struct IslandWorkCard: View {
    @ObservedObject var model: IslandModel
    let card: WorkCard

    private enum Layout {
        static let padding: CGFloat = 14
        static let markSide: CGFloat = 22
        static let avatarSide: CGFloat = 32
        static let closeSide: CGFloat = 24
        static let rowHeight: CGFloat = 30
        static let bodySize: CGFloat = 14
        static let bodyLineSpacing: CGFloat = 4
        static let commentRadius: CGFloat = 8
        static let fieldNameWidth: CGFloat = 96
    }

    private enum Shade {
        static let rule = 0.07
        static let chip = 0.1
        static let commentHeader = 0.05
        /// The answers dim while Touch ID is up, so a second press is not invited.
        static let sending = 0.55
    }

    private enum Symbol {
        static let close = "xmark"
        static let touchID = "touchid"
        static let matched = "checkmark.seal.fill"
        static let unverified = "exclamationmark.triangle.fill"
        static let place = "arrow.turn.down.right"
    }

    private var draft: WorkDraft { card.draft }
    private var tool: String { ToolkitName.of(draft.toolkit) }

    var body: some View {
        // Plain black like the rest of the tool surfaces: the logo and the Send button carry the brand.
        IslandCard(veil: nil) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.regular) {
                header
                account
                rule
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Memnox.Spacing.regular) {
                        content
                        if !draft.fields.isEmpty { fields }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
                footer
            }
            .padding(Layout.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(kindWord) on \(tool), waiting for you to send it")
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: Memnox.Spacing.medium) {
            ToolMark(toolkit: draft.toolkit, side: Layout.markSide)
            Text("\(kindWord) on \(tool)")
                .font(Memnox.sans(Memnox.TextSize.callout, .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
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
            .accessibilityLabel("Close without sending")
        }
    }

    /// Whose name it goes out under, and whether the workspace could tell that account is theirs.
    private var account: some View {
        let shown = draft.account?.shown
        let check = draft.account?.accountCheck ?? .unknown
        return HStack(spacing: Memnox.Spacing.small) {
            Text(shown.map { "As \($0)" } ?? "As you")
                .font(Memnox.sans(Memnox.TextSize.footnote, .medium))
                .foregroundStyle(Color.white.opacity(Memnox.Ink.primary))
            if check == .matched {
                Image(systemName: Symbol.matched).foregroundStyle(IslandPalette.green)
                    .accessibilityLabel("your account")
            } else {
                Label("not tied to you, check the name", systemImage: Symbol.unverified)
                    .foregroundStyle(IslandPalette.amber)
            }
        }
        .font(Memnox.sans(Memnox.TextSize.caption, .medium))
        .lineLimit(1)
    }

    private var rule: some View {
        Rectangle().fill(Color.white.opacity(Shade.rule)).frame(height: Memnox.Stroke.hairline)
    }

    private var footer: some View {
        HStack {
            Text("Nothing goes out until you send it.")
                .font(Memnox.sans(Memnox.TextSize.caption))
                .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
            Spacer()
            Button { answer(send: true) } label: {
                HStack(spacing: Memnox.Spacing.small) {
                    Image(systemName: Symbol.touchID)
                    Text(ToolBrand.sendLabel(draft.toolkit))
                }
                .font(Memnox.sans(Memnox.TextSize.callout, .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, Memnox.Spacing.xLarge)
                .padding(.vertical, Memnox.Spacing.medium)
                .background(Capsule().fill(ToolBrand.color(draft.toolkit)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(Memnox.Ink.edge)))
            }
            .buttonStyle(PressableStyle())
            .help("Send with Touch ID")
            .accessibilityLabel("\(ToolBrand.sendLabel(draft.toolkit)) on \(tool), with Touch ID")
        }
        .disabled(model.sending)
        .opacity(model.sending ? Shade.sending : 1)
    }

    // MARK: Each tool's own layout

    @ViewBuilder private var content: some View {
        switch draft.draftKind {
        case .message: message
        case .comment: comment
        case .email: email
        case .issue, .other: generic
        }
    }

    /// Slack: where it goes, then the message as it will sit in the channel, under their name.
    private var message: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            if let to = draft.to, !to.isEmpty { chips("To", to) }
            HStack(alignment: .top, spacing: Memnox.Spacing.regular) {
                avatar
                VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                    HStack(spacing: Memnox.Spacing.small) {
                        Text(draft.account?.shown ?? "You")
                            .font(Memnox.sans(Memnox.TextSize.body, .bold))
                            .foregroundStyle(Color.white)
                        Text("now")
                            .font(Memnox.sans(Memnox.TextSize.caption))
                            .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
                    }
                    bodyText
                }
            }
        }
    }

    /// GitHub and Linear: where it lands, then a comment box headed by who wrote it.
    private var comment: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            if let place = draft.where {
                Label(place, systemImage: Symbol.place)
                    .font(Memnox.mono(Memnox.TextSize.footnote, .medium))
                    .foregroundStyle(Color.white.opacity(Memnox.Ink.primary))
                    .lineLimit(1)
            }
            let shape = RoundedRectangle(cornerRadius: Layout.commentRadius, style: .continuous)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Memnox.Spacing.small) {
                    avatar.scaleEffect(0.6).frame(width: Layout.avatarSide * 0.6, height: Layout.avatarSide * 0.6)
                    Text(draft.account?.shown ?? "You").font(Memnox.sans(Memnox.TextSize.footnote, .bold))
                    Text("commenting").font(Memnox.sans(Memnox.TextSize.footnote))
                        .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, Memnox.Spacing.regular)
                .frame(height: Layout.rowHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(Shade.commentHeader))
                rule
                bodyText.padding(Memnox.Spacing.regular)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(Memnox.Ink.edge)))
        }
    }

    /// Gmail: recipients, subject, then the words.
    private var email: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            if let to = draft.to, !to.isEmpty { chips("To", to) }
            if let subject = draft.subject {
                Text(subject)
                    .font(Memnox.sans(Memnox.TextSize.callout, .semibold))
                    .foregroundStyle(Color.white)
            }
            rule
            bodyText
        }
    }

    /// Anything else: a title where there is one, then the words, with every argument listed below.
    private var generic: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            if let place = draft.where {
                Label(place, systemImage: Symbol.place)
                    .font(Memnox.mono(Memnox.TextSize.footnote, .medium))
                    .foregroundStyle(Color.white.opacity(Memnox.Ink.primary))
            }
            if let subject = draft.subject {
                Text(subject)
                    .font(Memnox.sans(Memnox.TextSize.callout, .semibold))
                    .foregroundStyle(Color.white)
            }
            if draft.body != nil { bodyText }
        }
    }

    // MARK: Parts

    private var avatar: some View {
        Text(String((draft.account?.shown ?? "You").prefix(1)).uppercased())
            .font(Memnox.sans(Memnox.TextSize.callout, .bold))
            .foregroundStyle(Color.white)
            .frame(width: Layout.avatarSide, height: Layout.avatarSide)
            .background(RoundedRectangle(cornerRadius: Memnox.radius, style: .continuous)
                .fill(ToolBrand.color(draft.toolkit)))
            .accessibilityHidden(true)
    }

    /// The words, with their bold, links and code drawn as the tool would draw them.
    private var bodyText: some View {
        Text(rendered(draft.body ?? ""))
            .font(Memnox.sans(Layout.bodySize))
            .lineSpacing(Layout.bodyLineSpacing)
            .foregroundStyle(Color.white.opacity(Memnox.Ink.primary))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func chips(_ label: String, _ people: [String]) -> some View {
        HStack(spacing: Memnox.Spacing.medium) {
            Text(label)
                .font(Memnox.sans(Memnox.TextSize.body))
                .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
            ForEach(people, id: \.self) { person in
                Text(person)
                    .font(Memnox.sans(Memnox.TextSize.body, .medium))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .padding(.horizontal, Memnox.Spacing.regular)
                    .padding(.vertical, Memnox.Spacing.xSmall)
                    .background(Capsule().fill(Color.white.opacity(Shade.chip)))
            }
        }
    }

    /// Every argument the layout did not show, so nothing is sent that the person did not see.
    private var fields: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
            Text("Also sends")
                .font(Memnox.sans(Memnox.TextSize.caption, .semibold))
                .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
            ForEach(draft.fields, id: \.name) { field in
                HStack(alignment: .firstTextBaseline, spacing: Memnox.Spacing.medium) {
                    Text(field.name)
                        .font(Memnox.mono(Memnox.TextSize.caption))
                        .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
                        .frame(width: Layout.fieldNameWidth, alignment: .leading)
                        .lineLimit(1)
                    Text(field.value)
                        .font(Memnox.mono(Memnox.TextSize.caption))
                        .foregroundStyle(Color.white.opacity(Memnox.Ink.primary))
                }
            }
        }
    }

    private var kindWord: String {
        switch draft.draftKind {
        case .message: return "Message"
        case .comment: return draft.toolkit == "github" ? "Review comment" : "Comment"
        case .email: return "Email"
        case .issue: return "Issue"
        case .other: return "Action"
        }
    }

    private func rendered(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private func answer(send: Bool) {
        model.sending = send
        model.answerWork(card, send)
    }
}
