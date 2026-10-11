import AppKit
import MemnoxVoiceCore
import SwiftUI

/// What the side panel shows, most urgent first: what is waiting on the person, what is working for
/// them now, then every exchange lately by day, each with how it went. One search filters all of it.
struct SideView: View {
    @ObservedObject var model: IslandModel
    @State private var filter = SideFilter.all
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Layout {
        static let cornerRadius: CGFloat = 22
        /// The same concave curve the top notch flows into the menu bar with, here flowing into the screen's left edge.
        static let flare = Island.flare
        static let padding: CGFloat = 10
        static let sectionGap: CGFloat = 14
        /// Faint, so the folded tab is findable without drawing the eye.
        static let tabEdgeInk = 0.22
        /// The contents wait for the panel to be mostly grown, so they never squeeze through a narrow shape.
        static let contentDelay: TimeInterval = 0.12
    }

    var body: some View {
        let open = model.sideOpen
        let shape = SideNotchShape(flare: open ? Layout.flare : SideMotion.tabFlare, radius: Layout.cornerRadius)
        let tab = SideMotion.tab(hovering: model.sideHovering)
        ZStack {
            shape.fill(Memnox.Palette.pinnedDark)
                // A hairline on the folded tab only, so the sliver shows against a dark window behind it.
                .overlay(shape.stroke(Color.white.opacity(open ? 0 : Layout.tabEdgeInk), lineWidth: Memnox.Stroke.hairline))
            if open {
                panel.transition(.opacity.animation(.easeOut(duration: Memnox.Motion.quick).delay(Layout.contentDelay)))
            }
        }
        .frame(width: open ? nil : tab.width, height: open ? nil : tab.height)
        .clipShape(shape)
        // The tab grows out of the middle of the left edge, the way the notch grows down from the top.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
        ForEach(days, id: \.start) { day in
            SideSection(title: day.title, count: nil, tint: nil) {
                ForEach(day.exchanges) { exchange in
                    ExchangeRow(
                        exchange: exchange,
                        opened: model.picked == exchange.id,
                        open: { model.showExchange(exchange.id) },
                        askAgain: { model.askAgain(exchange.question) }
                    )
                }
            }
        }
        if days.isEmpty { SideEmpty(searching: !model.query.trimmingCharacters(in: .whitespaces).isEmpty, query: model.query) }
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

    /// The exchanges that match, grouped by the day they were asked, newest day first.
    private var days: [HistoryDay] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: model.history.matching(model.query)) { calendar.startOfDay(for: $0.askedAt) }
        return grouped.keys.sorted(by: >).map { start in
            HistoryDay(start: start, exchanges: grouped[start]?.sorted { $0.askedAt > $1.askedAt } ?? [], calendar: calendar)
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

/// One day of exchanges, named the way a person says it: today with the time of the newest, yesterday, or the date.
private struct HistoryDay {
    let start: Date
    let exchanges: [Exchange]
    let title: String

    init(start: Date, exchanges: [Exchange], calendar: Calendar) {
        self.start = start
        self.exchanges = exchanges
        let newest = exchanges.first?.askedAt.formatted(date: .omitted, time: .shortened) ?? ""
        if calendar.isDateInToday(start) {
            title = newest.isEmpty ? "Today" : "Today, \(newest)"
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
                    .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
                TextField("Search", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(Memnox.sans(Memnox.TextSize.callout))
                    .foregroundStyle(Color.white)
                    .focused($focused)
                if !model.query.isEmpty {
                    Button("Clear search", systemImage: Symbol.clear) { model.query = "" }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Color.white.opacity(Memnox.Ink.tertiary))
                        .buttonStyle(PressableStyle())
                        .help("Clear search")
                }
            }
            .padding(.horizontal, Memnox.Spacing.large)
            .frame(height: Layout.height)
            .background(RoundedRectangle(cornerRadius: Layout.radius).fill(Color.white.opacity(focused ? Self.focusedFill : Self.fill)))
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            Button { model.sidePinned.toggle() } label: {
                Image(systemName: model.sidePinned ? Symbol.pinned : Symbol.unpinned)
                    .font(.system(size: Memnox.TextSize.footnote, weight: .semibold))
                    .foregroundStyle(model.sidePinned ? Memnox.Palette.primary : Color.white.opacity(Memnox.Ink.secondary))
                    .frame(width: Layout.pinSide, height: Layout.height)
                    .background(RoundedRectangle(cornerRadius: Layout.radius).fill(Color.white.opacity(Self.fill)))
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
                    .foregroundStyle(Color.white.opacity(Memnox.Ink.tertiary))
                if let count {
                    Text("\(count)")
                        .font(Memnox.sans(Memnox.TextSize.footnote, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(Memnox.Ink.tertiary))
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
            .background(RoundedRectangle(cornerRadius: RowStyle.radius).fill(Color.white.opacity(fill)))
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
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    if card.thinking {
                        ShimmerText(text: card.subtitle(now: Date()))
                    } else {
                        Text(card.subtitle(now: Date()))
                            .font(Memnox.sans(Memnox.TextSize.caption))
                            .foregroundStyle(IslandPalette.quiet)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: Self.arrow)
                    .font(.system(size: Memnox.TextSize.caption, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(hovering ? Memnox.Ink.secondary : 0))
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
                        .foregroundStyle(Color.white)
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
                .foregroundStyle(Color.white)
                .frame(width: Layout.markSide, height: Layout.markSide)
                .background(Circle().fill(IslandPalette.red.opacity(Shade.failedMark)))
        } else {
            LogoMark(size: Layout.markSide * Layout.logoScale)
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
                .foregroundStyle(IslandPalette.red.liftedTowardWhite)
                .lineLimit(1)
        } else {
            Text("Answered in \(clock(exchange.elapsed(now: Date()))) \u{00B7} \(exchange.askedAt.formatted(date: .omitted, time: .shortened))")
                .font(Memnox.sans(Memnox.TextSize.caption))
                .foregroundStyle(IslandPalette.quiet)
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
                .foregroundStyle(Color.white.opacity(Memnox.Ink.tertiary))
            Text(searching ? "Nothing mentions \u{201C}\(query)\u{201D}" : "Nothing asked yet")
                .font(Memnox.sans(Memnox.TextSize.callout, .semibold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
            if !searching {
                Text("Press Option Space and ask anything. Every answer stays here, on this Mac.")
                    .font(Memnox.sans(Memnox.TextSize.body))
                    .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
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
                .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
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
                .foregroundStyle(confirming ? IslandPalette.red : Color.white.opacity(Memnox.Ink.secondary))
            }
        }
        .padding(.horizontal, Memnox.Spacing.small)
    }
}
