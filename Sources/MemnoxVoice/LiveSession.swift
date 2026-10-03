import AppKit
import MemnoxVoiceCore
import SwiftUI

/// What the live window shows, refreshed while it is open.
@MainActor
final class LiveModel: ObservableObject {
    @Published var view: SessionView?
    /// Drives the 3D entrance and exit: tipped back and small, then standing upright.
    @Published var shown = false
    /// Where the pointer is over the window, from minus one to one each way, for its lean and its sheen.
    @Published var tilt: CGSize = .zero
    @Published var size: CGSize = CGSize(width: LivePanel.width, height: LiveModel.initialHeight)
    /// A starting height only, until the window is laid out around its content.
    private static let initialHeight: CGFloat = 600
}

/// A borderless panel that can still take the pointer, so it leans as the person moves over it,
/// without making Memnox the active app and taking their keyboard.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The SF Symbols the live window draws.
private enum LiveSymbol {
    static let thinking = "sparkles"
    static let acting = "arrow.right.circle"
    static let shell = "terminal"
    static let filesystem = "doc.text"
    static let network = "globe"
    static let mcp = "puzzlepiece.extension"
    static let git = "arrow.triangle.branch"
    static let browser = "safari"
    static let otherStep = "circle.fill"
    static let tool = "gearshape"
    static let helper = "person.2"
    static let close = "xmark"
    static let openWindow = "arrow.up.forward.app"
}

/// Values more than one part of the live window shares, so its sections match.
private enum LiveStyle {
    static let sectionCornerRadius: CGFloat = 16
    /// Barely there, so a section reads as a shape rather than a box.
    static let sectionEdgeOpacity = 0.035
    /// Just under full white, so step and helper lines sit below the headline text.
    static let softTextOpacity = 0.88
    /// How many entries a list shows when it has the window to itself.
    static let fullListLength = 8
    /// How many it shows beside the conversation, which says most of it.
    static let sharedListLength = 4
}

private let nanosecondsPerSecond: TimeInterval = 1_000_000_000

/// The sleep APIs here take nanoseconds, so every wait is written in seconds and converted once.
private func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
    UInt64((seconds * nanosecondsPerSecond).rounded())
}

/// A window on a session in the middle of the screen: what it is on, what it just did, its
/// helpers and the files it changed, updated every couple of seconds while it stays open.
/// It swings in from depth rather than appearing, so it reads as something brought forward.
@MainActor
final class LivePanel {
    private let panel: KeyablePanel
    private let model = LiveModel()
    private var polling: Task<Void, Never>?
    private var hide: Task<Void, Never>?
    /// Asked for the session each refresh; set by the app once the conversation exists.
    var fetch: ((String) async -> SessionView?)?
    /// Brings the session's own terminal tab or editor forward, from the button in the window.
    var openOwnWindow: ((String, DisplayHost?) async -> Void)?
    static let width: CGFloat = 540

    private enum Timing {
        static let refreshEvery: TimeInterval = 2
        /// Long enough to watch a stretch of work, never a window left up all day.
        static let showFor: TimeInterval = 5 * 60
        static let entranceResponse = 0.6
        static let entranceDamping = 0.78
        static let exitDuration: TimeInterval = 0.28
        /// Just past the exit animation, so the panel leaves only once it has faded.
        static let orderOutDelay: TimeInterval = 0.3
    }

    private enum Layout {
        /// A placeholder until the panel is fitted to the screen it opens on.
        static let initialHeight: CGFloat = 520
        static let maxHeight: CGFloat = 820
        /// Keeps the panel clear of the screen's top and bottom edges.
        static let screenMargin: CGFloat = 40
        /// Room each side for the swing in, so it is never clipped while it turns.
        static let swingRoom: CGFloat = 30
    }

    init() {
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Layout.initialHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
    }

