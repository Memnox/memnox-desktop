import MemnoxVoiceCore
import SwiftUI

/// The apps Memnox can work in for the person, offered on the last step of setup with Connect beside each, so the first
/// thing they ask of it can already happen in their own Gmail or Slack.
struct SuggestedApps: View {
    @ObservedObject var tools: ToolsModel

    /// Enough to show the range without turning the last step into a catalogue; the rest are in Settings.
    private static let shown = 6

    var body: some View {
        KitCard(symbol: "square.grid.2x2", title: "Your apps", detail: "Optional. Memnox works in them as you, and asks before anything goes out.") {
            ForEach(Array(tools.suggested.prefix(Self.shown)), id: \.self) { toolkit in
                if toolkit != tools.suggested.first { KitDivider() }
                KitRow(title: ToolkitName.of(toolkit), detail: tools.waitingFor == toolkit ? "Finish signing in in your browser" : nil,
                       leading: { ToolMark(toolkit: toolkit, side: SettingsMetrics.tileSide) }) {
                    HStack(spacing: Memnox.Spacing.medium) {
                        if tools.busy == toolkit { ProgressView().controlSize(.small) }
                        Button("Connect") { tools.connect(toolkit) }
                            .buttonStyle(KitButton(kind: .secondary))
                            .disabled(tools.busy != nil)
                    }
                }
            }
            if let why = tools.actionNote {
                Text(why)
                    .font(Memnox.sans(Memnox.TextSize.caption))
                    .foregroundStyle(Memnox.Palette.warm)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { tools.refresh() }
    }
}
