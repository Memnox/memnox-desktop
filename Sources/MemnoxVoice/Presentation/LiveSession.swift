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
/// without making Memnox the active app and taking their keyboard. It follows the chosen look unless its owner pins it.
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
    static let disclosure = "chevron.right"
}

/// Values more than one part of the live window shares, so its sections match.
private enum LiveStyle {
    static let sectionCornerRadius: CGFloat = 16
    /// Barely there, so a section reads as a shape rather than a box.
    static let sectionEdgeOpacity = 0.035
    /// Just under full ink, so step and helper lines sit below the headline text.
    static let softTextOpacity = 0.88
    /// The window's own page: black in the dark, as the notch is, and white in the light.
    static let page = Color(light: 0xFFFFFF, dark: 0x000000)
    /// A section one step off the page, the notch's card colour in the dark.
    static let section = Color(light: 0xF5F5F7, dark: 0x141518)
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
    /// The notch's model, so a call this session holds can be answered in the window through the same signed path.
    var island: IslandModel?
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
            island: island,
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
    let island: IslandModel?
    let close: () -> Void
    let jump: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        /// A thin flat band along the top in the colour of how the session stands, so it is read before any word.
        static let statusEdge: CGFloat = 3
    }

    /// The beat each part rises on, top to bottom, so the window assembles in reading order.
    private enum Order {
        static let header = 0
        static let conversation = 1
        static let now = 2
        static let steps = 3
        static let helpers = 4
        static let files = 5
        static let dock = 6
    }

    /// Settled when shown, and always settled under Reduce Motion so the window only fades.
    private var settled: Bool { model.shown || reduceMotion }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
            if let view = model.view {
                content(view)
            } else {
                Text("This session is not on the record yet.")
                    .font(Memnox.sans(Memnox.TextSize.callout))
                    .foregroundStyle(Memnox.Palette.muted)
                // No header stands above to take Escape, so the footer's Close answers it.
                LiveFooter(view: nil, jump: jump, close: close, answersEscape: true)
            }
        }
        .padding(Layout.padding)
        .frame(width: LivePanel.width, alignment: .leading)
        .background(surface)
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                .strokeBorder(Memnox.ink(Layout.edgeOpacity), lineWidth: Memnox.Stroke.hairline)
        )
        .shadow(color: .black.opacity(Layout.shadowOpacity), radius: Layout.shadowRadius, x: 0, y: Layout.shadowDrop)
        // Settles in the way the island opens, and stays flat so every button is where it is drawn.
        .scaleEffect(settled ? 1 : Layout.hiddenScale)
        .offset(y: settled ? 0 : Layout.hiddenLift)
        .blur(radius: settled ? 0 : Layout.hiddenBlur)
        .opacity(model.shown ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The conversation leads; what it ran, its helpers and its files fold away below it.
    @ViewBuilder
    private func content(_ view: SessionView) -> some View {
        let talk = view.conversation ?? []
        // Folded beside a conversation, which says most of it, and open when there is none to read.
        let detailsOpen = talk.isEmpty
        let most = talk.isEmpty ? LiveStyle.fullListLength : LiveStyle.sharedListLength
        LiveHeader(view: view, close: close).reveal(model.shown, order: Order.header)
        if !talk.isEmpty {
            LiveConversation(lines: talk, thinking: view.thinking).reveal(model.shown, order: Order.conversation)
        }
        LiveNow(view: view).reveal(model.shown, order: Order.now)
        if !view.steps.isEmpty {
            LiveDisclosure(title: "Latest steps", count: view.steps.count, startsOpen: detailsOpen) {
                LiveStepRows(steps: view.steps, most: most)
            }
            .reveal(model.shown, order: Order.steps)
        }
        if !view.helpers.isEmpty {
            LiveDisclosure(title: "Helpers", count: view.helpers.count, startsOpen: detailsOpen) {
                LiveHelperRows(helpers: view.helpers)
            }
            .reveal(model.shown, order: Order.helpers)
        }
        if !view.files.isEmpty {
            LiveDisclosure(title: "Changed", count: view.files.count, startsOpen: detailsOpen) {
                FileList(files: Array(view.files.prefix(most)), counting: model.shown)
            }
            .reveal(model.shown, order: Order.files)
        }
        Group {
            if let island {
                LiveDock(island: island, session: view.sessionId, spacing: Layout.sectionSpacing) {
                    LiveFooter(view: view, jump: jump, close: close)
                }
            } else {
                LiveFooter(view: view, jump: jump, close: close)
            }
        }
        .reveal(model.shown, order: Order.dock)
    }

    /// Solid and flat, black or white with the chosen look, with a band along the top in the colour of how the session stands.
    private var surface: some View {
        let shape = RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
        return shape.fill(LiveStyle.page)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(statusColour(model.view))
                    .frame(height: Layout.statusEdge)
                    .accessibilityHidden(true)
            }
            .clipShape(shape)
            .animation(.easeInOut(duration: Memnox.Motion.slow), value: model.view?.state)
    }
}

