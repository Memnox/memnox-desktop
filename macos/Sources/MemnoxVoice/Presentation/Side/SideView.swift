import AppKit
import MemnoxVoiceCore
import SwiftUI

/// What the side panel shows, most urgent first: what is waiting on the person, what is working for
/// them now, the turn still running, then what was done lately by day, each with the tool it went through.
/// It lists actions rather than talk, since what Memnox did is what the person comes back to check. One search
/// filters all of it.
struct SideView: View {
    @ObservedObject var model: IslandModel
    @State private var filter = SideFilter.all
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private enum Layout {
        static let cornerRadius: CGFloat = 22
        /// The same concave curve the top notch flows into the menu bar with, here flowing into the screen's left edge.
        static let flare = Island.flare
        static let padding: CGFloat = 10
        static let sectionGap: CGFloat = 14
        /// Faint, so the folded tab is findable without drawing the eye.
        static let tabEdgeInk = 0.22
        /// The open panel's rim in the light; the dark panel needs none, since it stands out from most windows as it is.
        static let lightEdgeInk = 0.12
        /// The contents wait for the panel to be mostly grown, so they never squeeze through a narrow shape.
        static let contentDelay: TimeInterval = 0.12
    }

    var body: some View {
        let open = model.sideOpen
        let shape = SideNotchShape(flare: open ? Layout.flare : SideMotion.tabFlare, radius: Layout.cornerRadius)
        let tab = SideMotion.tab(hovering: model.sideHovering)
        ZStack {
            // The live window's page, so the side panel and every window Memnox puts up read as one family.
            shape.fill(LiveStyle.page)
                // A hairline on the folded tab, so the sliver shows against a window of its own colour behind it, and on the
                // open panel in the light, where it has no shadow to lift it off a white window.
                .overlay(shape.stroke(Memnox.ink(edgeInk(open: open)), lineWidth: Memnox.Stroke.hairline))
            if open {
                panel.transition(.opacity.animation(.easeOut(duration: Memnox.Motion.quick).delay(Layout.contentDelay)))
            }
        }
        .frame(width: open ? nil : tab.width, height: open ? nil : tab.height)
        .clipShape(shape)
        // The tab grows out of the middle of the left edge, the way the notch grows down from the top.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func edgeInk(open: Bool) -> Double {
        guard open else { return Layout.tabEdgeInk }
        return scheme == .light ? Layout.lightEdgeInk : 0
    }