    func present(session: String, host: DisplayHost?) async {
        model.view = await fetch?(session)
        let view = LiveSessionView(
            model: model,
            close: { [weak self] in self?.dismiss() },
            jump: { [weak self] in
                Task { await self?.openOwnWindow?(session, host) }
                self?.dismiss()
            }
        )
        let hosting = FirstClickHosting(rootView: view)
        panel.contentView = hosting
        if let screen = NSScreen.main?.visibleFrame {
            // Room above and below for the swing in, so it is never clipped while it turns.
            let height: CGFloat = min(Layout.maxHeight, screen.height - Layout.screenMargin)
            panel.setFrame(
                NSRect(
                    x: screen.midX - Self.width / 2 - Layout.swingRoom,
                    y: screen.midY - height / 2,
                    width: Self.width + Layout.swingRoom * 2,
                    height: height
                ),
                display: true
            )
        }
        model.shown = false
        model.tilt = .zero
        panel.orderFrontRegardless()
        panel.makeKey()
        withAnimation(.spring(response: Timing.entranceResponse, dampingFraction: Timing.entranceDamping)) { model.shown = true }
        poll(session)
        hide?.cancel()
        hide = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds(Timing.showFor))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        polling?.cancel()
        hide?.cancel()
        withAnimation(.easeIn(duration: Timing.exitDuration)) { model.shown = false }
        Task { [panel] in
            try? await Task.sleep(nanoseconds: nanoseconds(Timing.orderOutDelay))
            panel.orderOut(nil)
        }
    }

    private func poll(_ session: String) {
        polling?.cancel()
        polling = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: nanoseconds(Timing.refreshEvery))
                guard !Task.isCancelled, let self, let fresh = await self.fetch?(session) else { continue }
                withAnimation(.easeOut(duration: Memnox.Motion.standard)) { self.model.view = fresh }
            }
        }
    }
}

struct LiveSessionView: View {
    @ObservedObject var model: LiveModel
    let close: () -> Void
    let jump: () -> Void

    private enum Layout {
        static let sectionSpacing: CGFloat = 14
        static let padding: CGFloat = 22
        static let cornerRadius: CGFloat = 28
        static let edgeOpacity = 0.07
        static let shadowOpacity = 0.5
        static let shadowRadius: CGFloat = 30
        static let shadowDrop: CGFloat = 18
        static let hiddenScale: CGFloat = 0.96
        static let hiddenLift: CGFloat = -14
        static let hiddenBlur: CGFloat = 8
    }

    private enum Glow {
        static let opacity = 0.32
        /// Below the bottom edge, so the light rises from under the window rather than inside it.
        static let center = UnitPoint(x: 0.5, y: 1.15)
        /// The low point of the breath while the session works.
        static let dimStrength = 0.55
        static let breathDuration: TimeInterval = 1.6
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
            if let view = model.view {
                LiveHeader(view: view, close: close).reveal(model.shown, order: 0)
                LiveNow(view: view).reveal(model.shown, order: 1)
                let talk = view.conversation ?? []
                if !talk.isEmpty {
                    LiveConversation(lines: talk, thinking: view.thinking).reveal(model.shown, order: 2)
                }
                // The conversation says most of it, so the record beside it stays short.
                if !view.steps.isEmpty {
                    LiveSteps(steps: view.steps, most: talk.isEmpty ? LiveStyle.fullListLength : LiveStyle.sharedListLength)
                        .reveal(model.shown, order: 3)
                }
                if !view.helpers.isEmpty { LiveHelpers(helpers: view.helpers).reveal(model.shown, order: 4) }
                if !view.files.isEmpty {
                    LiveSection(title: "Changed") {
                        FileList(
                            files: Array(view.files.prefix(talk.isEmpty ? LiveStyle.fullListLength : LiveStyle.sharedListLength)),
                            counting: model.shown
                        )
                    }
                    .reveal(model.shown, order: 5)
                }
                LiveFooter(view: view, jump: jump, close: close).reveal(model.shown, order: 6)
            } else {
                Text("This session is not on the record yet.")
                    .font(Memnox.sans(Memnox.TextSize.callout))
                    .foregroundStyle(Memnox.Palette.muted)
                LiveFooter(view: nil, jump: jump, close: close)
            }
        }
        .padding(Layout.padding)
        .frame(width: LivePanel.width, alignment: .leading)
        .background(surface)
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(Layout.edgeOpacity), lineWidth: Memnox.Stroke.hairline)
        )
        .shadow(color: .black.opacity(Layout.shadowOpacity), radius: Layout.shadowRadius, x: 0, y: Layout.shadowDrop)
        // Settles in the way the island opens, and stays flat so every button is where it is drawn.
        .scaleEffect(model.shown ? 1 : Layout.hiddenScale)
        .offset(y: model.shown ? 0 : Layout.hiddenLift)
        .blur(radius: model.shown ? 0 : Layout.hiddenBlur)
        .opacity(model.shown ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Solid black, lit from the bottom in the colour of how the session stands, and breathing while it works.
    private var surface: some View {
        let shape = RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
        let colour = glowColour(model.view)
        return shape.fill(Color.black)
            .overlay(
                RadialGradient(
                    colors: [colour.opacity(Glow.opacity), .clear],
                    center: Glow.center,
                    startRadius: 0,
                    endRadius: LivePanel.width
                )
                .phaseAnimator(model.view?.sessionState == .working ? [Glow.dimStrength, 1.0] : [1.0]) { light, strength in
                    light.opacity(strength)
                } animation: { _ in .easeInOut(duration: Glow.breathDuration) }
            )
            .clipShape(shape)
            .animation(.easeInOut(duration: Memnox.Motion.slow), value: model.view?.state)
    }
}

