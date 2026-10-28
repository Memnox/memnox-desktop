import AppKit
import MemnoxVoiceCore
import SwiftUI

/// A block of code somebody reads and copies, as the console draws one: a bar naming the file with Copy at its end,
/// then the code in DM Mono, coloured per token, scrolling sideways rather than wrapping a line the reader must
/// recognise whole. Only TOML is coloured today, the one language a page shows.
struct CodeBlock: View {
    let code: String
    /// What the block is, in its bar: a file name or a step.
    let label: String
    /// The tallest the code grows before it scrolls, nil to show it whole.
    var maxHeight: CGFloat?

    @State private var copied = false
    @State private var hoveringCopy = false

    private enum Layout {
        static let barHeight: CGFloat = 40
        static let codeSize: CGFloat = 12.5
        static let lineSpacing: CGFloat = 6
        static let copyIcon: CGFloat = 11
        static let copyHeight: CGFloat = 26
    }

    /// How long Copied stands before the button reads Copy again, long enough to be seen and no longer.
    private static let copiedFor: TimeInterval = 1.6

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous)
        VStack(spacing: 0) {
            bar
            Rectangle().fill(Memnox.Console.border).frame(height: Memnox.Stroke.hairline)
            ScrollView([.horizontal, .vertical]) {
                Text(highlighted)
                    .font(Memnox.Console.code(Layout.codeSize))
                    .lineSpacing(Layout.lineSpacing)
                    .textSelection(.enabled)
                    .fixedSize()
                    .padding(Memnox.Spacing.xLarge)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: maxHeight)
            .fixedSize(horizontal: false, vertical: maxHeight == nil)
        }
        .background(Memnox.Console.background, in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Memnox.Console.border, lineWidth: Memnox.Stroke.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private var bar: some View {
        HStack(spacing: Memnox.Spacing.medium) {
            Text(label)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.meta, .medium))
                .foregroundStyle(Memnox.Console.muted)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Memnox.Spacing.medium)
            Button(action: copy) {
                HStack(spacing: Memnox.Spacing.xSmall) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: Layout.copyIcon, weight: .medium))
                    Text(copied ? "Copied" : "Copy")
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.meta, .medium))
                }
                .foregroundStyle(hoveringCopy ? Memnox.Console.foreground : Memnox.Console.muted)
                .padding(.horizontal, Memnox.Spacing.regular)
                .frame(height: Layout.copyHeight)
                .background(hoveringCopy ? Memnox.Console.hover : Color.clear,
                            in: RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoveringCopy = $0 }
            .pointingHand()
            .help("Copy \(label)")
            .accessibilityLabel(copied ? "Copied" : "Copy \(label)")
        }
        .padding(.leading, Memnox.Spacing.xLarge)
        .padding(.trailing, Memnox.Spacing.medium)
        .frame(height: Layout.barHeight)
    }

    /// The code as one attributed text, each token in its colour, so selecting it copies plain text.
    private var highlighted: AttributedString {
        var text = AttributedString()
        for (index, line) in TomlTokens.lines(code).enumerated() {
            if index > 0 { text += AttributedString("\n") }
            for token in line {
                var run = AttributedString(token.text)
                run.foregroundColor = CodeColors.color(token.kind)
                text += run
            }
        }
        return text
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(Self.copiedFor))
            copied = false
        }
    }
}

/// The console's code colours: table headers in its orange, keys in its blue, strings in its green.
enum CodeColors {
    static func color(_ kind: TomlTokenKind) -> Color {
        switch kind {
        case .table: Memnox.Console.warm
        case .key: Memnox.Console.sky
        case .string: Memnox.Console.success
        case .punctuation, .comment: Memnox.Console.muted
        case .plain: Memnox.Console.foreground
        }
    }
}
