import AppKit
import MemnoxVoiceCore
import SwiftUI

/// One session on its own card, showing what it is doing the way the live window does: what it
/// is on this moment, the last words of its conversation, its latest steps and what it changed,
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
        static let taskLineLimit = 2
        static let metaSeparator = "  \u{00B7}  "
    }

    private enum Symbol {
        static let watch = "play.circle"
        static let open = "arrow.up.forward.app"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            CardHeader(title: model.view?.agentName ?? card.agentName, subtitle: meta, close: close) {
                BrandLogo(agent: model.view?.agent ?? card.agent, name: model.view?.agentName ?? card.agentName, size: FloatingCard.markSize)
            } accessory: {
                StatusTag(status: model.view?.status ?? card.status)
            }
            if let task = model.view?.task ?? card.task {
                Text(task)
                    .font(Memnox.sans(Memnox.TextSize.callout))
                    .foregroundStyle(Memnox.Palette.foreground.opacity(Memnox.Ink.primary))
                    .lineLimit(Layout.taskLineLimit)
            }
            if let view = model.view {
                LiveNow(view: view)
                let talk = Array((view.conversation ?? []).suffix(Layout.conversationLines))
                if !talk.isEmpty {
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
            } else if card.task == nil {
                Text("Nothing recorded for this session yet")
                    .font(Memnox.sans(Memnox.TextSize.callout))
                    .foregroundStyle(Memnox.Palette.muted)
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

    /// Where it works and how lately it did anything, the quiet line under the agent's name.
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