/// Each part rises into place a beat after the one above it, so the window assembles itself.
private struct Reveal: ViewModifier {
    let shown: Bool
    let order: Int

    private enum Motion {
        static let hiddenDrop: CGFloat = 18
        static let hiddenBlur: CGFloat = 6
        static let response = 0.55
        static let damping = 0.85
        /// Waits for the window itself to start settling before the first part rises.
        static let firstDelay: TimeInterval = 0.18
        static let delayPerPart: TimeInterval = 0.07
    }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : Motion.hiddenDrop)
            .blur(radius: shown ? 0 : Motion.hiddenBlur)
            .animation(
                .spring(response: Motion.response, dampingFraction: Motion.damping)
                    .delay(shown ? Motion.firstDelay + Double(order) * Motion.delayPerPart : 0),
                value: shown
            )
    }
}

extension View {
    fileprivate func reveal(_ shown: Bool, order: Int) -> some View {
        modifier(Reveal(shown: shown, order: order))
    }
}

/// Green while it works or thinks, amber when it waits on the person, red when paused, quiet otherwise.
private func glowColour(_ view: SessionView?) -> Color {
    view?.status.glow ?? Memnox.Palette.muted
}

struct LiveHeader: View {
    let view: SessionView
    let close: () -> Void

    private static let logoSize: CGFloat = 16
    private static let nameSize: CGFloat = 24
    private static let taskLineLimit = 2
    private static let metaSeparator = "  ·  "

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            HStack(alignment: .firstTextBaseline, spacing: Memnox.Spacing.regular) {
                LogoMark(size: Self.logoSize)
                Text(view.agentName)
                    .font(Memnox.display(Self.nameSize))
                    .foregroundStyle(Memnox.Palette.foreground)
                StatePill(view: view)
                Spacer()
                CloseButton(action: close)
            }
            if let task = view.task {
                Text(task)
                    .font(Memnox.sans(Memnox.TextSize.callout))
                    .foregroundStyle(Memnox.Palette.foreground.opacity(Memnox.Ink.primary))
                    .lineLimit(Self.taskLineLimit)
            }
            Text(meta(view))
                .font(Memnox.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.Palette.muted)
        }
    }

    private func meta(_ view: SessionView) -> String {
        [view.repository, view.runningIn, SessionText.ago(view.lastActive, now: Date()).map { "active \($0)" }]
            .compactMap { $0 }
            .joined(separator: Self.metaSeparator)
    }
}

/// Working, waiting on the person, paused or quiet, with a dot that breathes while it works.
private struct StatePill: View {
    let view: SessionView

    private enum Layout {
        static let dotSize: CGFloat = 7
        static let swellScale: CGFloat = 1.5
        static let swellOpacity = 0.5
        static let breathDuration: TimeInterval = 0.9
        static let horizontalPadding: CGFloat = 9
        static let verticalPadding: CGFloat = 3
        static let fillOpacity = 0.14
    }

