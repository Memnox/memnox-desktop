import MemnoxVoiceCore
import SwiftUI

/// One tool's card in the console's connector look: its logo, its name with the support pill and a Recommended pill,
/// its kind, two lines of the provider's own words, where it stands in its colour, and its buttons at the foot.
struct YourAppTile: View {
    let card: YourAppCard
    /// True for one of the tools the cloud puts first, which wears the Recommended pill.
    let recommended: Bool
    let busy: Bool
    let waiting: Bool
    let disabled: Bool
    /// True while connecting waits on a Memnox Cloud sign in, so Connect says it signs in first.
    let signInFirst: Bool
    /// What did not work on this app, said on its own card until the person closes it or presses again.
    let note: YourAppNote?
    let connect: () -> Void
    /// A fresh sign in on an app already working, so it runs as another of the person's accounts.
    let anotherAccount: () -> Void
    let disconnect: () -> Void
    let dismissNote: () -> Void

    private enum Layout {
        static let markSide: CGFloat = 40
        static let padding: CGFloat = 20
        static let headingSpacing: CGFloat = 12
        static let nameLines = 2
        static let descriptionLines = 2
        static let pillPadH: CGFloat = 8
        static let pillPadV: CGFloat = 2
        /// The pill's blue edge and wash, as the console draws its Fully supported badge.
        static let pillEdge = 0.4
        static let pillWash = 0.1
    }

