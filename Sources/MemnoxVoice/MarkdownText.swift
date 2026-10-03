import MemnoxVoiceCore
import SwiftUI

/// A card's markdown laid out as written: headings, bullets and code blocks, with backticks, bold
/// and links rendered inside each line, so the card shows exactly what the session did.
struct MarkdownText: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(MarkdownBlock.parse(source).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .foregroundStyle(Memnox.Palette.foreground.opacity(0.92))
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let line):
            Text(Self.inline(line))
                .font(Memnox.sans(15, .semibold))
                .foregroundStyle(Memnox.Palette.foreground)
                .padding(.top, 2)
        case .bullet(let line):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("•").font(Memnox.sans(13, .semibold)).foregroundStyle(Memnox.Palette.primary)
                Text(Self.inline(line)).font(Memnox.sans(13)).lineSpacing(2)
            }
        case .code(let code):
            Text(code)
                .font(.system(size: 11.5, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.28)))
        case .text(let line):
            Text(Self.inline(line)).font(Memnox.sans(13.5)).lineSpacing(3)
        }
    }

    /// Inline marks only, since the blocks were already cut; a line that will not parse shows as typed.
    private static func inline(_ line: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: line, options: options)) ?? AttributedString(line)
    }
}
