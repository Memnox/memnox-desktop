import AppKit
import MemnoxVoiceCore
import SwiftUI

/// Matches the corners `IslandCard` draws, so the detail's cards read as one set.
private let detailCardRadius: CGFloat = 20

/// One session up close: who it is, where, what it was asked and what it did on the left, the code it is writing on the right.
struct IslandSessionDetail: View {
    @ObservedObject var model: IslandModel
    let session: SessionView

    private enum Layout {
        static let logoSide: CGFloat = 30
        static let stepSpacing: CGFloat = 8
        static let listedSteps = 3
        static let cardPadding: CGFloat = 14
        static let cardWidth: CGFloat = 236
        static let headerSpacing: CGFloat = 2
        static let askLines = 2
    }

    private static let thinkingVeilOpacity = 0.3

    var body: some View {
        HStack(spacing: Memnox.Spacing.regular) {
            IslandCard(veil: session.thinking ? IslandPalette.color(session.agent).opacity(Self.thinkingVeilOpacity) : nil) {
                VStack(alignment: .leading, spacing: Memnox.Spacing.regular) {
                    identity
                    if let task = session.task { asked(task) }
                    activity
                    Spacer(minLength: 0)
                }
                .padding(Layout.cardPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: Layout.cardWidth)
            IslandCodePanel(session: session)
        }
        .islandContentInset(model.notch)
    }

    /// The agent's logo, its name and badge, where it runs, and the way into it.
    private var identity: some View {
        HStack(alignment: .center, spacing: Memnox.Spacing.medium) {
            AgentLogo(kind: IslandPalette.kind(session.agent), name: session.agentName)
                .frame(width: Layout.logoSide * Shade.logoScale, height: Layout.logoSide * Shade.logoScale)
                .frame(width: Layout.logoSide, height: Layout.logoSide)
                .background(Circle().fill(IslandPalette.color(session.agent)))
            VStack(alignment: .leading, spacing: Layout.headerSpacing) {
                HStack(spacing: Memnox.Spacing.small) {
                    Text(session.agentName)
                        .font(Memnox.sans(Memnox.TextSize.headline, .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    IslandStatusBadge(status: session.status, label: SessionDetailText.statusLabel(of: session, now: Date()))
                }
                if let place = SessionDetailText.place(of: session) {
                    Text(place)
                        .font(Memnox.sans(Memnox.TextSize.caption))
                        .foregroundStyle(Color.white.opacity(Shade.place))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            Button(action: open) {
                Image(systemName: Symbol.open)
                    .font(.system(size: Memnox.TextSize.caption, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: Shade.openSide, height: Shade.openSide)
                    .background(Circle().fill(Color.white.opacity(Memnox.Ink.fill)))
            }
            .buttonStyle(PressableStyle())
            .help(session.runningIn.map { "Open this session in \($0)" } ?? "Open this session")
        }
    }

    /// What the person last asked it, quoted, since that is what the work on the right is for.
    private func asked(_ task: String) -> some View {
        Text("\u{201C}\(task)\u{201D}")
            .font(Memnox.sans(Memnox.TextSize.footnote))
            .foregroundStyle(IslandPalette.soft)
            .lineLimit(Layout.askLines)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .help(task)
    }

    /// The latest few things it did, newest first, each with how long ago.
    @ViewBuilder private var activity: some View {
        let steps = Array(SessionText.meaningful(session.steps).suffix(Layout.listedSteps).reversed())
        if !steps.isEmpty {
            VStack(alignment: .leading, spacing: Layout.stepSpacing) {
                Text("Recent activity")
                    .font(Memnox.sans(Memnox.TextSize.micro, .semibold))
                    .foregroundStyle(Color.white.opacity(Shade.sectionLabel))
                    .textCase(.uppercase)
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    IslandStepLine(step: step, latest: index == 0, working: index == 0 && session.thinking)
                }
            }
        }
    }

    private func open() {
        let card = model.cards.first { $0.sessionId == session.sessionId } ?? model.focusCard
        if let card { model.openWindow(card.sessionId, card.host) }
    }

    private enum Symbol {
        static let open = "arrow.up.forward"
    }

    private enum Shade {
        static let place = 0.5
        static let sectionLabel = 0.4
        /// The logo fills a little over half its disc, the same as in the session list.
        static let logoScale: CGFloat = 0.56
        static let openSide: CGFloat = 24
    }
}

/// A session's state as a small coloured pill, the same colours the switcher and the live window use.
struct IslandStatusBadge: View {
    let status: SessionStatus
    let label: String

    private static let dotSide: CGFloat = 6
    private static let fillOpacity = 0.16

    var body: some View {
        HStack(spacing: Memnox.Spacing.xSmall) {
            Circle()
                .fill(status.tint)
                .frame(width: Self.dotSide, height: Self.dotSide)
                .modifier(PulseIf(on: status.isActive))
            Text(label)
                .font(Memnox.sans(Memnox.TextSize.micro, .semibold))
                .foregroundStyle(status.tint.liftedTowardWhite)
                .lineLimit(1)
        }
        .padding(.horizontal, Memnox.Spacing.small)
        .padding(.vertical, Memnox.Spacing.xxSmall)
        .background(Capsule().fill(status.tint.opacity(Self.fillOpacity)))
        .fixedSize()
    }
}

/// Pulses only while the session is busy, so a resting badge sits still.
private struct PulseIf: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        if on { content.modifier(PulseEffect()) } else { content }
    }
}

/// One thing the session did, for the detail card's list, with how long ago on the right.
struct IslandStepLine: View {
    let step: SessionViewStep
    let latest: Bool
    let working: Bool

    private static let iconColumnWidth: CGFloat = 14
    private static let agoOpacity = 0.35

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
                .font(Memnox.sans(Memnox.TextSize.footnote, latest ? .medium : .regular))
                .foregroundStyle(latest ? Color.white : IslandPalette.soft)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Memnox.Spacing.xSmall)
            if let ago = SessionText.ago(step.at, now: Date()) {
                Text(ago)
                    .font(Memnox.sans(Memnox.TextSize.micro))
                    .foregroundStyle(Color.white.opacity(Self.agoOpacity))
                    .monospacedDigit()
                    .fixedSize()
            }
        }
        .help(step.text)
    }
}