    /// The panel's own contents, laid in only once it has grown, so the tab is just its shape.
    private var panel: some View {
        let needsYou = needsYou
        let working = working
        let days = days
        let shown = showing(needsYou: needsYou, working: working, days: days)
        return VStack(spacing: Memnox.Spacing.regular) {
            SideSearch(model: model)
            filters(needsYou: needsYou.count, working: working.count, history: !days.isEmpty)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Layout.sectionGap) {
                    if shown.shows(.needsYou), !needsYou.isEmpty {
                        SideSection(title: "Needs you", count: needsYou.count, tint: IslandPalette.amber) {
                            ForEach(needsYou, id: \.subject) { card in HeldStrip(model: model, card: card) }
                        }
                    }
                    if shown.shows(.working), !working.isEmpty {
                        SideSection(title: "Working now", count: working.count, tint: IslandPalette.green) {
                            ForEach(working, id: \.sessionId) { card in
                                WorkingRow(card: card) { model.openWindow(card.sessionId, card.host) }
                            }
                        }
                    }
                    if shown.shows(.history) { history(days) }
                }
                .padding(.bottom, Memnox.Spacing.medium)
            }
            SideFooter(model: model)
        }
        .padding(Layout.padding)
        .padding(.vertical, Layout.flare)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// One chip per section that has something in it, so a chip never leads to an empty list.
    private func filters(needsYou: Int, working: Int, history: Bool) -> some View {
        HStack(spacing: Memnox.Spacing.small) {
            chip(.all, count: nil)
            if needsYou > 0 { chip(.needsYou, count: needsYou) }
            if working > 0 { chip(.working, count: working) }
            if history { chip(.history, count: nil) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Memnox.Spacing.xxSmall)
    }

    private func chip(_ choice: SideFilter, count: Int?) -> some View {
        FilterChip(title: choice.title, chosen: filter == choice, count: count) {
            withAnimation(reduceMotion ? nil : .easeOut(duration: Memnox.Motion.quick)) { filter = choice }
        }
    }

    @ViewBuilder private func history(_ days: [HistoryDay]) -> some View {
        if let running = model.history.current, running.mentions(model.query) {
            SideSection(title: "In progress", count: nil, tint: Memnox.Palette.primary) {
                ExchangeRow(
                    exchange: running,
                    opened: model.picked == running.id,
                    open: { model.showExchange(running.id) },
                    askAgain: { model.askAgain(running.question) }
                )
            }
        }
        ForEach(days, id: \.start) { day in
            SideSection(title: day.title, count: nil, tint: nil) {
                ForEach(day.done, id: \.key) { done in
                    ActionRow(
                        action: done.action,
                        question: done.exchange.question,
                        opened: model.picked == done.exchange.id,
                        open: { model.showExchange(done.exchange.id) }
                    )
                }
            }
        }
        if days.isEmpty, model.history.current == nil {
            SideEmpty(searching: !model.query.trimmingCharacters(in: .whitespaces).isEmpty, query: model.query)
        }
    }

    /// The chosen filter, or All once its section has emptied, so an answered call never leaves a blank panel.
    private func showing(needsYou: [HeldCard], working: [SessionCard], days: [HistoryDay]) -> SideFilter {
        switch filter {
        case .needsYou where needsYou.isEmpty, .working where working.isEmpty, .history where days.isEmpty: .all
        default: filter
        }
    }

    /// Every held call waiting, newest first, answered right here through the notch's own path, since each blocks work until the person acts.
    private var needsYou: [HeldCard] {
        model.waiting.newestFirst.map(\.card).filter { mentions($0.who) || mentions($0.what) }
    }

    private var working: [SessionCard] {
        model.working.filter { mentions($0.title) || mentions($0.agentName) || mentions($0.repository ?? "") }
    }

    private func mentions(_ text: String) -> Bool {
        let wanted = model.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return wanted.isEmpty || text.localizedStandardContains(wanted)
    }

    /// What was done in the exchanges that match, grouped by the day it was done, newest first; a turn that only
    /// talked is left out, since its answer is in the notch while it lasts and is not an action to come back to.
    private var days: [HistoryDay] {
        let calendar = Calendar.current
        let done = model.history.matching(model.query).flatMap { exchange in
            exchange.actions.enumerated().map { index, action in DoneAction(exchange: exchange, action: action, index: index) }
        }
        let grouped = Dictionary(grouping: done) { calendar.startOfDay(for: $0.action.at) }
        return grouped.keys.sorted(by: >).map { start in
            HistoryDay(start: start, done: grouped[start]?.sorted { $0.action.at > $1.action.at } ?? [], calendar: calendar)
        }
    }
}

/// The notch turned on its side: flush with the screen's left edge, flowing into it with a concave curve
/// at the top and the bottom, and rounded on the side that faces the work.
private struct SideNotchShape: Shape {
    var flare: CGFloat
    var radius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(flare, radius) }
        set {
            flare = newValue.first
            radius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = rect.minY + flare
        let bottom = rect.maxY - flare
        let edge = rect.minX + flare
        let r = min(radius, max(0, (bottom - top) / 2), max(0, rect.width - flare))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: edge, y: top), control: CGPoint(x: rect.minX, y: top))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: top + r), control: CGPoint(x: rect.maxX, y: top))
        path.addLine(to: CGPoint(x: rect.maxX, y: bottom - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: bottom), control: CGPoint(x: rect.maxX, y: bottom))
        path.addLine(to: CGPoint(x: edge, y: bottom))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY), control: CGPoint(x: rect.minX, y: bottom))
        path.closeSubpath()
        return path
    }
}

/// One thing done, with the exchange that did it, so its row opens that answer.
private struct DoneAction {
    let exchange: Exchange
    let action: TakenAction
    let index: Int

    var key: String { "\(exchange.id.uuidString)#\(index)" }
}

/// One day of what was done, named the way a person says it: today, yesterday, or the date.
private struct HistoryDay {
    let start: Date
    let done: [DoneAction]
    let title: String

    init(start: Date, done: [DoneAction], calendar: Calendar) {
        self.start = start
        self.done = done
        if calendar.isDateInToday(start) {
            title = "Today"
        } else if calendar.isDateInYesterday(start) {
            title = "Yesterday"
        } else {
            title = start.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        }
    }
}