    private static let waitingLine = "Finish signing in in your browser"

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            heading
            if let words = card.description {
                Text(words)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                    .foregroundStyle(Memnox.Console.muted)
                    .lineLimit(Layout.descriptionLines)
                    .fixedSize(horizontal: false, vertical: true)
            }
            status
            if let agents = card.agentsLine(name: McpHubLines.agentLabel) {
                HStack(alignment: .top, spacing: Memnox.Spacing.small) {
                    NamedAgentLogos(agents: card.uses.map(\.agent))
                    Text(agents)
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                        .foregroundStyle(Memnox.Console.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if let note { YourAppNoteView(note: note, dismiss: dismissNote) }
            foot
        }
        .padding(Layout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Memnox.Console.card, in: shape)
        .overlay(shape.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
        .accessibilityElement(children: .contain)
    }

    private var heading: some View {
        HStack(alignment: .top, spacing: Layout.headingSpacing) {
            ToolMark(toolkit: card.slug, side: Layout.markSide)
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                Text(card.name)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .semibold))
                    .foregroundStyle(Memnox.Console.foreground)
                    .lineLimit(Layout.nameLines)
                    .fixedSize(horizontal: false, vertical: true)
                if card.supportPill != nil || recommended || card.orderChip != nil {
                    HStack(spacing: Memnox.Spacing.xxSmall) {
                        if let support = card.supportPill { supportPill(support) }
                        if recommended { pill }
                        if let order = card.orderChip { orderPill(order) }
                    }
                }
                Text(reach)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                    .foregroundStyle(Memnox.Console.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var pill: some View {
        Text("Recommended")
            .font(Memnox.Console.sans(Memnox.Console.TextSize.label, .medium))
            .foregroundStyle(Memnox.Console.primary)
            .padding(.horizontal, Layout.pillPadH)
            .padding(.vertical, Layout.pillPadV)
            .background(Memnox.Console.primary.opacity(Layout.pillWash), in: Capsule())
            .overlay(Capsule().strokeBorder(Memnox.Console.primary.opacity(Layout.pillEdge), lineWidth: Memnox.Stroke.hairline))
            .fixedSize()
    }

    /// Where the connector comes from and the weight the search sorted it by, a plain edge so it never reads as a status.
    private func orderPill(_ words: String) -> some View {
        Text(words)
            .font(Memnox.Console.sans(Memnox.Console.TextSize.label, .medium))
            .foregroundStyle(Memnox.Console.muted)
            .padding(.horizontal, Layout.pillPadH)
            .padding(.vertical, Layout.pillPadV)
            .overlay(Capsule().strokeBorder(Memnox.Console.border, lineWidth: Memnox.Stroke.hairline))
            .fixedSize()
            .accessibilityLabel("Source \(words)")
    }

    /// The console's pill for how fully the cloud reads it: blue when fully, a plain edge when limited.
    private func supportPill(_ words: String) -> some View {
        let full = card.support == .full
        return Text(words)
            .font(Memnox.Console.sans(Memnox.Console.TextSize.label, .medium))
            .foregroundStyle(full ? Memnox.Console.primary : Memnox.Console.muted)
            .padding(.horizontal, Layout.pillPadH)
            .padding(.vertical, Layout.pillPadV)
            .background(full ? Memnox.Console.primary.opacity(Layout.pillWash) : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(full ? Memnox.Console.primary.opacity(Layout.pillEdge) : Memnox.Console.border,
                                            lineWidth: Memnox.Stroke.hairline))
            .fixedSize()
    }

    /// The line under the name: the cloud's kind for it where it said one, else how the tool is reached.
    private var reach: String {
        if card.standing == .onThisMac { return "Reached from this Mac itself" }
        return card.kindLine ?? "Your own account"
    }

    private var status: some View {
        HStack(spacing: Memnox.Spacing.small) {
            Circle().fill(tone.dot).frame(width: ShellMetrics.dot, height: ShellMetrics.dot)
            Text(statusLine)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.meta, .medium))
                .foregroundStyle(tone.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusLine: String {
        waiting ? Self.waitingLine : card.statusLine
    }

    private var tone: Tone {
        if waiting { return .attention }
        switch card.standing {
        case .onThisMac, .connected: return .good
        case .signInAgain: return .attention
        case .available: return .quiet
        }
    }

    @ViewBuilder private var foot: some View {
        HStack(spacing: Memnox.Spacing.medium) {
            switch card.standing {
            case .onThisMac:
                Text("Your agents reach it here, so there is nothing to connect.")
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                    .foregroundStyle(Memnox.Console.faint)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: Memnox.Console.controlHeight, alignment: .leading)
            case .connected:
                Button("Disconnect", action: disconnect)
                    .buttonStyle(KitButton(kind: .secondary))
                    .disabled(disabled)
                    .accessibilityLabel("Disconnect \(card.name)")
                Button(YourAppPress.anotherAccountButton, action: anotherAccount)
                    .buttonStyle(.plain)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                    .foregroundStyle(Memnox.Console.muted)
                    .pointingHand()
                    .disabled(disabled)
                    .accessibilityLabel("Sign in to \(card.name) with another account")
            case .signInAgain:
                Button("Sign in again", action: connect)
                    .buttonStyle(KitButton(kind: .primary, wide: true))
                    .disabled(disabled)
                    .accessibilityLabel("Sign in to \(card.name) again")
                Button("Disconnect", action: disconnect)
                    .buttonStyle(KitButton(kind: .secondary))
                    .disabled(disabled)
                    .accessibilityLabel("Disconnect \(card.name)")
            case .available:
                Button(signInFirst ? YourApps.signInButton : "Connect", action: connect)
                    .buttonStyle(KitButton(kind: .primary, wide: true))
                    .disabled(disabled)
                    .accessibilityLabel(signInFirst ? "\(YourApps.signInTitle) \(card.name)" : "Connect \(card.name)")
            }
            if busy { ProgressView().controlSize(.small) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A note that something did not work, inline where it happened: the warm mark, what did not happen, the daemon's
/// words, and a close button, so it never stands over the page once the person has read it.
struct YourAppNoteView: View {
    let note: YourAppNote
    let dismiss: () -> Void

    private enum Layout {
        static let padding: CGFloat = 12
        /// The warm wash and edge, light enough that the note reads as a word beside the card rather than an alarm.
        static let wash = 0.08
        static let edge = 0.35
    }

    private static let symbol = "exclamationmark.circle"
    private static let closeSymbol = "xmark"

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous)
        HStack(alignment: .top, spacing: Memnox.Spacing.medium) {
            Image(systemName: Self.symbol)
                .foregroundStyle(Memnox.Console.warm)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                Text(note.title)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta, .semibold))
                    .foregroundStyle(Memnox.Console.foreground)
                Text(note.words)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                    .foregroundStyle(Memnox.Console.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: Self.closeSymbol)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.label, .semibold))
                    .foregroundStyle(Memnox.Console.muted)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHand()
            .accessibilityLabel("Close")
        }
        .padding(Layout.padding)
        .background(Memnox.Console.warm.opacity(Layout.wash), in: shape)
        .overlay(shape.strokeBorder(Memnox.Console.warm.opacity(Layout.edge), lineWidth: Memnox.Stroke.hairline))
        .accessibilityElement(children: .contain)
    }
}