    var body: some View {
        HStack(spacing: Memnox.Spacing.small) {
            Circle()
                .fill(colour)
                .frame(width: Layout.dotSize, height: Layout.dotSize)
                .phaseAnimator(working ? [false, true] : [false]) { dot, swelling in
                    dot.scaleEffect(swelling ? Layout.swellScale : 1).opacity(swelling ? Layout.swellOpacity : 1)
                } animation: { _ in .easeInOut(duration: Layout.breathDuration) }
            Text(label).font(Memnox.sans(Memnox.TextSize.caption, .medium))
        }
        .foregroundStyle(colour)
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.verticalPadding)
        .background(Capsule().fill(colour.opacity(Layout.fillOpacity)))
    }

    private var working: Bool { view.sessionState == .working }

    private var label: String { view.status.label }

    private var colour: Color { view.status.tint }
}

/// The one line that says what it is doing this moment.
struct LiveNow: View {
    let view: SessionView

    private static let horizontalPadding: CGFloat = 14
    private static let verticalPadding: CGFloat = 11

    var body: some View {
        HStack(spacing: Memnox.Spacing.medium) {
            Image(systemName: view.thinking ? LiveSymbol.thinking : LiveSymbol.acting)
                .foregroundStyle(Memnox.Palette.primary)
            Text(now)
                .font(Memnox.sans(Memnox.TextSize.body, .medium))
                .foregroundStyle(Memnox.Palette.foreground)
                .lineLimit(1)
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, Self.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: LiveStyle.sectionCornerRadius, style: .continuous).fill(IslandPalette.card))
        .overlay(
            RoundedRectangle(cornerRadius: LiveStyle.sectionCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(LiveStyle.sectionEdgeOpacity), lineWidth: Memnox.Stroke.hairline)
        )
    }

    private var now: String {
        if let paused = view.paused { return "Paused: \(paused)" }
        if view.thinking { return "Thinking through its answer" }
        if let last = view.steps.last { return last.text }
        return "Nothing recorded yet"
    }
}

/// The latest steps, newest at the bottom, each with what kind of thing it touched.
struct LiveSteps: View {
    let steps: [SessionViewStep]
    let most: Int

    private static let rowSpacing: CGFloat = 5
    private static let iconWidth: CGFloat = 14
    /// The runtime records browser steps, which `StepSurface` does not name yet.
    private static let browserSurface = "browser"

