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
        static let titleSize: CGFloat = 22
        static let taskOpacity = 0.75
        static let taskLineLimit = 2
    }

    private enum Symbol {
        static let watch = "play.circle"
        static let open = "arrow.up.forward.app"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            if let view = model.view {
                LiveHeader(view: view, close: close)
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
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(card.agentName)
                        .font(Memnox.display(Layout.titleSize))
                        .foregroundStyle(Memnox.Palette.foreground)
                    Spacer()
                    CloseButton(action: close)
                }
                Text(card.task ?? "Nothing recorded for this session yet")
                    .font(Memnox.sans(Memnox.TextSize.callout))
                    .foregroundStyle(Memnox.Palette.foreground.opacity(Layout.taskOpacity))
                    .lineLimit(Layout.taskLineLimit)
            }
            HStack(spacing: Memnox.Spacing.medium) {
                Spacer()
                CardButton(title: "Watch live", icon: Symbol.watch, primary: open == nil, action: watch)
                if let open {
                    CardButton(title: card.host?.app.map { "Open in \($0)" } ?? "Open its window", icon: Symbol.open, primary: true, action: open)
                }
            }
        }
        .modifier(CardFace(entrance: entrance, hovering: hovering))
    }
}