/// The bottom of the window: a call this session holds, answered in place, pinned above the footer while it waits.
private struct LiveDock<Footer: View>: View {
    @ObservedObject var island: IslandModel
    let session: String
    let spacing: CGFloat
    @ViewBuilder let footer: () -> Footer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The newest call this session is waiting on, which may not be the one on the notch's card.
    private var held: HeldCard? {
        island.waiting.newestFirst.first { $0.card.sessionId == session }?.card
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if let held {
                HeldStrip(model: island, card: held)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
            footer()
        }
        .animation(reduceMotion ? .easeOut(duration: Memnox.Motion.quick) : .spring(response: LiveDockMotion.response, dampingFraction: LiveDockMotion.damping), value: held)
    }
}

/// LiveDock's spring, at file scope because a generic type cannot hold stored statics.
private enum LiveDockMotion {
    static let response = 0.45
    static let damping = 0.85
}

/// Each part rises into place a beat after the one above it, so the window assembles itself.
private struct Reveal: ViewModifier {
    let shown: Bool
    let order: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Motion {
        static let hiddenDrop: CGFloat = 18
        static let hiddenBlur: CGFloat = 6
        static let response = 0.55
        static let damping = 0.85
        /// Waits for the window itself to start settling before the first part rises.
        static let firstDelay: TimeInterval = 0.18
        static let delayPerPart: TimeInterval = 0.07
    }

    /// Under Reduce Motion a part only fades, so nothing travels or blurs.
    private var still: Bool { shown || reduceMotion }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: still ? 0 : Motion.hiddenDrop)
            .blur(radius: still ? 0 : Motion.hiddenBlur)
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
private func statusColour(_ view: SessionView?) -> Color {
    view?.status.tint ?? Memnox.Palette.muted
}

/// The card header every floating card wears, with the agent's own logo, how it stands beside the name,
/// and the task it is on underneath.
private struct LiveHeader: View {
    let view: SessionView
    let close: () -> Void

    private static let taskLineLimit = 2
    private static let metaSeparator = "  ·  "

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            CardHeader(title: view.agentName, subtitle: meta, close: close) {
                BrandLogo(agent: view.agent, name: view.agentName, size: FloatingCard.markSize)
            } accessory: {
                StatePill(view: view)
            }
            if let task = view.task {
                Text(task)
                    .font(Memnox.sans(Memnox.TextSize.callout))
                    .foregroundStyle(Memnox.Palette.foreground.opacity(Memnox.Ink.primary))
                    .lineLimit(Self.taskLineLimit)
            }
        }
    }

    private var meta: String? {
        let parts = [view.repository, view.runningIn, SessionText.ago(view.lastActive, now: Date()).map { "active \($0)" }]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: Self.metaSeparator)
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
        .background(RoundedRectangle(cornerRadius: LiveStyle.sectionCornerRadius, style: .continuous).fill(LiveStyle.section))
        .overlay(
            RoundedRectangle(cornerRadius: LiveStyle.sectionCornerRadius, style: .continuous)
                .strokeBorder(Memnox.ink(LiveStyle.sectionEdgeOpacity), lineWidth: Memnox.Stroke.hairline)
        )
    }

    private var now: String {
        if let paused = view.paused { return "Paused: \(paused)" }
        if view.thinking { return "Thinking through its answer" }
        if let last = view.steps.last { return last.text }
        return "Nothing recorded yet"
    }
}

/// The latest steps under their section title, for the session popup.
struct LiveSteps: View {
    let steps: [SessionViewStep]
    let most: Int

    var body: some View {
        LiveSection(title: "Latest steps") { LiveStepRows(steps: steps, most: most) }
    }
}

/// The latest steps, newest at the bottom, each with what kind of thing it touched.
struct LiveStepRows: View {
    let steps: [SessionViewStep]
    let most: Int

    private static let rowSpacing: CGFloat = 5
    private static let iconWidth: CGFloat = 14
    /// The runtime records browser steps, which `StepSurface` does not name yet.
    private static let browserSurface = "browser"

