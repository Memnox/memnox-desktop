import MemnoxVoiceCore
import SwiftUI

/// The categories down a page's side with their counts, as the console's Connected tools page draws them: a heading,
/// an All row, then each category, the chosen one on the active fill.
struct CategoryRail: View {
    let heading: String
    let allTitle: String
    let total: Int
    let categories: [(id: String, title: String, count: Int)]
    /// Nil while All is chosen.
    let chosen: String?
    let choose: (String?) -> Void

    enum Layout {
        static let width: CGFloat = 200
        static let rowSpacing: CGFloat = 2
        static let rowPadH: CGFloat = 10
        static let rowPadV: CGFloat = 6
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.rowSpacing) {
            Text(heading)
                .textCase(.uppercase)
                .font(Memnox.Console.code(Memnox.Console.TextSize.meta))
                .tracking(Memnox.Console.headingTracking)
                .foregroundStyle(Memnox.Console.muted)
                .padding(.horizontal, Layout.rowPadH)
                .padding(.bottom, Memnox.Spacing.small)
            row(title: allTitle, count: total, on: chosen == nil) { choose(nil) }
            ForEach(categories, id: \.id) { each in
                row(title: each.title, count: each.count, on: chosen == each.id) { choose(each.id) }
            }
        }
        .frame(width: Layout.width, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(heading)
    }

    private func row(title: String, count: Int, on: Bool, choose: @escaping () -> Void) -> some View {
        Button(action: choose) {
            HStack(spacing: Memnox.Spacing.small) {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Memnox.Spacing.small)
                Text("\(count)")
                    .font(Memnox.Console.code(Memnox.Console.TextSize.meta).monospacedDigit())
                    .foregroundStyle(Memnox.Console.faint)
            }
            .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, on ? .medium : .regular))
            .foregroundStyle(on ? Memnox.Console.foreground : Memnox.Console.muted)
            .padding(.horizontal, Layout.rowPadH)
            .padding(.vertical, Layout.rowPadV)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? Memnox.Console.active : Color.clear,
                        in: RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHand()
        .accessibilityLabel("\(title), \(count)")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}

/// The page's pending changes gathered in one bar at its foot: how many, Undo, and the one way on to review and save.
struct ChangesBar: View {
    let count: String
    let busy: Bool
    let undo: () -> Void
    let review: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous)
        HStack(spacing: Memnox.Spacing.medium) {
            Circle().fill(Memnox.Console.primary).frame(width: ShellMetrics.dot, height: ShellMetrics.dot).accessibilityHidden(true)
            Text(count)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                .foregroundStyle(Memnox.Console.foreground)
                .contentTransition(.numericText())
            Text(ProtectionLines.notSaved)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
                .foregroundStyle(Memnox.Console.muted)
            Spacer(minLength: Memnox.Spacing.medium)
            Button(ProtectionLines.undo, systemImage: "arrow.uturn.backward", action: undo)
                .buttonStyle(KitButton(kind: .secondary))
                .disabled(busy)
            Button(ProtectionLines.review, action: review)
                .buttonStyle(KitButton(kind: .primary))
                .disabled(busy)
        }
        .padding(.horizontal, Memnox.Spacing.xLarge)
        .padding(.vertical, Memnox.Spacing.medium)
        .background(Memnox.Console.card, in: shape)
        .overlay(shape.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
        .shadow(color: .black.opacity(Self.shadow), radius: Memnox.Spacing.large, y: Memnox.Spacing.xSmall)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(count), \(ProtectionLines.notSaved.lowercased())")
    }

    /// Faint enough to lift the bar off the page without a hard edge.
    private static let shadow = 0.12
}