/// The file the session changed most, as an editor tab with its counts and its changed lines; the files alone when no lines can be read.
struct IslandCodePanel: View {
    let session: SessionView

    private enum Layout {
        /// As many changed lines as fit under the tab and the footer at the detail's height.
        static let shownLines = 7
        static let shownFiles = 6
        static let lineSpacing: CGFloat = 1
        static let badgeTextSize: CGFloat = 9
        static let badgeRadius: CGFloat = 3
        /// An editor marks a language with a short tag, so the extension is cut to this many letters.
        static let badgeLetters = 3
        static let tabInset: CGFloat = 14
        static let tabHeight: CGFloat = 38
        static let footerHeight: CGFloat = 26
        static let nameSpacing: CGFloat = 1
    }

    private enum Shade {
        /// Barely there, so the panel's edge shows without framing the code.
        static let edge = 0.035
        static let folder = 0.4
        static let tabFill = 0.03
        static let footer = 0.45
    }

    private static let linesAnimation = Animation.easeOut(duration: 0.25)

    private static let nothingChanged = "No files changed yet"
    /// Memnox saw only where it connected, as for a desktop app it does not hook, so its files are unseen rather than unchanged.
    private static let filesUnseen = "Memnox sees only where this session connects, not the files it changes"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let excerpt = session.excerpt {
                let lines = SessionDetailText.diffLines(excerpt.lines)
                tab(excerpt.path)
                VStack(alignment: .leading, spacing: Layout.lineSpacing) {
                    ForEach(Array(lines.prefix(Layout.shownLines).enumerated()), id: \.offset) { _, line in
                        IslandCodeLine(line: line)
                    }
                }
                .padding(.vertical, Memnox.Spacing.small)
                .animation(Self.linesAnimation, value: excerpt.lines)
                Spacer(minLength: 0)
                footer(hiddenLines: max(0, lines.count - Layout.shownLines), excerptPath: excerpt.path)
            } else if !session.files.isEmpty {
                Text("Changed files")
                    .font(Memnox.sans(Memnox.TextSize.micro, .semibold))
                    .foregroundStyle(Color.white.opacity(Shade.folder))
                    .textCase(.uppercase)
                    .padding([.horizontal, .top], Memnox.Spacing.xLarge)
                VStack(alignment: .leading, spacing: Memnox.Spacing.regular) {
                    ForEach(Array(session.files.prefix(Layout.shownFiles).enumerated()), id: \.offset) { _, file in
                        HStack(spacing: Memnox.Spacing.medium) {
                            Text(name(file.path)).font(.system(size: Memnox.TextSize.footnote, design: .monospaced))
                                .foregroundStyle(Color.white).lineLimit(1)
                            Text(SessionDetailText.folder(of: file.path)).font(Memnox.sans(Memnox.TextSize.caption))
                                .foregroundStyle(Color.white.opacity(Shade.folder)).lineLimit(1).truncationMode(.head)
                            Spacer(minLength: Memnox.Spacing.medium)
                            counts(file.added, file.removed)
                        }
                        .help(file.path)
                    }
                }
                .padding(Memnox.Spacing.xLarge)
                Spacer(minLength: 0)
            } else {
                Text(SessionText.onlyNetwork(session.steps) ? Self.filesUnseen : Self.nothingChanged)
                    .font(Memnox.sans(Memnox.TextSize.body))
                    .foregroundStyle(IslandPalette.soft)
                    .multilineTextAlignment(.center)
                    .padding(Memnox.Spacing.xLarge)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: detailCardRadius, style: .continuous).fill(Color(hex: 0x0D0E10)))
        .overlay(RoundedRectangle(cornerRadius: detailCardRadius, style: .continuous).strokeBorder(Color.white.opacity(Shade.edge), lineWidth: Memnox.Stroke.hairline))
        .clipShape(RoundedRectangle(cornerRadius: detailCardRadius, style: .continuous))
    }

    /// The file's name over the folders it sits in, with how much it changed on the right.
    private func tab(_ path: String) -> some View {
        let changed = SessionDetailText.counts(for: path, in: session.files)
        return HStack(spacing: Memnox.Spacing.medium) {
            Text(kind(path))
                .font(.system(size: Layout.badgeTextSize, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white)
                .padding(.horizontal, Memnox.Spacing.xSmall)
                .padding(.vertical, Memnox.Spacing.xxSmall)
                .background(RoundedRectangle(cornerRadius: Layout.badgeRadius).fill(Memnox.Palette.primary))
            VStack(alignment: .leading, spacing: Layout.nameSpacing) {
                Text(name(path)).font(.system(size: Memnox.TextSize.footnote, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(SessionDetailText.folder(of: path)).font(Memnox.sans(Memnox.TextSize.micro))
                    .foregroundStyle(Color.white.opacity(Shade.folder))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: Memnox.Spacing.medium)
            if let changed { counts(changed.added, changed.removed) }
        }
        .padding(.horizontal, Layout.tabInset)
        .frame(height: Layout.tabHeight)
        .background(Color.white.opacity(Shade.tabFill))
        .help(path)
    }

    /// What is not shown: the rest of this file's lines, and the other files it changed.
    @ViewBuilder private func footer(hiddenLines: Int, excerptPath: String) -> some View {
        let others = session.files.filter { $0.path != SessionDetailText.counts(for: excerptPath, in: session.files)?.path }
        let parts = [
            hiddenLines > 0 ? "\(hiddenLines) more \(hiddenLines == 1 ? "line" : "lines") here" : nil,
            others.isEmpty ? nil : "\(others.count) other \(others.count == 1 ? "file" : "files") changed",
        ].compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: SessionText.separator))
                .font(Memnox.sans(Memnox.TextSize.caption))
                .foregroundStyle(Color.white.opacity(Shade.footer))
                .lineLimit(1)
                .padding(.horizontal, Layout.tabInset)
                .frame(maxWidth: .infinity, minHeight: Layout.footerHeight, alignment: .leading)
                .background(Color.white.opacity(Shade.tabFill))
                .help(others.map(\.path).joined(separator: "\n"))
        }
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

/// One changed line marked the way a diff marks it: a plus and green for what it added, a minus and red for what it took out.
struct IslandCodeLine: View {
    let line: SessionDetailText.DiffLine

    private enum Layout {
        static let markerWidth: CGFloat = 10
        static let barWidth: CGFloat = 2
    }

    private enum Shade {
        static let removedText = 0.5
        static let rowTint = 0.09
        static let bar = 0.7
    }

    var body: some View {
        let tint = line.added ? IslandPalette.green : IslandPalette.red
        HStack(spacing: Memnox.Spacing.medium) {
            Text(line.added ? "+" : "\u{2212}")
                .foregroundStyle(tint)
                .frame(width: Layout.markerWidth, alignment: .center)
            Text(line.text)
                .foregroundStyle(line.added ? IslandPalette.soft : Color.white.opacity(Shade.removedText))
                .strikethrough(!line.added, color: Color.white.opacity(Shade.removedText))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: Memnox.TextSize.footnote, design: .monospaced))
        .padding(.horizontal, Memnox.Spacing.large)
        .padding(.vertical, Memnox.Spacing.xxSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(Shade.rowTint))
        .overlay(alignment: .leading) { Rectangle().fill(tint.opacity(Shade.bar)).frame(width: Layout.barWidth) }
        .help(line.text)
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
