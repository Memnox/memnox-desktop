import AppKit
import MemnoxVoiceCore
import SwiftUI

/// A trace, the way Logfire draws one: each step indented under what it ran inside, with a bar on
/// the trace's own clock, green when it went well, red when it failed, amber when it was refused.
struct TraceView: View {
    let trace: TraceData
    let title: String
    let close: () -> Void
    let hovering: (Bool) -> Void
    @StateObject private var entrance = CardEntrance()
    private static let track: CGFloat = 170

    private enum Layout {
        static let logoSize: CGFloat = 16
        static let titleSize: CGFloat = 22
        /// The bars grow in after the card has begun to swing in, one row a beat after the last.
        static let barDelay: TimeInterval = 0.25
        static let barStagger: TimeInterval = 0.05
        static let barResponse = 0.6
        static let barDamping = 0.85
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            HStack(alignment: .firstTextBaseline) {
                LogoMark(size: Layout.logoSize)
                Text(title)
                    .font(Memnox.display(Layout.titleSize))
                    .foregroundStyle(Memnox.Palette.foreground)
                    .lineLimit(1)
                Spacer()
                Text(SessionText.duration(milliseconds: trace.totalMs))
                    .font(.system(size: Memnox.TextSize.body, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Memnox.Palette.primary)
                CloseButton(action: close)
            }
            VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
                ForEach(Array(trace.rows.enumerated()), id: \.offset) { index, row in
                    TraceRow(row: row, total: max(trace.totalMs, 1), track: Self.track, shown: entrance.shown)
                        .animation(
                            .spring(response: Layout.barResponse, dampingFraction: Layout.barDamping)
                                .delay(Layout.barDelay + Double(index) * Layout.barStagger),
                            value: entrance.shown
                        )
                }
            }
        }
        .modifier(CardFace(entrance: entrance, hovering: hovering))
    }
}

struct TraceRow: View {
    let row: TraceData.Row
    let total: Double
    let track: CGFloat
    let shown: Bool

    /// The statuses a step is drawn apart for; any other is a step that went well.
    private enum Status: String {
        case error
        case refused
    }

    private enum Layout {
        static let nestedOpacity = 0.85
        /// Deeper steps stop indenting here, so a long chain still leaves room for its name.
        static let deepestIndent = 4
        static let indentStep: CGFloat = 12
        static let nameWidth: CGFloat = 150
        static let barHeight: CGFloat = 6
        /// Even an instant step keeps a bar wide enough to see.
        static let shortestBar: CGFloat = 3
        static let durationWidth: CGFloat = 52
    }

    var body: some View {
        HStack(spacing: Memnox.Spacing.regular) {
            Text(SessionText.traceStepName(row.name))
                .font(Memnox.sans(Memnox.TextSize.footnote, row.depth == 0 ? .semibold : .regular))
                .foregroundStyle(Memnox.Palette.foreground.opacity(row.depth == 0 ? 1 : Layout.nestedOpacity))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, CGFloat(min(row.depth, Layout.deepestIndent)) * Layout.indentStep)
                .frame(width: Layout.nameWidth, alignment: .leading)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(Memnox.Ink.faintFill)).frame(width: track, height: Layout.barHeight)
                Capsule()
                    .fill(colour)
                    .frame(width: shown ? max(Layout.shortestBar, track * row.durationMs / total) : 0, height: Layout.barHeight)
                    .offset(x: track * row.offsetMs / total)
            }
            .frame(width: track, alignment: .leading)
            Text(SessionText.duration(milliseconds: row.durationMs))
                .font(.system(size: Memnox.TextSize.caption, design: .monospaced))
                .foregroundStyle(Memnox.Palette.muted)
                .frame(width: Layout.durationWidth, alignment: .trailing)
        }
    }

    private var colour: Color {
        switch Status(rawValue: row.status) {
        case .error: return Memnox.Palette.destructive
        case .refused: return Memnox.Palette.warm
        case nil: return row.depth == 0 ? Memnox.Palette.primary : Memnox.Palette.success
        }
    }
}
