import MemnoxVoiceCore
import SwiftUI

/// A SKILL.md drawn the way its agent reads it: headings, lists, quotes, tables and code fences from the core's block
/// parser, and bold, italics, inline code and links inside each block from Foundation's own markdown reader.
struct SkillMarkdown: View {
    let blocks: [SkillBlock]

    private enum Layout {
        static let blockSpacing: CGFloat = 10
        static let listIndent: CGFloat = 16
        static let bulletWidth: CGFloat = 18
        static let quoteBar: CGFloat = 3
        static let codeRadius: CGFloat = 6
        static let lineSpacing: CGFloat = 3
        /// How far the code wash stands off the page, a little stronger in the dark.
        static let codeWash = 0.06
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.blockSpacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                draw(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder private func draw(_ block: SkillBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(Self.inline(text))
                .font(Memnox.Console.sans(Self.headingSize(level), .semibold))
                .foregroundStyle(Memnox.Console.foreground)
                .padding(.top, level <= 2 ? Memnox.Spacing.medium : Memnox.Spacing.xSmall)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            prose(text)
        case .item(let depth, let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: Memnox.Spacing.xSmall) {
                Text(number.map { "\($0)." } ?? "\u{2022}")
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall).monospacedDigit())
                    .foregroundStyle(Memnox.Console.muted)
                    .frame(width: Layout.bulletWidth, alignment: .leading)
                prose(text)
            }
            .padding(.leading, CGFloat(depth) * Layout.listIndent)
        case .code(_, let text):
            ScrollView(.horizontal) {
                Text(text)
                    .font(Memnox.Console.code(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Console.foreground)
                    .lineSpacing(Layout.lineSpacing)
                    .fixedSize()
                    .padding(Memnox.Spacing.regular)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Memnox.Console.foreground.opacity(Layout.codeWash),
                        in: RoundedRectangle(cornerRadius: Layout.codeRadius, style: .continuous))
        case .quote(let text):
            HStack(spacing: Memnox.Spacing.regular) {
                Rectangle().fill(Memnox.Console.border).frame(width: Layout.quoteBar)
                prose(text).foregroundStyle(Memnox.Console.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .table(let rows):
            table(rows)
        case .rule:
            ShellDivider()
        }
    }

    private func prose(_ text: String) -> some View {
        Text(Self.inline(text))
            .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
            .foregroundStyle(Memnox.Console.foreground)
            .lineSpacing(Layout.lineSpacing)
            .tint(Memnox.Console.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func table(_ rows: [[String]]) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Memnox.Spacing.xLarge, verticalSpacing: Memnox.Spacing.small) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(Self.inline(cell))
                            .font(Memnox.Console.sans(Memnox.Console.TextSize.meta, index == 0 ? .semibold : .regular))
                            .foregroundStyle(index == 0 ? Memnox.Console.foreground : Memnox.Console.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if index == 0 { ShellDivider().gridCellUnsizedAxes(.horizontal) }
            }
        }
    }

    private static func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: Memnox.Console.TextSize.large
        case 2: Memnox.Console.TextSize.base
        default: Memnox.Console.TextSize.bodySmall
        }
    }

    /// Bold, italics, inline code and links styled in place; text Foundation cannot read stays as written.
    private static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard var styled = try? AttributedString(markdown: text, options: options) else { return AttributedString(text) }
        for run in styled.runs where run.inlinePresentationIntent?.contains(.code) == true {
            styled[run.range].font = Memnox.Console.code(Memnox.TextSize.footnote)
        }
        return styled
    }
}