    var body: some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            ForEach(Array(steps.suffix(most).enumerated()), id: \.element.at) { _, step in
                HStack(spacing: Memnox.Spacing.medium) {
                    Image(systemName: icon(step))
                        .font(.system(size: Memnox.TextSize.caption))
                        .frame(width: Self.iconWidth)
                        .foregroundStyle(tint(step))
                        .accessibilityHidden(true)
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
                .accessibilityElement(children: .combine)
                .transition(.move(edge: .bottom).combined(with: .opacity))
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
    /// The tallest part of the window, because the conversation is what the person opened it to read.
    private static let maxHeight: CGFloat = 380
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

private struct LiveHelperRows: View {
    let helpers: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
            ForEach(helpers, id: \.self) { helper in
                Label(helper, systemImage: LiveSymbol.helper)
                    .font(Memnox.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Palette.foreground.opacity(LiveStyle.softTextOpacity))
            }
        }
    }
}

/// LiveDisclosure's measurements, at file scope because a generic type cannot hold stored statics.
private enum LiveDisclosureLayout {
    /// A quarter turn, so the chevron points down once the section is open.
    static let openAngle: Double = 90
    static let response = 0.4
    static let damping = 0.88
}

/// A section that folds under its title, in the same card as every other section, so the record stays
/// one tap away without taking room from the conversation.
private struct LiveDisclosure<Content: View>: View {
    let title: String
    let count: Int
    let content: () -> Content
    @State private var open: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private typealias Layout = LiveDisclosureLayout

    init(title: String, count: Int, startsOpen: Bool, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.count = count
        self.content = content
        _open = State(initialValue: startsOpen)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: LiveStyle.sectionCornerRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            header
            if open {
                content()
                    .padding(.horizontal, Memnox.Spacing.large)
                    .padding(.bottom, Memnox.Spacing.large)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(LiveStyle.section))
        .overlay(shape.strokeBorder(Memnox.ink(LiveStyle.sectionEdgeOpacity), lineWidth: Memnox.Stroke.hairline))
        .clipShape(shape)
    }

    private var header: some View {
        Button(action: toggle) {
            HStack(spacing: Memnox.Spacing.medium) {
                Text(title.uppercased())
                    .font(Memnox.sans(Memnox.TextSize.micro, .semibold))
                    .tracking(LiveSectionLayout.titleTracking)
                    .foregroundStyle(Memnox.ink(LiveSectionLayout.titleOpacity))
                Text(count, format: .number)
                    .font(Memnox.sans(Memnox.TextSize.micro, .medium))
                    .foregroundStyle(Memnox.Palette.muted)
                Spacer(minLength: Memnox.Spacing.small)
                Image(systemName: LiveSymbol.disclosure)
                    .font(.system(size: Memnox.TextSize.micro, weight: .semibold))
                    .foregroundStyle(Memnox.Palette.muted)
                    .rotationEffect(.degrees(open ? Layout.openAngle : 0))
            }
            .padding(Memnox.Spacing.large)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHand()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(title), \(count)"))
        .accessibilityValue(Text(open ? "Shown" : "Folded"))
        .accessibilityAddTraits(.isButton)
        .help(open ? "Fold \(title.lowercased())" : "Show \(title.lowercased())")
    }

    private func toggle() {
        let motion: Animation = reduceMotion
            ? .easeOut(duration: Memnox.Motion.quick)
            : .spring(response: Layout.response, dampingFraction: Layout.damping)
        withAnimation(motion) { open.toggle() }
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
                .foregroundStyle(Memnox.ink(Layout.titleOpacity))
                .padding(.leading, Memnox.Spacing.xSmall)
            content()
                .padding(Memnox.Spacing.large)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: LiveStyle.sectionCornerRadius, style: .continuous).fill(LiveStyle.section))
                .overlay(
                    RoundedRectangle(cornerRadius: LiveStyle.sectionCornerRadius, style: .continuous)
                        .strokeBorder(Memnox.ink(LiveStyle.sectionEdgeOpacity), lineWidth: Memnox.Stroke.hairline)
                )
        }
    }
}

private struct LiveFooter: View {
    let view: SessionView?
    let jump: () -> Void
    let close: () -> Void
    /// Only where no header's close cross already answers Escape, so one key never has two owners.
    var answersEscape = false

    var body: some View {
        HStack(spacing: Memnox.Spacing.medium) {
            Spacer()
            CardButton(title: "Close", icon: LiveSymbol.close, primary: false, action: close)
                .keyboardShortcut(answersEscape ? .cancelAction : nil)
            CardButton(title: jumpLabel, icon: LiveSymbol.openWindow, primary: true, action: jump)
        }
    }

    private var jumpLabel: String {
        guard let app = view?.runningIn else { return "Open its window" }
        return "Open in \(app)"
    }
}
