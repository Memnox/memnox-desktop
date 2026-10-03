import AppKit
import MemnoxVoiceCore
import SwiftUI

/// Matches the corners `IslandCard` draws, so the detail's cards read as one set.
private let detailCardRadius: CGFloat = 20

/// One session up close: who it is and what it did on the left, the code it is writing on the right.
struct IslandSessionDetail: View {
    @ObservedObject var model: IslandModel
    let session: SessionView

    private enum Layout {
        /// Room for the orb, which sits over this card's top left.
        static let orbClearance: CGFloat = 66
        static let stepSpacing: CGFloat = 7
        static let listedSteps = 4
        static let cardPadding: CGFloat = 14
        static let cardWidth: CGFloat = 220
    }

    private static let thinkingVeilOpacity = 0.3

    var body: some View {
        HStack(spacing: Memnox.Spacing.regular) {
            IslandCard(veil: session.thinking ? IslandPalette.color(session.agent).opacity(Self.thinkingVeilOpacity) : nil) {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: Layout.orbClearance)
                    Text(session.agentName)
                        .font(Memnox.sans(Memnox.TextSize.headline, .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    Text(session.task ?? session.repository ?? session.state)
                        .font(Memnox.sans(Memnox.TextSize.footnote))
                        .foregroundStyle(Color.white.opacity(Memnox.Ink.tertiary))
                        .lineLimit(1)
                        .padding(.bottom, Memnox.Spacing.regular)
                    VStack(alignment: .leading, spacing: Layout.stepSpacing) {
                        ForEach(Array(SessionText.meaningful(session.steps).suffix(Layout.listedSteps).reversed().enumerated()), id: \.offset) { index, step in
                            IslandStepLine(step: step, latest: index == 0, working: index == 0 && session.thinking)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(Layout.cardPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: Layout.cardWidth)
            .contentShape(RoundedRectangle(cornerRadius: detailCardRadius))
            .onTapGesture {
                if let card = model.focusCard { model.openWindow(card.sessionId, card.host) }
            }
            .help("Open this session")
            IslandCodePanel(session: session)
        }
        .islandContentInset(model.notch)
    }
}

/// One thing the session did, for the detail card's list.
struct IslandStepLine: View {
    let step: SessionViewStep
    let latest: Bool
    let working: Bool

    private static let iconColumnWidth: CGFloat = 14

    var body: some View {
        HStack(spacing: Memnox.Spacing.medium) {
            Group {
                if working {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: stepIcon(step))
                        .font(.system(size: Memnox.TextSize.caption, weight: .medium))
                        .foregroundStyle(stepTint(step, current: latest))
                }
            }
            .frame(width: Self.iconColumnWidth)
            Text(SessionText.line(for: step))
                .font(Memnox.sans(Memnox.TextSize.footnote, latest ? .semibold : .regular))
                .foregroundStyle(latest ? Color.white : IslandPalette.quiet)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// The file the session changed most, as an editor tab and its changed lines; the files alone when no lines can be read.
struct IslandCodePanel: View {
    let session: SessionView

    private enum Layout {
        /// As many changed lines as fit under the tab at the detail's height.
        static let shownLines = 10
        static let shownFiles = 6
        static let lineSpacing: CGFloat = 1
        static let badgeTextSize: CGFloat = 9
        static let badgeRadius: CGFloat = 3
        /// An editor marks a language with a short tag, so the extension is cut to this many letters.
        static let badgeLetters = 3
        static let tabInset: CGFloat = 14
        static let tabHeight: CGFloat = 34
    }

    private enum Shade {
        /// Barely there, so the panel's edge shows without framing the code.
        static let edge = 0.035
        static let path = 0.3
        static let tabFill = 0.03
    }

    private static let linesAnimation = Animation.easeOut(duration: 0.25)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let excerpt = session.excerpt {
                tab(excerpt.path)
                VStack(alignment: .leading, spacing: Layout.lineSpacing) {
                    ForEach(Array(excerpt.lines.prefix(Layout.shownLines).enumerated()), id: \.offset) { index, line in
                        IslandCodeLine(number: index + 1, line: line)
                    }
                }
                .padding(.vertical, Memnox.Spacing.medium)
                .animation(Self.linesAnimation, value: excerpt.lines)
            } else if !session.files.isEmpty {
                VStack(alignment: .leading, spacing: Memnox.Spacing.regular) {
                    ForEach(Array(session.files.prefix(Layout.shownFiles).enumerated()), id: \.offset) { _, file in
                        HStack(spacing: Memnox.Spacing.medium) {
                            Text(name(file.path)).font(.system(size: Memnox.TextSize.footnote, design: .monospaced))
                                .foregroundStyle(Color.white).lineLimit(1)
                            Spacer(minLength: Memnox.Spacing.medium)
                            counts(file.added, file.removed)
                        }
                    }
                }
                .padding(Memnox.Spacing.xLarge)
            } else {
                Text("Nothing changed yet")
                    .font(Memnox.sans(Memnox.TextSize.body))
                    .foregroundStyle(IslandPalette.quiet)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: detailCardRadius, style: .continuous).fill(Color(hex: 0x0D0E10)))
        .overlay(RoundedRectangle(cornerRadius: detailCardRadius, style: .continuous).strokeBorder(Color.white.opacity(Shade.edge), lineWidth: Memnox.Stroke.hairline))
        .clipShape(RoundedRectangle(cornerRadius: detailCardRadius, style: .continuous))
    }

    private func tab(_ path: String) -> some View {
        HStack(spacing: Memnox.Spacing.medium) {
            Text(kind(path))
                .font(.system(size: Layout.badgeTextSize, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white)
                .padding(.horizontal, Memnox.Spacing.xSmall)
                .padding(.vertical, Memnox.Spacing.xxSmall)
                .background(RoundedRectangle(cornerRadius: Layout.badgeRadius).fill(Memnox.Palette.primary))
            Text(name(path)).font(.system(size: Memnox.TextSize.footnote, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white)
            Spacer(minLength: Memnox.Spacing.medium)
            Text(path).font(.system(size: Memnox.TextSize.caption, design: .monospaced))
                .foregroundStyle(Color.white.opacity(Shade.path))
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, Layout.tabInset)
        .frame(height: Layout.tabHeight)
        .background(Color.white.opacity(Shade.tabFill))
    }

    private func counts(_ added: Int?, _ removed: Int?) -> some View {
        HStack(spacing: Memnox.Spacing.small) {
            if let added { Text("+\(added)").foregroundStyle(IslandPalette.green) }
            if let removed { Text("\u{2212}\(removed)").foregroundStyle(IslandPalette.red) }
        }
        .font(.system(size: Memnox.TextSize.caption, weight: .medium, design: .monospaced))
    }

    private func name(_ path: String) -> String { (path as NSString).lastPathComponent }

    /// The extension as a badge, the way an editor tab marks a file's language.
    private func kind(_ path: String) -> String {
        let ext = (path as NSString).pathExtension
        return ext.isEmpty ? "TXT" : String(ext.prefix(Layout.badgeLetters)).uppercased()
    }
}

/// One changed line with a gutter number: green for what it added, red for what it took out.
struct IslandCodeLine: View {
    let number: Int
    let line: String

    private enum Layout {
        static let gutterWidth: CGFloat = 18
        static let barWidth: CGFloat = 2
    }

    private enum Shade {
        static let gutter = 0.2
        static let removedText = 0.4
        static let rowTint = 0.09
        static let bar = 0.7
    }

    /// How a unified diff marks a line it added.
    private static let addedMarker = "+"

    var body: some View {
        let added = line.hasPrefix(Self.addedMarker)
        let tint = added ? IslandPalette.green : IslandPalette.red
        HStack(spacing: Memnox.Spacing.large) {
            Text("\(number)")
                .foregroundStyle(Color.white.opacity(Shade.gutter))
                .frame(width: Layout.gutterWidth, alignment: .trailing)
            Text(String(line.dropFirst()))
                .foregroundStyle(added ? IslandPalette.soft : Color.white.opacity(Shade.removedText))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: Memnox.TextSize.footnote, design: .monospaced))
        .padding(.horizontal, Memnox.Spacing.large)
        .padding(.vertical, Memnox.Spacing.xxSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(Shade.rowTint))
        .overlay(alignment: .leading) { Rectangle().fill(tint.opacity(Shade.bar)).frame(width: Layout.barWidth) }
    }
}

/// Opened with nothing running.
struct IslandEmpty: View {
    @ObservedObject var model: IslandModel

    private static let veilOpacity = 0.25
    /// Clears the orb, which sits over this card's left side.
    private static let textLeading: CGFloat = 112
    private static let talkSymbol = "waveform"

    var body: some View {
        IslandCard(veil: IslandPalette.indigo.opacity(Self.veilOpacity)) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
                Text("Nothing is running right now.")
                    .font(Memnox.sans(Memnox.TextSize.headline, .medium))
                    .foregroundStyle(Color.white)
                Button { model.tapped() } label: {
                    HStack(spacing: Memnox.Spacing.small) {
                        Image(systemName: Self.talkSymbol)
                        Text("Talk to Memnox")
                    }
                }
                .buttonStyle(IslandButton(primary: true))
            }
            .padding(.leading, Self.textLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .islandContentInset(model.notch)
    }
}
