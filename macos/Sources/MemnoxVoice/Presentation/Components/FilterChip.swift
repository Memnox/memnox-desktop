import SwiftUI

/// One choice in a row of chips: filled in the Memnox blue when chosen, an outline otherwise, with a count where one
/// helps. The same chip as the iPhone's session filter.
struct FilterChip: View {
    let title: String
    let chosen: Bool
    var count: Int?
    let choose: () -> Void
    @State private var hovering = false

    private static let height: CGFloat = 24
    /// The chosen chip's edge and wash, the console's blue at 45 and 7 percent.
    private static let chosenEdge = 0.45
    private static let chosenWash = 0.07

    var body: some View { console }

    /// The console's filter: 32 tall at radius 6, bordered, and the chosen one washed in its blue.
    private var console: some View {
        let shape = RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous)
        return Button(action: choose) {
            HStack(spacing: Memnox.Spacing.small) {
                Text(title)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, chosen ? .medium : .regular))
                if let count, count > 0 {
                    Text("\(count)")
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.meta, .medium).monospacedDigit())
                        .foregroundStyle(Memnox.Console.muted)
                }
            }
            .foregroundStyle(chosen ? Memnox.Console.foreground : Memnox.Console.muted)
            .padding(.horizontal, Memnox.Spacing.large)
            .frame(height: Memnox.Console.controlHeight)
            .background(shape.fill(chosen ? Memnox.Console.primary.opacity(Self.chosenWash) : hovering ? Memnox.Console.hover : Memnox.Console.card))
            .overlay(shape.strokeBorder(chosen ? Memnox.Console.primary.opacity(Self.chosenEdge) : Memnox.Console.panelEdge,
                                        lineWidth: Memnox.Stroke.hairline))
            .contentShape(shape)
            .animation(.easeOut(duration: Memnox.Motion.quick), value: hovering)
            .animation(.easeOut(duration: Memnox.Motion.quick), value: chosen)
        }
        .buttonStyle(PressDip())
        .onHover { hovering = $0 }
        .pointingHand()
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
