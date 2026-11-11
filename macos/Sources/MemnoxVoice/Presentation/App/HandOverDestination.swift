import MemnoxVoiceCore
import SwiftUI

/// Hand over: the one action people keep saying yes to, offered as a rule that lets it run on its own. Budgets and
/// autopilot join it as tabs once this Mac's runtime answers them, so nothing here is a promise.
struct HandOverDestination: View {
    @ObservedObject var home: HomeModel
    let width: WidthClass

    var body: some View {
        ShellScroll(width: width) {
            if let ready = home.home?.ready {
                HandOverCard(ready: ready, busy: home.handingOver, note: home.handOverNote) { home.handOver(ready) }
            } else {
                EmptyState(symbol: "gauge.with.dots.needle.67percent", title: HomeBriefBlock.ready.title,
                           detail: HomeBriefBlock.ready.none)
            }
        }
    }
}

/// The question, what it would cover, and the button that proposes the rule, which holds once signed with Touch ID.
private struct HandOverCard: View {
    let ready: HomeReady
    let busy: Bool
    let note: String?
    let handOver: () -> Void

    var body: some View {
        ShellSection(title: HomeBriefBlock.ready.title) {
            ShellPanel {
                VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
                    Text(HomeLines.ready(ready))
                        .font(Memnox.Console.sans(Memnox.TextSize.headline, .semibold))
                        .foregroundStyle(Memnox.Console.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(ready.targets, id: \.self) { target in
                        Text(target)
                            .font(Memnox.Console.code(Memnox.TextSize.footnote))
                            .foregroundStyle(Memnox.Console.foreground)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Text(ready.because)
                        .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                        .foregroundStyle(Memnox.Console.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Memnox.Spacing.medium) {
                        Button(busy ? "Proposing the rule" : "Let it run on its own", action: handOver)
                            .buttonStyle(KitButton(kind: .primary))
                            .disabled(busy)
                            .help("Proposes an allow rule for exactly these; nothing changes until you confirm it with Touch ID")
                        if let note {
                            Text(note)
                                .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                                .foregroundStyle(Memnox.Console.muted)
                        }
                    }
                }
                .padding(SettingsMetrics.cardPadding)
            }
        }
    }
}
