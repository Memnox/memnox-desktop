import AppKit
import MemnoxVoiceCore
import SwiftUI

/// The monospaced size of file names, line counts and diff lines.
private let codeTextSize: CGFloat = 11.5

/// The files it changed, each by its short name with the lines it added and removed.
struct FileList: View {
    let files: [CardFile]
    /// Counts roll up from zero once this turns true, so the size of the change is felt, not just read.
    var counting = true

    private enum Layout {
        static let nameOpacity = 0.9
        static let countDuration: TimeInterval = 1.1
        /// The counts wait for the card to settle before they roll up.
        static let countDelay: TimeInterval = 0.55
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
            ForEach(files, id: \.path) { file in
                HStack(spacing: Memnox.Spacing.medium) {
                    Text(SessionText.shortPath(file.path))
                        .font(.system(size: Memnox.TextSize.footnote, design: .monospaced))
                        .foregroundStyle(Memnox.Palette.foreground.opacity(Layout.nameOpacity))
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer(minLength: Memnox.Spacing.medium)
                    if let added = file.added {
                        Text("+\(counting ? added : 0)")
                            .foregroundStyle(Memnox.Palette.success)
                            .contentTransition(.numericText(value: Double(counting ? added : 0)))
                    }
                    if let removed = file.removed, removed > 0 {
                        Text("\u{2212}\(counting ? removed : 0)")
                            .foregroundStyle(Memnox.Palette.destructive)
                            .contentTransition(.numericText(value: Double(counting ? removed : 0)))
                    }
                }
                .font(.system(size: codeTextSize, weight: .medium, design: .monospaced))
            }
        }
        .animation(.easeOut(duration: Layout.countDuration).delay(counting ? Layout.countDelay : 0), value: counting)
        .padding(.top, Memnox.Spacing.xxSmall)
    }
}

/// A few changed lines of the file that changed most, coloured the way a diff is read.
struct CodeExcerpt: View {
    let excerpt: CardExcerpt

    private enum Layout {
        static let cornerRadius: CGFloat = 14
        static let badgeTextSize: CGFloat = 9
        static let badgeCornerRadius: CGFloat = 3
        /// The badge shows at most this many letters of the extension.
        static let badgeLength = 3
        static let headerHeight: CGFloat = 30
        static let headerFill = 0.03
        /// The rows sit almost flush, so the diff reads as one block.
        static let lineGap: CGFloat = 1
        static let lineTint = 0.09
        static let ruleTint = 0.7
        static let ruleWidth: CGFloat = 2
        static let unchangedTint = 0.2
        static let edge = 0.05
    }

    /// The marks a diff line starts with.
    private enum Diff {
        static let added = "+"
        static let removed = "-"
    }

    /// The badge for a file with no extension.
    private static let plainTextBadge = "TXT"

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Memnox.Spacing.medium) {
                Text(extensionBadge)
                    .font(.system(size: Layout.badgeTextSize, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, Memnox.Spacing.xSmall)
                    .padding(.vertical, Memnox.Spacing.xxSmall)
                    .background(RoundedRectangle(cornerRadius: Layout.badgeCornerRadius).fill(Memnox.Palette.primary))
                Text(SessionText.shortPath(excerpt.path))
                    .font(.system(size: codeTextSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Memnox.Spacing.large)
            .frame(height: Layout.headerHeight)
            .background(Color.white.opacity(Layout.headerFill))
            VStack(alignment: .leading, spacing: Layout.lineGap) {
                ForEach(Array(excerpt.lines.enumerated()), id: \.offset) { _, line in
                    let tint = colour(of: line)
                    Text(line.dropFirst())
                        .font(.system(size: codeTextSize, design: .monospaced))
                        .foregroundStyle(line.hasPrefix(Diff.removed) ? Color.white.opacity(Memnox.Ink.tertiary) : IslandPalette.soft)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, Memnox.Spacing.large)
                        .padding(.vertical, Memnox.Spacing.xxSmall)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(tint.opacity(Layout.lineTint))
                        .overlay(alignment: .leading) { Rectangle().fill(tint.opacity(Layout.ruleTint)).frame(width: Layout.ruleWidth) }
                }
            }
            .padding(.vertical, Memnox.Spacing.small)
        }
        .background(shape.fill(Color(hex: 0x0D0E10)))
        .overlay(shape.strokeBorder(Color.white.opacity(Layout.edge), lineWidth: Memnox.Stroke.hairline))
        .clipShape(shape)
    }

    /// The extension as a badge, the way an editor tab marks a file's language.
    private var extensionBadge: String {
        let ext = (excerpt.path as NSString).pathExtension
        return ext.isEmpty ? Self.plainTextBadge : String(ext.prefix(Layout.badgeLength)).uppercased()
    }

    private func colour(of line: String) -> Color {
        if line.hasPrefix(Diff.added) { return IslandPalette.green }
        if line.hasPrefix(Diff.removed) { return IslandPalette.red }
        return Color.white.opacity(Layout.unchangedTint)
    }
}