    var body: some View {
        LiveSection(title: "Latest steps") {
            VStack(alignment: .leading, spacing: Self.rowSpacing) {
                ForEach(Array(steps.suffix(most).enumerated()), id: \.element.at) { _, step in
                    HStack(spacing: Memnox.Spacing.medium) {
                        Image(systemName: icon(step))
                            .font(.system(size: Memnox.TextSize.caption))
                            .frame(width: Self.iconWidth)
                            .foregroundStyle(tint(step))
                        Text(step.text)
                            .font(.system(size: Memnox.TextSize.footnote, design: .monospaced))
                            .foregroundStyle(tint(step))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: Memnox.Spacing.small)
                        Text(SessionText.ago(step.at, now: Date()) ?? "")
                            .font(Memnox.sans(Memnox.TextSize.caption))
                            .foregroundStyle(Memnox.Palette.muted)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private func icon(_ step: SessionViewStep) -> String {
        switch step.stepSurface {
        case .shell: LiveSymbol.shell
        case .filesystem: LiveSymbol.filesystem
        case .network: LiveSymbol.network
        case .mcp: LiveSymbol.mcp
        case .git: LiveSymbol.git
        case .question, .config: LiveSymbol.otherStep
        case nil: step.surface == Self.browserSurface ? LiveSymbol.browser : LiveSymbol.otherStep
        }
    }

    private func tint(_ step: SessionViewStep) -> Color {
        if step.refused == true { return Memnox.Palette.warm }
        if step.failed == true { return Memnox.Palette.destructive }
        return Memnox.Palette.foreground.opacity(LiveStyle.softTextOpacity)
    }
}

/// Who said a conversation line, as the runtime writes it.
private enum LineAuthor: String {
    case person
    case agent
    case tool
}

/// The conversation itself, newest at the bottom and kept in view as it grows: the person on
/// the right, the agent on the left, and each tool it runs as a quiet line between them.
private struct LiveConversation: View {
    let lines: [ConversationLine]
    let thinking: Bool
    private static let dotsKey = "typing-dots"
    /// Enough of a line to tell it apart from its neighbours without keying on all of it.
    private static let keyTextLength = 48
    private static let arrivalScale: CGFloat = 0.96
    private static let lineSpacing: CGFloat = 8
    private static let maxHeight: CGFloat = 280
    private static let scrollDuration: TimeInterval = 0.35
    /// A new line slides up from below and settles, rather than appearing in place.
    private static let arrives = AnyTransition.asymmetric(
        insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: LiveConversation.arrivalScale, anchor: .bottomLeading)),
        removal: .opacity
    )

    /// Each line keyed by what it is, not where it sits, so one arriving moves in instead of every line shifting.
    private var keyed: [(key: String, line: ConversationLine)] {
        var seen: [String: Int] = [:]
        return lines.map { line in
            let base = "\(line.at)|\(line.who)|\(line.text.prefix(Self.keyTextLength))"
            let count = seen[base, default: 0]
            seen[base] = count + 1
            return (key: count == 0 ? base : "\(base)#\(count)", line: line)
        }
    }

    /// Only the agent's latest words type themselves out; the rest are already said.
    private var newestReply: String? {
        keyed.last { $0.line.who == LineAuthor.agent.rawValue }?.key
    }

    private var bottom: String { thinking ? Self.dotsKey : (keyed.last?.key ?? Self.dotsKey) }

    var body: some View {
        LiveSection(title: "Conversation") {
            ScrollViewReader { reader in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Self.lineSpacing) {
                        ForEach(keyed, id: \.key) { item in
                            ConversationRow(line: item.line, typing: item.key == newestReply)
                                .id(item.key)
                                .transition(Self.arrives)
                        }
                        if thinking { TypingDots().id(Self.dotsKey).transition(.opacity) }
                    }
                    .padding(.vertical, Memnox.Spacing.xxSmall)
                }
                .frame(maxHeight: Self.maxHeight)
                .onAppear { reader.scrollTo(bottom, anchor: .bottom) }
                .onChange(of: lines) { _, _ in
                    withAnimation(.easeOut(duration: Self.scrollDuration)) { reader.scrollTo(bottom, anchor: .bottom) }
                }
            }
        }
    }
}

struct ConversationRow: View {
    let line: ConversationLine
    let typing: Bool

    private enum Layout {
        /// Keeps the person's bubble to the right, clear of the agent's side.
        static let personIndent: CGFloat = 60
        static let bubbleHorizontalPadding: CGFloat = 11
        static let bubbleVerticalPadding: CGFloat = 7
        static let bubbleCornerRadius: CGFloat = 12
        static let bubbleFillOpacity = 0.32
        static let replyLineSpacing: CGFloat = 2
        /// Keeps the agent's words to the left, clear of the person's side.
        static let replyTrailingRoom: CGFloat = 40
    }

    var body: some View {
        switch LineAuthor(rawValue: line.who) {
        case .person:
            HStack {
                Spacer(minLength: Layout.personIndent)
                Text(line.text)
                    .font(Memnox.sans(Memnox.TextSize.body))
                    .foregroundStyle(Memnox.Palette.foreground)
                    .padding(.horizontal, Layout.bubbleHorizontalPadding)
                    .padding(.vertical, Layout.bubbleVerticalPadding)
                    .background(RoundedRectangle(cornerRadius: Layout.bubbleCornerRadius).fill(Memnox.Palette.primary.opacity(Layout.bubbleFillOpacity)))
            }
        case .tool:
            Label(line.text, systemImage: LiveSymbol.tool)
                .font(.system(size: Memnox.TextSize.caption, design: .monospaced))
                .foregroundStyle(Memnox.Palette.muted)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, Memnox.Spacing.xSmall)
        case .agent, nil:
            Group {
                if typing { TypedText(text: line.text) } else { Text(line.text) }
            }
                .font(Memnox.sans(Memnox.TextSize.body))
                .foregroundStyle(Memnox.Palette.foreground.opacity(Memnox.Ink.primary))
                .lineSpacing(Layout.replyLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, Layout.replyTrailingRoom)
        }
    }
}

