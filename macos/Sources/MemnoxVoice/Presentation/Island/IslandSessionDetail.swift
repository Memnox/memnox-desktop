import AppKit
import MemnoxVoiceCore
import SwiftUI

/// One session up close, sized to the notch: who and where with how it stands, what it is doing this moment and
/// what it was asked on the left; the files it changed on the right, which open the live window and their diffs.
struct IslandSessionDetail: View {
    @ObservedObject var model: IslandModel
    let session: SessionView

    private enum Layout {
        static let logoSide: CGFloat = 30
        static let stepSpacing: CGFloat = 7
        /// Two lines of what it did fit under the ask without pushing past the notch's height.
        static let listedSteps = 2
        static let cardPadding: CGFloat = 14
        static let cardWidth: CGFloat = 260
        static let headerSpacing: CGFloat = 3
        static let askLines = 2
        static let labelTracking: CGFloat = 0.6
    }

    private static let thinkingVeilOpacity = 0.3

    var body: some View {
        HStack(spacing: Memnox.Spacing.regular) {
            IslandCard(veil: session.thinking ? IslandPalette.color(session.agent).opacity(Self.thinkingVeilOpacity) : nil) {
                VStack(alignment: .leading, spacing: Memnox.Spacing.regular) {
                    identity
                    ask
                    activity
                    Spacer(minLength: 0)
                }
                .padding(Layout.cardPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: Layout.cardWidth)
            IslandFilesPanel(session: session, watch: watch)
        }
        .islandContentInset(model.notch)
    }

    /// The logo, the agent's whole name, then how it stands and where it runs on one quiet line, and the way into it.
    private var identity: some View {
        HStack(alignment: .center, spacing: Memnox.Spacing.medium) {
            AgentLogo(kind: IslandPalette.kind(session.agent), name: session.agentName)
                .frame(width: Layout.logoSide * Shade.logoScale, height: Layout.logoSide * Shade.logoScale)
                .frame(width: Layout.logoSide, height: Layout.logoSide)
                .background(Circle().fill(IslandPalette.color(session.agent)))
            VStack(alignment: .leading, spacing: Layout.headerSpacing) {
                Text(session.agentName)
                    .font(Memnox.sans(Memnox.TextSize.callout, .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .layoutPriority(1)
                HStack(spacing: Memnox.Spacing.small) {
                    IslandStatusBadge(status: session.status, label: SessionDetailText.statusLabel(of: session, now: Date()))
                    if let place = SessionDetailText.place(of: session) {
                        Text(place)
                            .font(Memnox.sans(Memnox.TextSize.caption))
                            .foregroundStyle(Color.white.opacity(Shade.place))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
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

    /// The follow-up it is on when there is one, else what it was opened for, with icon glyphs from a terminal taken out.
    @ViewBuilder private var ask: some View {
        let opening = SessionReading.readable(session.task)
        let latest = SessionReading.readable(session.lastAsk)
        let followUp = latest != nil && latest != opening
        if let words = followUp ? latest : opening {
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                Text(followUp ? "Follow-up" : "Asked")
                    .font(Memnox.sans(Memnox.TextSize.micro, .semibold))
                    .tracking(Layout.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(followUp ? Memnox.Palette.sky : Color.white.opacity(Shade.sectionLabel))
                Text(words)
                    .font(Memnox.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(IslandPalette.soft)
                    .lineLimit(Layout.askLines)
                    .truncationMode(.tail)
                    .help(words)
            }
        }
    }

    /// What it is doing this moment first, then what it did just before, each with how long ago.
    @ViewBuilder private var activity: some View {
        let steps = Array(SessionText.meaningful(session.steps).suffix(Layout.listedSteps).reversed())
        if !steps.isEmpty {
            VStack(alignment: .leading, spacing: Layout.stepSpacing) {
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

    private func watch() {
        let card = model.cards.first { $0.sessionId == session.sessionId }
        model.watchLive(session.sessionId, card?.host)
    }

    private enum Symbol {
        static let open = "arrow.up.forward"
    }

    private enum Shade {
        static let place = 0.5
        static let sectionLabel = 0.4
        /// The logo fills a little over half its disc, the same as in the session list.
        static let logoScale: CGFloat = 0.56
        static let openSide: CGFloat = 26
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

/// The files the session changed with the totals over them, as many as the notch holds; a click opens the live
/// window, where each file opens into its real diff.
struct IslandFilesPanel: View {
    let session: SessionView
    let watch: () -> Void
    @State private var hovered = false

    private enum Layout {
        /// As many rows as fit under the totals in the notch's height, with the line that counts the rest.
        static let shownFiles = 5
        static let rowSpacing: CGFloat = 7
        static let padding: CGFloat = 14
    }

    private enum Shade {
        static let folder = 0.4
        static let hint = 0.55
    }

    private enum Symbol {
        static let file = "doc.text"
        static let diffs = "plusminus"
    }

    private static let nothingChanged = "No files changed yet"
    /// Memnox saw only where it connected, as for a desktop app it does not hook, so its files are unseen rather than unchanged.
    private static let filesUnseen = "Memnox sees only where this session connects, not the files it changes"

    private var added: Int { session.files.compactMap(\.added).reduce(0, +) }
    private var removed: Int { session.files.compactMap(\.removed).reduce(0, +) }

    var body: some View {
        Button(action: watch) {
            IslandCard(veil: nil) {
                VStack(alignment: .leading, spacing: Layout.rowSpacing) {
                    if session.files.isEmpty {
                        Text(SessionText.onlyNetwork(session.steps) ? Self.filesUnseen : Self.nothingChanged)
                            .font(Memnox.sans(Memnox.TextSize.footnote))
                            .foregroundStyle(IslandPalette.soft)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        HStack(spacing: Memnox.Spacing.small) {
                            Text(session.files.count == 1 ? "1 file changed" : "\(session.files.count) files changed")
                                .font(Memnox.sans(Memnox.TextSize.caption, .semibold))
                                .foregroundStyle(Color.white)
                            Spacer(minLength: Memnox.Spacing.small)
                            counts(added, removed)
                        }
                        ForEach(Array(session.files.prefix(Layout.shownFiles).enumerated()), id: \.offset) { _, file in
                            HStack(spacing: Memnox.Spacing.small) {
                                Image(systemName: Symbol.file)
                                    .font(.system(size: Memnox.TextSize.micro))
                                    .foregroundStyle(Color.white.opacity(Shade.folder))
                                Text(name(file.path)).font(Memnox.sans(Memnox.TextSize.footnote, .medium))
                                    .foregroundStyle(Color.white).lineLimit(1).truncationMode(.middle)
                                    .layoutPriority(1)
                                Text(SessionDetailText.folder(of: file.path)).font(Memnox.sans(Memnox.TextSize.caption))
                                    .foregroundStyle(Color.white.opacity(Shade.folder)).lineLimit(1).truncationMode(.head)
                                Spacer(minLength: Memnox.Spacing.small)
                                counts(file.added, file.removed)
                            }
                            .help(file.path)
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: Memnox.Spacing.xSmall) {
                            Image(systemName: Symbol.diffs)
                            Text(more)
                        }
                        .font(Memnox.sans(Memnox.TextSize.caption, .medium))
                        .foregroundStyle(hovered ? Memnox.Palette.sky : Color.white.opacity(Shade.hint))
                    }
                }
                .padding(Layout.padding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .buttonStyle(PressableStyle())
        .onHover { hovered = $0 }
        .pointingHand()
        .help("Open the live window to read the diffs")
        .accessibilityLabel("\(session.files.count) files changed. Open the live window to read the diffs")
    }

    /// The files left over, and that the diffs are a click away.
    private var more: String {
        let rest = session.files.count - Layout.shownFiles
        return rest > 0 ? "\(rest) more, see every diff" : "See the diffs"
    }

    private func counts(_ added: Int?, _ removed: Int?) -> some View {
        HStack(spacing: Memnox.Spacing.xSmall) {
            if let added { Text("+\(added)").foregroundStyle(IslandPalette.green) }
            if let removed, removed > 0 { Text("\u{2212}\(removed)").foregroundStyle(IslandPalette.red) }
        }
        .font(.system(size: Memnox.TextSize.caption, weight: .medium).monospacedDigit())
        .fixedSize()
    }

    private func name(_ path: String) -> String { (path as NSString).lastPathComponent }
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
