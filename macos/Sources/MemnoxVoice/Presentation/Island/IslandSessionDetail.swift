import AppKit
import MemnoxVoiceCore
import SwiftUI

/// One session up close, sized to the notch: who and where with how it stands, what it is doing this moment and
/// what it was asked on the left; the files it changed on the right, which open the live window and their diffs.
struct IslandSessionDetail: View {
    @ObservedObject var model: IslandModel
    let session: SessionView
    /// The whole ask shown in place of the two lines it is cut to, for a prompt too long to read cut.
    @State private var askOpen = false
    @State private var reply = ""
    @State private var sending = false
    /// What became of the last reply, said under the field until the next one.
    @State private var replied: String?
    /// The header lights under the pointer, so it reads as the way into the session rather than a label.
    @State private var headerHovered = false

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
        /// Tall enough to read a long prompt in place, short enough that the reply field stays on the card.
        static let openAskHeight: CGFloat = 92
    }

    private static let thinkingVeilOpacity = 0.3

    var body: some View {
        HStack(spacing: Memnox.Spacing.regular) {
            IslandCard(veil: session.thinking ? IslandPalette.color(session.agent).opacity(Self.thinkingVeilOpacity) : nil) {
                VStack(alignment: .leading, spacing: Memnox.Spacing.regular) {
                    identity
                    ask
                    if !askOpen { activity }
                    Spacer(minLength: 0)
                    replyField
                }
                .padding(Layout.cardPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: Layout.cardWidth)
            IslandFilesPanel(session: session, watch: watch)
        }
        .islandContentInset(model.notch)
    }

    /// The logo, the agent's whole name, then how it stands and where it runs on one quiet line. The whole row is the
    /// way into the session, and says so under the pointer, since a lone arrow was easy to miss.
    private var identity: some View {
        Button(action: open) { identityRow }
            .buttonStyle(PressableStyle())
            .onHover { inside in withAnimation(.easeOut(duration: Memnox.Motion.quick)) { headerHovered = inside } }
            .pointingHand()
            .help(openWords)
            .accessibilityLabel("\(session.agentName), \(openWords)")
    }

    private var openWords: String { session.runningIn.map { "Open in \($0)" } ?? "Open this session" }

    private var identityRow: some View {
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
                    // Under the pointer the quiet line says where the click goes, in place of where it runs.
                    if let place = headerHovered ? openWords : SessionDetailText.place(of: session) {
                        Text(place)
                            .font(Memnox.sans(Memnox.TextSize.caption, headerHovered ? .semibold : .regular))
                            .foregroundStyle(headerHovered ? Color.white : Color.white.opacity(Shade.place))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: Symbol.open)
                .font(.system(size: Memnox.TextSize.caption, weight: .semibold))
                .foregroundStyle(headerHovered ? Color.black : Color.white)
                .frame(width: Shade.openSide, height: Shade.openSide)
                .background(Circle().fill(headerHovered ? Color.white : Color.white.opacity(Memnox.Ink.fill)))
                .scaleEffect(headerHovered ? Shade.openHoverScale : 1)
        }
        .padding(Shade.headerInset)
        .background(
            RoundedRectangle(cornerRadius: Shade.headerRadius, style: .continuous)
                .fill(Color.white.opacity(headerHovered ? Shade.headerHoverFill : 0))
        )
        // The light sits just outside the card's padding, so the row keeps its place when it lights.
        .padding(-Shade.headerInset)
        .contentShape(Rectangle())
    }

    /// The follow-up it is on when there is one, else what it was opened for, with icon glyphs from a terminal taken out.
    @ViewBuilder private var ask: some View {
        let opening = SessionReading.readable(session.task)
        let latest = SessionReading.readable(session.lastAsk)
        let followUp = latest != nil && latest != opening
        if let words = followUp ? latest : opening {
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                HStack(spacing: Memnox.Spacing.xSmall) {
                    Text(followUp ? "Follow-up" : "Asked")
                        .font(Memnox.sans(Memnox.TextSize.micro, .semibold))
                        .tracking(Layout.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(followUp ? Memnox.Palette.sky : Color.white.opacity(Shade.sectionLabel))
                    Spacer(minLength: 0)
                    // Said in words beside the label, so the prompt reads as something to open rather than cut text.
                    Label(askOpen ? "Less" : "All of it", systemImage: askOpen ? Symbol.less : Symbol.more)
                        .font(Memnox.sans(Memnox.TextSize.micro, .semibold))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(Color.white.opacity(Shade.sectionLabel))
                }
                if askOpen {
                    ScrollView {
                        askText(words).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: Layout.openAskHeight)
                } else {
                    askText(words)
                        .lineLimit(Layout.askLines)
                        .truncationMode(.tail)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.snappy) { askOpen.toggle() } }
            .pointingHand()
            .help(askOpen ? "Show less" : "Show all of it")
            .accessibilityAddTraits(.isButton)
        }
    }

    private func askText(_ words: String) -> some View {
        Text(words)
            .font(Memnox.sans(Memnox.TextSize.footnote))
            .foregroundStyle(IslandPalette.soft)
            .textSelection(.enabled)
    }

    /// The reply to this session, typed rather than said, and signed with Touch ID like a reply from the phone.
    private var replyField: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
            SearchField(prompt: "Reply to \(session.agentName)", text: $reply, symbol: "arrow.turn.down.right", submit: send)
                .disabled(sending)
                .environment(\.colorScheme, .dark)
            if let replied {
                Text(replied)
                    .font(Memnox.sans(Memnox.TextSize.micro))
                    .foregroundStyle(Color.white.opacity(Shade.sectionLabel))
                    .lineLimit(1)
            }
        }
    }

    private func send() {
        let words = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, !sending else { return }
        sending = true
        Task { @MainActor in
            let state = await model.followUp(words, session.sessionId)
            sending = false
            if case .sent = state { reply = "" }
            replied = FollowUpWords.of(state)
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
        static let more = "chevron.down"
        static let less = "chevron.up"
    }

    private enum Shade {
        static let place = 0.5
        static let sectionLabel = 0.4
        /// The logo fills a little over half its disc, the same as in the session list.
        static let logoScale: CGFloat = 0.56
        static let openSide: CGFloat = 26
        static let openHoverScale: CGFloat = 1.08
        static let headerInset: CGFloat = 6
        static let headerRadius: CGFloat = 12
        static let headerHoverFill = 0.08
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

/// What became of a reply typed to a session, in the words of where it now is, the same in the notch and the window.
enum FollowUpWords {
    static func of(_ state: FollowUpState) -> String {
        switch state {
        case .sent(.typed): return "Typed into its prompt, it shows in the session"
        case .sent(.queued): return "Handed over, it reads it at its next step"
        case .sent(.later): return "It reads it at its next prompt"
        case .cancelled: return "Not sent"
        case .refused(let why): return why
        case .unreachable: return "Memnox is not running"
        }
    }
}