/// Words that appear a few at a time, the way a reply is being written, then stay.
@MainActor
private final class Typing: ObservableObject {
    @Published var shown = 0
    private var target = ""
    private var task: Task<Void, Never>?
    private static let tick: TimeInterval = 0.014
    private static let charactersPerTick = 2

    func type(_ text: String) {
        guard text != target else { return }
        // Picks up where it was when the reply grows, rather than starting it again.
        let from = text.hasPrefix(target) ? shown : 0
        target = text
        shown = from
        task?.cancel()
        task = Task { [weak self] in
            while let self, !Task.isCancelled, self.shown < text.count {
                try? await Task.sleep(nanoseconds: nanoseconds(Self.tick))
                self.shown = min(text.count, self.shown + Self.charactersPerTick)
            }
        }
    }
}

private struct TypedText: View {
    let text: String
    @StateObject private var typing = Typing()

    var body: some View {
        Text(String(text.prefix(typing.shown)))
            .onAppear { typing.type(text) }
            .onChange(of: text) { _, fresh in typing.type(fresh) }
    }
}

/// Three dots that rise in turn while the agent is thinking through its answer.
private struct TypingDots: View {
    private enum Layout {
        static let count = 3
        static let spacing: CGFloat = 5
        static let dotSize: CGFloat = 6
        static let risen: CGFloat = -3
        static let resting: CGFloat = 1
        static let restingOpacity = 0.4
        static let riseDuration: TimeInterval = 0.45
        /// The gap between one dot rising and the next.
        static let stagger: TimeInterval = 0.15
    }

    var body: some View {
        HStack(spacing: Layout.spacing) {
            ForEach(0..<Layout.count, id: \.self) { dot in
                Circle()
                    .fill(Memnox.Palette.muted)
                    .frame(width: Layout.dotSize, height: Layout.dotSize)
                    .phaseAnimator([false, true]) { circle, up in
                        circle.offset(y: up ? Layout.risen : Layout.resting).opacity(up ? 1 : Layout.restingOpacity)
                    } animation: { _ in .easeInOut(duration: Layout.riseDuration).delay(Double(dot) * Layout.stagger) }
            }
        }
        .padding(.leading, Memnox.Spacing.xSmall)
        .padding(.vertical, Memnox.Spacing.xSmall)
    }
}

private struct LiveHelpers: View {
    let helpers: [String]

    var body: some View {
        LiveSection(title: "Helpers") {
            VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                ForEach(helpers, id: \.self) { helper in
                    Label(helper, systemImage: LiveSymbol.helper)
                        .font(Memnox.sans(Memnox.TextSize.footnote))
                        .foregroundStyle(Memnox.Palette.foreground.opacity(LiveStyle.softTextOpacity))
                }
            }
        }
    }
}

/// LiveSection's measurements, at file scope because a generic type cannot hold stored statics.
private enum LiveSectionLayout {
    static let titleSpacing: CGFloat = 7
    static let titleTracking: CGFloat = 0.8
    /// Dimmer than secondary text, so a section title labels without competing.
    static let titleOpacity = 0.4
}

struct LiveSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    private typealias Layout = LiveSectionLayout

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.titleSpacing) {
            Text(title.uppercased())
                .font(Memnox.sans(Memnox.TextSize.micro, .semibold))
                .tracking(Layout.titleTracking)
                .foregroundStyle(Color.white.opacity(Layout.titleOpacity))
                .padding(.leading, Memnox.Spacing.xSmall)
            content()
                .padding(Memnox.Spacing.large)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: LiveStyle.sectionCornerRadius, style: .continuous).fill(IslandPalette.card))
                .overlay(
                    RoundedRectangle(cornerRadius: LiveStyle.sectionCornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(LiveStyle.sectionEdgeOpacity), lineWidth: Memnox.Stroke.hairline)
                )
        }
    }
}

private struct LiveFooter: View {
    let view: SessionView?
    let jump: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: Memnox.Spacing.medium) {
            Spacer()
            CardButton(title: "Close", icon: LiveSymbol.close, primary: false, action: close)
            CardButton(title: jumpLabel, icon: LiveSymbol.openWindow, primary: true, action: jump)
        }
    }

    private var jumpLabel: String {
        guard let app = view?.runningIn else { return "Open its window" }
        return "Open in \(app)"
    }
}
