import MemnoxVoiceCore
import SwiftUI

/// A card's markdown laid out as written: headings, bullets and code blocks, with backticks, bold
/// and links rendered inside each line, so the card shows exactly what the session did.
struct MarkdownText: View {
    let source: String

    private enum Layout {
        /// Between a bullet and its line.
        static let bulletGap: CGFloat = 7
        static let bulletLineSpacing: CGFloat = 2
        /// The monospaced size of a code block, two points under a paragraph.
        static let codeTextSize: CGFloat = 11.5
        /// The dark shade behind a code block that sets it apart from the text around it.
        static let codeShadeOpacity = 0.28
        /// Between the body and callout sizes, so a paragraph reads a touch above a bullet.
        static let paragraphTextSize: CGFloat = 13.5
        static let paragraphLineSpacing: CGFloat = 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
            ForEach(Array(MarkdownBlock.parse(source).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .foregroundStyle(Memnox.Palette.foreground.opacity(Memnox.Ink.primary))
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let line):
            Text(Self.inline(line))
                .font(Memnox.sans(Memnox.TextSize.headline, .semibold))
                .foregroundStyle(Memnox.Palette.foreground)
                .padding(.top, Memnox.Spacing.xxSmall)
        case .bullet(let line):
            HStack(alignment: .firstTextBaseline, spacing: Layout.bulletGap) {
                Text("•").font(Memnox.sans(Memnox.TextSize.body, .semibold)).foregroundStyle(Memnox.Palette.primary)
                Text(Self.inline(line)).font(Memnox.sans(Memnox.TextSize.body)).lineSpacing(Layout.bulletLineSpacing)
            }
        case .code(let code):
            Text(code)
                .font(.system(size: Layout.codeTextSize, design: .monospaced))
                .padding(Memnox.Spacing.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Memnox.radius).fill(Color.black.opacity(Layout.codeShadeOpacity)))
        case .text(let line):
            Text(Self.inline(line)).font(Memnox.sans(Layout.paragraphTextSize)).lineSpacing(Layout.paragraphLineSpacing)
        }
    }

    /// Inline marks only, since the blocks were already cut; a line that will not parse shows as typed.
    private static func inline(_ line: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: line, options: options)) ?? AttributedString(line)
    }
}