/// The search box and the pin that keeps the panel up while the person works beside it.
private struct SideSearch: View {
    @ObservedObject var model: IslandModel
    @FocusState private var focused: Bool

    private enum Layout {
        static let height: CGFloat = 36
        static let radius: CGFloat = 12
        static let pinSide: CGFloat = 36
    }

    private enum Symbol {
        static let search = "magnifyingglass"
        static let clear = "xmark.circle.fill"
        static let pinned = "pin.fill"
        static let unpinned = "pin"
    }

    private static let fill = 0.08
    private static let focusedFill = 0.12

    var body: some View {
        HStack(spacing: Memnox.Spacing.medium) {
            HStack(spacing: Memnox.Spacing.medium) {
                Image(systemName: Symbol.search)
                    .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                TextField("Search", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(Memnox.sans(Memnox.TextSize.callout))
                    .foregroundStyle(Memnox.Palette.ink)
                    .focused($focused)
                if !model.query.isEmpty {
                    Button("Clear search", systemImage: Symbol.clear) { model.query = "" }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Memnox.ink(Memnox.Ink.tertiary))
                        .buttonStyle(PressableStyle())
                        .help("Clear search")
                }
            }
            .padding(.horizontal, Memnox.Spacing.large)
            .frame(height: Layout.height)
            .background(RoundedRectangle(cornerRadius: Layout.radius).fill(Memnox.ink(focused ? Self.focusedFill : Self.fill)))
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            Button { model.sidePinned.toggle() } label: {
                Image(systemName: model.sidePinned ? Symbol.pinned : Symbol.unpinned)
                    .font(.system(size: Memnox.TextSize.footnote, weight: .semibold))
                    .foregroundStyle(model.sidePinned ? Memnox.Palette.primary : Memnox.ink(Memnox.Ink.secondary))
                    .frame(width: Layout.pinSide, height: Layout.height)
                    .background(RoundedRectangle(cornerRadius: Layout.radius).fill(Memnox.ink(Self.fill)))
            }
            .buttonStyle(PressableStyle())
            .help(model.sidePinned ? "Let it close when you click elsewhere" : "Keep it open while you work")
            .accessibilityLabel(model.sidePinned ? "Unpin the panel" : "Pin the panel open")
        }
    }
}

/// How a section heading and a row are drawn; at file scope because a generic type cannot hold static stored properties.
private enum RowStyle {
    static let headingDot: CGFloat = 6
    static let radius: CGFloat = 12
    static let horizontal: CGFloat = 8
    static let vertical: CGFloat = 7
    /// Every row stands at least this tall, so a one line row and a two line row sit on one rhythm.
    static let minHeight: CGFloat = 44
    static let hoverFill = 0.06
    static let selectedFill = 0.1
    static let markRadius: CGFloat = 7
}

/// A heading, a count where one helps, and the rows under it.
private struct SideSection<Rows: View>: View {
    let title: String
    let count: Int?
    let tint: Color?
    @ViewBuilder let rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
            HStack(spacing: Memnox.Spacing.small) {
                if let tint { Circle().fill(tint).frame(width: RowStyle.headingDot, height: RowStyle.headingDot) }
                Text(title)
                    .font(Memnox.sans(Memnox.TextSize.footnote, .semibold))
                    .foregroundStyle(Memnox.ink(Memnox.Ink.tertiary))
                if let count {
                    Text("\(count)")
                        .font(Memnox.sans(Memnox.TextSize.footnote, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Memnox.ink(Memnox.Ink.tertiary))
                }
            }
            .padding(.horizontal, Memnox.Spacing.medium)
            .padding(.bottom, Memnox.Spacing.xSmall)
            rows
        }
    }
}

/// A row's shape and hover light, shared by every row in the panel.
private struct SideRow<Content: View>: View {
    let selected: Bool
    let action: (() -> Void)?
    @ViewBuilder let content: (Bool) -> Content
    @State private var hovering = false

    var body: some View {
        let row = content(hovering)
            .padding(.horizontal, RowStyle.horizontal)
            .padding(.vertical, RowStyle.vertical)
            .frame(maxWidth: .infinity, minHeight: RowStyle.minHeight, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: RowStyle.radius).fill(Memnox.ink(fill)))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
        if let action {
            Button(action: action) { row }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            row
        }
    }

    private var fill: Double { selected ? RowStyle.selectedFill : hovering && action != nil ? RowStyle.hoverFill : 0 }
}

