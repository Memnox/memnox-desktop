import MemnoxVoiceCore
import SwiftUI

/// The pieces Today draws its tables from: a header of muted column names, a state worn as a mark
/// beside its word, and tabs that carry their counts.
enum WorkTable {
    static let numberWidth: CGFloat = 28
    static let fromWidth: CGFloat = 170
    static let whenWidth: CGFloat = 72
    static let stateWidth: CGFloat = 118
    static let whereWidth: CGFloat = 110
    static let engineWidth: CGFloat = 140
    static let asksWidth: CGFloat = 64
    static let wayWidth: CGFloat = 150
    static let logo: CGFloat = 20
    static let markSize: CGFloat = 11
    static let headHeight: CGFloat = 34
}

/// One column's name and width; a nil width takes what is left.
struct WorkColumn: Identifiable {
    let title: String
    let width: CGFloat?
    var id: String { title }
}

/// The table's head: each column's name, small and muted, over a hairline.
struct WorkTableHead: View {
    let columns: [WorkColumn]

    var body: some View {
        HStack(spacing: Memnox.Spacing.large) {
            ForEach(columns) { column in
                Text(column.title)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.label, .medium))
                    .foregroundStyle(Memnox.Console.faint)
                    .lineLimit(1)
                    .frame(width: column.width, alignment: .leading)
                    .frame(maxWidth: column.width == nil ? .infinity : nil, alignment: .leading)
            }
        }
        .padding(.horizontal, ShellMetrics.rowPaddingH)
        .frame(height: WorkTable.headHeight)
        .overlay(alignment: .bottom) { ShellDivider() }
        .accessibilityHidden(true)
    }
}

/// A state as a mark in its colour beside its word, so the colour is never all that says it.
struct StateMark: View {
    let symbol: String
    let tone: Tone
    let text: String

    var body: some View {
        HStack(spacing: Memnox.Spacing.small) {
            Image(systemName: symbol)
                .font(.system(size: WorkTable.markSize, weight: .semibold))
                .foregroundStyle(tone.color)
                .accessibilityHidden(true)
            Text(text)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.meta, .medium))
                .foregroundStyle(Memnox.Console.foreground)
                .lineLimit(1)
        }
    }

    init(_ state: TodayState) {
        switch state {
        case .needsYou: (symbol, tone) = ("exclamationmark.triangle.fill", .attention)
        case .stopped: (symbol, tone) = ("xmark.circle.fill", .bad)
        case .working: (symbol, tone) = ("circle.dotted", .good)
        case .upNext: (symbol, tone) = ("arrow.right.circle", .quiet)
        case .done: (symbol, tone) = ("checkmark.circle.fill", .good)
        }
        text = state.label
    }
}

/// Tabs across a page, each word with its count, the chosen one over a blue rule as the inspector's tabs are.
struct CountTabs<ID: Hashable>: View {
    let tabs: [(id: ID, title: String, count: Int)]
    let chosen: ID
    let choose: (ID) -> Void

    private static var underline: CGFloat { 2 }
    private static var padH: CGFloat { 12 }
    private static var padV: CGFloat { 10 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.id) { tab in
                let on = tab.id == chosen
                Button { choose(tab.id) } label: {
                    HStack(spacing: Memnox.Spacing.small) {
                        Text(tab.title)
                            .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                            .foregroundStyle(on ? Memnox.Console.foreground : Memnox.Console.muted)
                        Text("\(tab.count)")
                            .font(Memnox.Console.code(Memnox.Console.TextSize.label, .medium))
                            .foregroundStyle(Memnox.Console.faint)
                    }
                    .padding(.horizontal, Self.padH)
                    .padding(.vertical, Self.padV)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(on ? Memnox.Console.primary : Color.clear).frame(height: Self.underline)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHand()
                .accessibilityLabel("\(tab.title), \(tab.count)")
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) { ShellDivider() }
    }
}

/// A strip of short facts in one bordered row, as the console heads a table with what it covers.
struct WorkStrip<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous)
        HStack(spacing: Memnox.Spacing.large) { content }
            .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
            .foregroundStyle(Memnox.Console.muted)
            .padding(.horizontal, ShellMetrics.rowPaddingH)
            .padding(.vertical, Memnox.Spacing.regular)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Memnox.Console.hover, in: shape)
            .overlay(shape.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
    }
}
