import SwiftUI

/// One number at a glance, an overview card: what it counts with its symbol on top, the number beside a short bar in
/// its tint, and one quiet line saying what it means. The same widget as the iPhone's home.
struct StatTile: View {
    let value: Int
    let label: String
    let symbol: String
    let tint: Color
    var caption: String?

    private enum Layout {
        static let valueSize: CGFloat = 22
        static let barWidth: CGFloat = 3
        static let barHeight: CGFloat = 16
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
            Label(label, systemImage: symbol)
                .font(Memnox.sans(Memnox.TextSize.footnote, .semibold))
                .foregroundStyle(Memnox.ink(Memnox.Ink.primary))
                .lineLimit(1)
            HStack(spacing: Memnox.Spacing.small) {
                Capsule().fill(tint).frame(width: Layout.barWidth, height: Layout.barHeight)
                Text("\(value)")
                    .font(.system(size: Layout.valueSize, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Memnox.Palette.ink)
                    .contentTransition(.numericText(value: Double(value)))
            }
            if let caption {
                Text(caption)
                    .font(Memnox.sans(Memnox.TextSize.caption))
                    .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SurfaceStyle.padding)
        .surface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(value) \(label)"))
    }
}