/// A session working now: who, on what, where and how long, and a click to its own window.
private struct WorkingRow: View {
    let card: SessionCard
    let open: () -> Void

    private static let logoSide: CGFloat = 26
    private static let arrow = "arrow.up.forward"

    var body: some View {
        SideRow(selected: false, action: open) { hovering in
            HStack(spacing: Memnox.Spacing.regular) {
                BrandLogo(agent: card.agent, name: card.agentName, size: Self.logoSide)
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                    Text(card.title)
                        .font(Memnox.sans(Memnox.TextSize.body, .semibold))
                        .foregroundStyle(Memnox.Palette.ink)
                        .lineLimit(1)
                    if card.thinking {
                        ShimmerText(text: card.subtitle(now: Date()))
                    } else {
                        Text(card.subtitle(now: Date()))
                            .font(Memnox.sans(Memnox.TextSize.caption))
                            .foregroundStyle(Memnox.Palette.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: Self.arrow)
                    .font(.system(size: Memnox.TextSize.caption, weight: .semibold))
                    .foregroundStyle(Memnox.ink(hovering ? Memnox.Ink.secondary : 0))
            }
        }
        .help("Bring its window forward")
        .accessibilityLabel("\(card.agentName), \(card.title), \(card.subtitle(now: Date()))")
        .accessibilityHint("Brings its window forward")
    }
}

/// One exchange: the question, then how it went: still answering, answered and how fast, or why it failed.
private struct ExchangeRow: View {
    let exchange: Exchange
    let opened: Bool
    let open: () -> Void
    let askAgain: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Layout {
        static let markSide: CGFloat = 22
        static let dotSide: CGFloat = 7
        /// The Memnox mark sits inside its disc with the margin a logo tile keeps.
        static let logoScale: CGFloat = 0.56
    }

    private enum Symbol {
        static let failed = "exclamationmark"
        static let retry = "arrow.clockwise"
    }

    var body: some View {
        SideRow(selected: opened, action: open) { hovering in
            HStack(spacing: Memnox.Spacing.regular) {
                mark
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                    Text(exchange.question)
                        .font(Memnox.sans(Memnox.TextSize.body, .semibold))
                        .foregroundStyle(Memnox.Palette.ink)
                        .lineLimit(1)
                    detail
                }
                Spacer(minLength: 0)
                if exchange.failed, hovering {
                    Button(action: askAgain) {
                        Label("Ask again", systemImage: Symbol.retry)
                    }
                    .buttonStyle(IslandButton(primary: false))
                } else {
                    dot
                }
            }
        }
        .help(exchange.failed ? "Open what went wrong" : "Open this answer")
        .accessibilityLabel(exchange.question)
        .accessibilityValue(status)
        .accessibilityAction(named: "Ask again", askAgain)
    }

    /// The row's state in words, for VoiceOver, since the dot and the shimmer say it only to the eye.
    private var status: String {
        if exchange.isAnswering { return "Still answering" }
        if let failure = exchange.failure { return "Failed, \(failure)" }
        return "Answered at \(exchange.askedAt.formatted(date: .omitted, time: .shortened))"
    }

    @ViewBuilder private var mark: some View {
        if exchange.failed {
            Image(systemName: Symbol.failed)
                .font(.system(size: Memnox.TextSize.caption, weight: .bold))
                .foregroundStyle(SideInk.onTint)
                .frame(width: Layout.markSide, height: Layout.markSide)
                .background(Circle().fill(IslandPalette.red.opacity(Shade.failedMark)))
        } else {
            LogoMark(size: Layout.markSide * Layout.logoScale)
                // White on the blue disc in either look, as the mark is drawn in ink.
                .environment(\.colorScheme, .dark)
                .frame(width: Layout.markSide, height: Layout.markSide)
                .background(Circle().fill(Memnox.Palette.primary))
        }
    }

