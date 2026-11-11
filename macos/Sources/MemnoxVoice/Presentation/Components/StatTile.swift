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
        static let consolePadding: CGFloat = 16
        static let consoleSpacing: CGFloat = 16
    }

    /// The console's stat card: what it counts above with its tinted icon, the number large under it.
    var body: some View {
        VStack(alignment: .leading, spacing: Layout.consoleSpacing) {
            HStack(spacing: Memnox.Spacing.medium) {
                Text(label)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                    .foregroundStyle(Memnox.Console.foreground)
                    .lineLimit(1)
                Spacer(minLength: Memnox.Spacing.small)
                IconTile(symbol: symbol, tint: tint)
            }
            VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                Text("\(value)")
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.title, .semibold).monospacedDigit())
                    .tracking(Memnox.Console.titleTracking)
                    .foregroundStyle(Memnox.Console.foreground)
                    .contentTransition(.numericText(value: Double(value)))
                if let caption {
                    Text(caption)
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                        .foregroundStyle(Memnox.Console.muted)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Layout.consolePadding)
        .surface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(value) \(label)"))
    }
}
