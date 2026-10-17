import SwiftUI

/// One choice in a row of chips: filled in the Memnox blue when chosen, an outline otherwise, with a count where one
/// helps. The same chip as the iPhone's session filter.
struct FilterChip: View {
    let title: String
    let chosen: Bool
    var count: Int?
    let choose: () -> Void

    private static let height: CGFloat = 24

    var body: some View {
        Button(action: choose) {
            HStack(spacing: Memnox.Spacing.xSmall) {
                Text(title)
                    .font(Memnox.sans(Memnox.TextSize.caption, chosen ? .semibold : .medium))
                if let count, count > 0 {
                    Text("\(count)")
                        .font(Memnox.sans(Memnox.TextSize.micro, .semibold).monospacedDigit())
                        .foregroundStyle(Memnox.ink(chosen ? Memnox.Ink.primary : Memnox.Ink.tertiary))
                }
            }
            .foregroundStyle(chosen ? IslandPalette.primaryText : Memnox.Palette.ink)
            .padding(.horizontal, Memnox.Spacing.regular)
            .frame(height: Self.height)
            .background(Capsule().fill(chosen ? IslandPalette.primaryFill : Memnox.ink(Memnox.Ink.faintFill)))
            .overlay(Capsule().strokeBorder(chosen ? Color.clear : Memnox.ink(Memnox.Ink.edge), lineWidth: Memnox.Stroke.hairline))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHand()
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