    @ViewBuilder private var detail: some View {
        if exchange.isAnswering {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                ShimmerText(text: "Answering, \(clock(exchange.elapsed(now: timeline.date)))")
            }
        } else if let failure = exchange.failure {
            Text(failure)
                .font(Memnox.sans(Memnox.TextSize.caption))
                .foregroundStyle(SideInk.failure)
                .lineLimit(1)
        } else {
            Text("Answered in \(clock(exchange.elapsed(now: Date()))) \u{00B7} \(exchange.askedAt.formatted(date: .omitted, time: .shortened))")
                .font(Memnox.sans(Memnox.TextSize.caption))
                .foregroundStyle(Memnox.Palette.muted)
                .lineLimit(1)
        }
    }

    /// Blue and breathing while it answers, red when it never did; nothing once it is simply done.
    @ViewBuilder private var dot: some View {
        if exchange.isAnswering {
            let dot = Circle().fill(Memnox.Palette.primary).frame(width: Layout.dotSide, height: Layout.dotSide)
            // A still dot under Reduce Motion, since the breathing is decoration and the caption already says answering.
            if reduceMotion { dot } else { dot.modifier(PulseEffect()) }
        } else if exchange.failed {
            Circle().fill(IslandPalette.red).frame(width: Layout.dotSide, height: Layout.dotSide)
        }
    }

    private enum Shade {
        static let failedMark = 0.85
    }
}

/// One thing done: the tool it went through as its own logo, what was done in a few words, and what was asked for it.
private struct ActionRow: View {
    let action: TakenAction
    let question: String
    let opened: Bool
    let open: () -> Void

    private enum Layout {
        static let markSide: CGFloat = 26
        static let symbolSize: CGFloat = 12
    }

    var body: some View {
        let words = ActionWords(action)
        SideRow(selected: opened, action: open) { _ in
            HStack(spacing: Memnox.Spacing.regular) {
                mark(words)
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                    Text(words.title)
                        .font(Memnox.sans(Memnox.TextSize.body, .semibold))
                        .foregroundStyle(Memnox.Palette.ink)
                        .lineLimit(1)
                    Text(action.about ?? question)
                        .font(Memnox.sans(Memnox.TextSize.caption))
                        .foregroundStyle(Memnox.Palette.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(action.at.formatted(date: .omitted, time: .shortened))
                    .font(Memnox.sans(Memnox.TextSize.caption).monospacedDigit())
                    .foregroundStyle(Memnox.ink(Memnox.Ink.tertiary))
            }
        }
        .help("You asked: \(question)")
        .accessibilityLabel("\(words.title), \(action.about ?? question)")
        .accessibilityValue(action.at.formatted(date: .omitted, time: .shortened))
    }

    /// A toolkit's own logo where it went out through one, else the symbol for what Memnox did itself.
    @ViewBuilder private func mark(_ words: ActionWords) -> some View {
        if let toolkit = action.toolkit {
            ToolMark(toolkit: toolkit, side: Layout.markSide)
        } else {
            Image(systemName: words.symbol)
                .font(.system(size: Layout.symbolSize, weight: .semibold))
                .foregroundStyle(SideInk.onTint)
                .frame(width: Layout.markSide, height: Layout.markSide)
                .background(RoundedRectangle(cornerRadius: RowStyle.markRadius, style: .continuous).fill(Memnox.Palette.primary))
        }
    }
}

/// What an action is called in the list and the symbol drawn for it, read off the tool it used.
struct ActionWords {
    let title: String
    let symbol: String

    /// Memnox's own tools by the name the runtime gives them.
    private enum Own: String {
        case startSession = "start_session"
        case sendInstruction = "send_instruction"
        case watchFor = "watch_for"
        case pauseSession = "pause_session"
        case show
        case walkThrough = "walk_through"
        case typeInApp = "type_in_app"
        case controlApp = "control_app"
        case answerQuestion = "answer_question"
        case searchWeb = "search_web"
        case openLink = "open_link"
        case createFolder = "create_folder"
        case signIn = "sign_in"
    }

