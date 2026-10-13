import AppKit
import MemnoxVoiceCore
import SwiftUI

/// One session on its own card: what it is about in the person's own words, where and since when it
/// works, what it is on this moment, where the work stands, its latest steps and what it changed,
/// kept short so several fit on a screen and refreshed while it is up.
struct SessionPopupView: View {
    let card: SessionCard
    @ObservedObject var model: LiveModel
    let close: () -> Void
    let watch: () -> Void
    let open: (() -> Void)?
    let hovering: (Bool) -> Void
    @StateObject private var entrance = CardEntrance()

    /// How much of the session the card holds, kept short so several cards fit on a screen.
    private enum Layout {
        static let conversationLines = 2
        static let conversationLineLimit = 3
        static let steps = 3
        static let files = 3
        static let taskLineLimit = 3
        static let lastAskLineLimit = 2
        static let contextLineLimit = 2
        static let lastSaidLineLimit = 4
        static let metaSeparator = "  \u{00B7}  "
    }

    private enum Symbol {
        static let watch = "play.circle"
        static let open = "arrow.up.forward.app"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            CardHeader(title: model.view?.agentName ?? card.agentName, subtitle: model.view?.place ?? card.repository, close: close) {
                BrandLogo(agent: model.view?.agent ?? card.agent, name: model.view?.agentName ?? card.agentName, size: FloatingCard.markSize)
            } accessory: {
                StatusTag(status: model.view?.status ?? card.status)
            }
            about
            if let view = model.view {
                LiveNow(view: view)
                let talk = Array((view.conversation ?? []).suffix(Layout.conversationLines))
                if let said = view.lastSaid {
                    LiveSection(title: "Where it stands") {
                        Text(said)
                            .font(Memnox.sans(Memnox.TextSize.callout))
                            .foregroundStyle(Memnox.Palette.foreground.opacity(Memnox.Ink.primary))
                            .lineLimit(Layout.lastSaidLineLimit)
                    }
                } else if !talk.isEmpty {
                    LiveSection(title: "Conversation") {
                        VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
                            ForEach(Array(talk.enumerated()), id: \.offset) { _, line in
                                ConversationRow(line: line, typing: false).lineLimit(Layout.conversationLineLimit)
                            }
                        }
                    }
                }
                if !view.steps.isEmpty { LiveSteps(steps: view.steps, most: Layout.steps) }
                if !view.files.isEmpty {
                    LiveSection(title: "Changed") {
                        FileList(files: Array(view.files.prefix(Layout.files)), counting: entrance.shown)
                    }
                }
            }
            HStack(spacing: Memnox.Spacing.medium) {
                Spacer()
                // One primary action per card: opening its window when it has one, watching it otherwise.
                CardButton(title: "Watch live", icon: Symbol.watch, primary: open == nil, action: watch)
                if let open {
                    CardButton(title: card.host?.app.map { "Open in \($0)" } ?? "Open its window", icon: Symbol.open, primary: true, action: open)
                }
            }
        }
        .modifier(CardFace(entrance: entrance, hovering: hovering))
    }

    /// What the session is about: the task or the person's first request, what they asked last, and where and since when it runs.
    private var about: some View {
        LiveSection(title: "About") {
            VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
                if let task = model.view?.task ?? card.task {
                    Text(task)
                        .font(Memnox.sans(Memnox.TextSize.callout, .medium))
                        .foregroundStyle(Memnox.Palette.foreground.opacity(Memnox.Ink.primary))
                        .lineLimit(Layout.taskLineLimit)
                } else {
                    Text("No request recorded for this session yet")
                        .font(Memnox.sans(Memnox.TextSize.callout))
                        .foregroundStyle(Memnox.Palette.muted)
                }
                if let lastAsk = model.view?.lastAsk {
                    Text("Latest ask: \(lastAsk)")
                        .font(Memnox.sans(Memnox.TextSize.footnote))
                        .foregroundStyle(Memnox.Palette.foreground.opacity(Memnox.Ink.secondary))
                        .lineLimit(Layout.lastAskLineLimit)
                }
                if let context = model.view?.context(now: Date()) ?? meta {
                    Text(context)
                        .font(Memnox.sans(Memnox.TextSize.caption))
                        .foregroundStyle(Memnox.Palette.muted)
                        .lineLimit(Layout.contextLineLimit)
                }
            }
        }
    }

    /// Where it works and how lately it did anything, from the list alone before the session itself is read.
    private var meta: String? {
        let repository = model.view?.repository ?? card.repository
        let runningIn = model.view?.runningIn ?? card.runningIn
        let active = SessionText.ago(model.view?.lastActive ?? card.lastActive, now: Date()).map { "active \($0)" }
        let parts = [repository, runningIn, active].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: Layout.metaSeparator)
    }
}

/// How the session stands, as a dot and a word in the status colour, so it reads before the details.
private struct StatusTag: View {
    let status: SessionStatus

    private static let dot: CGFloat = 7

    var body: some View {
        HStack(spacing: Memnox.Spacing.small) {
            Circle().fill(status.tint).frame(width: Self.dot, height: Self.dot)
            Text(status.label).font(Memnox.sans(Memnox.TextSize.caption, .medium))
        }
        .foregroundStyle(status.tint)
        .accessibilityElement(children: .combine)
    }
}