    init(_ action: TakenAction) {
        if let toolkit = action.toolkit {
            let tool = ToolkitName.of(toolkit)
            switch WorkDraftKind(rawValue: action.kind ?? "") ?? .other {
            case .message: title = "Sent a message on \(tool)"
            case .comment: title = "Commented on \(tool)"
            case .email: title = "Sent an email"
            case .issue: title = "Filed an issue on \(tool)"
            case .event: title = "Added an event to \(tool)"
            case .page: title = "Wrote a page in \(tool)"
            case .other: title = "Used \(tool)"
            }
            symbol = "paperplane.fill"
            return
        }
        switch Own(rawValue: action.tool) {
        case .startSession: (title, symbol) = ("Started an agent", "play.fill")
        case .sendInstruction: (title, symbol) = ("Told an agent", "arrow.turn.down.right")
        case .watchFor: (title, symbol) = ("Watching an agent", "eye.fill")
        case .pauseSession: (title, symbol) = ("Paused an agent", "pause.fill")
        case .show: (title, symbol) = ("Showed you", "rectangle.on.rectangle")
        case .walkThrough: (title, symbol) = ("Walked you through", "figure.walk")
        case .typeInApp: (title, symbol) = ("Typed in an app", "keyboard.fill")
        case .controlApp: (title, symbol) = ("Used an app", "cursorarrow.click")
        case .answerQuestion: (title, symbol) = ("Answered an agent", "bubble.left.fill")
        case .searchWeb: (title, symbol) = ("Searched Google", "magnifyingglass")
        case .openLink: (title, symbol) = ("Opened a link", "link")
        case .createFolder: (title, symbol) = ("Made a folder", "folder.fill")
        case .signIn: (title, symbol) = ("Signed in to a tool", "person.badge.key.fill")
        case .none: (title, symbol) = ("Did \(action.tool.replacingOccurrences(of: "_", with: " "))", "bolt.fill")
        }
    }
}

/// Nothing to list: how to start, or that the search found nothing.
private struct SideEmpty: View {
    let searching: Bool
    let query: String

    private static let topRoom: CGFloat = 40
    private static let symbol = "text.bubble"

    var body: some View {
        VStack(spacing: Memnox.Spacing.medium) {
            Image(systemName: Self.symbol)
                .font(.system(size: Memnox.TextSize.title))
                .foregroundStyle(Memnox.ink(Memnox.Ink.tertiary))
            Text(searching ? "Nothing mentions \u{201C}\(query)\u{201D}" : "Nothing done yet")
                .font(Memnox.sans(Memnox.TextSize.callout, .semibold))
                .foregroundStyle(Memnox.Palette.ink)
                .multilineTextAlignment(.center)
            if !searching {
                Text("Press Option Space and ask Memnox to do something. What it does is listed here, on this Mac.")
                    .font(Memnox.sans(Memnox.TextSize.body))
                    .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Self.topRoom)
        .padding(.horizontal, Memnox.Spacing.xLarge)
    }
}

/// How to ask, and clearing the history, which asks once more before it goes since it cannot come back.
private struct SideFooter: View {
    @ObservedObject var model: IslandModel
    @State private var confirming = false

    private static let keycapSpacing: CGFloat = 3
    /// Long enough to read "Clear all?" and press it, short enough that a stray click is forgotten.
    private static let confirmFor: TimeInterval = 3
    private static let nanosecondsPerSecond: TimeInterval = 1_000_000_000

    var body: some View {
        HStack(spacing: Memnox.Spacing.small) {
            HStack(spacing: Self.keycapSpacing) {
                Keycap(label: "\u{2325}")
                Keycap(label: "Space")
            }
            Text("to ask")
                .font(Memnox.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
            Spacer()
            if !model.history.exchanges.isEmpty {
                Button(confirming ? "Clear all?" : "Clear history") {
                    if confirming {
                        confirming = false
                        model.forgetHistory()
                    } else {
                        confirming = true
                        Task {
                            try? await Task.sleep(nanoseconds: UInt64(Self.confirmFor * Self.nanosecondsPerSecond))
                            confirming = false
                        }
                    }
                }
                .buttonStyle(PressableStyle())
                .font(Memnox.sans(Memnox.TextSize.footnote, .medium))
                .foregroundStyle(confirming ? SideInk.failure : Memnox.ink(Memnox.Ink.secondary))
            }
        }
        .padding(.horizontal, Memnox.Spacing.small)
    }
}

/// The panel's colours that are not ink: white on a coloured mark, and red text that keeps 4.5 to 1 on either page.
private enum SideInk {
    static let onTint = Color.white
    /// The island's red lifted on the dark page and deepened on the light one, so a failure reads as text on both.
    static let failure = Color(light: 0xC0213A, dark: 0xF77C86)
}
