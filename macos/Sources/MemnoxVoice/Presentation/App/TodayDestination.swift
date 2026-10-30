import Combine
import MemnoxVoiceCore
import SwiftUI

/// What needs the person today, most urgent first, read off what the window already holds: the calls waiting on the
/// island, the sessions, what the agents did since midnight, the agents outside Memnox and what only the person can do.
/// Every answer to a held call goes through the island's own path, so an allow is signed with Touch ID exactly as there.
struct TodayDestination: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var island: IslandModel
    let home: HomeModel?
    let agents: AgentsScreen?
    let activity: ActivityScreen?
    let width: WidthClass

    @State private var tab: TodayTab = .overview
    @State private var hidden: Set<TodaySection> = []
    @State private var everyUrgent = false
    /// Bumped when the home, the agents or the activity change, since each is optional and so not observed directly.
    @State private var tick = 0
    @FocusState private var focused: Bool

    /// The window reads the clock this often, so ages and the synced time stay true while it is open.
    private static let clockSeconds: TimeInterval = 15

    private static let columns = [
        WorkColumn(title: "", width: WorkTable.numberWidth), WorkColumn(title: "What", width: nil),
        WorkColumn(title: "From", width: WorkTable.fromWidth), WorkColumn(title: "When", width: WorkTable.whenWidth),
        WorkColumn(title: "State", width: WorkTable.stateWidth),
    ]

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.clockSeconds)) { context in
            page(now: context.date)
        }
        .onReceive(changes) { _ in tick += 1 }
        .task { await read() }
        .task(id: activity?.activity.live.count ?? 0) {
            // A row arriving live is a name only, so the day is read again to show it whole.
            if (activity?.activity.live.count ?? 0) > 0 { await readActivity() }
        }
    }

    private var changes: AnyPublisher<Void, Never> {
        let publishers: [AnyPublisher<Void, Never>] = [home?.objectWillChange.eraseToAnyPublisher(),
                                                       agents?.objectWillChange.eraseToAnyPublisher(),
                                                       activity?.objectWillChange.eraseToAnyPublisher()]
            .compactMap { $0 }
        return Publishers.MergeMany(publishers).eraseToAnyPublisher()
    }

    private func page(now: Date) -> some View {
        let sources = self.sources
        let overview = TodayBoard.overview(sources, now: now)
        let rows = activity?.activity.rows ?? []
        let lists: [TodayTab: [TodayItem]] = [
            .overview: overview,
            .done: TodayBoard.done(rows, now: now),
            .handoffs: TodayBoard.handoffs(sources),
            .log: TodayBoard.log(rows, now: now),
        ]
        let items = lists[tab] ?? []
        let open = items.first { $0.id == shell.inspecting }
        return InspectorLayout(width: width, title: TodayLines.position(of: open?.id, in: items), close: { shell.inspecting = nil }) {
            ShellScroll(width: width) {
                header(overview, now: now)
                CountTabs(tabs: TodayTab.allCases.map { ($0, $0.title, lists[$0]?.count ?? 0) }, chosen: tab) { chosen in
                    tab = chosen
                    shell.inspecting = nil
                }
                if tab == .overview { strip(overview, now: now) }
                table(items, now: now)
            }
        } detail: {
            if let open { panel(open, in: items, now: now) }
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in key(press, items: items) }
        .onAppear { focused = true }
    }

    // MARK: Reading

    private var sources: TodaySources {
        _ = tick
        let held = island.waiting.entries.map { entry in
            TodayHeld(subject: entry.card.subject, agent: entry.card.agent, who: entry.card.who, what: entry.card.what,
                      why: entry.card.why, at: entry.card.at, team: entry.card.team, sessionId: entry.card.sessionId)
        }
        return TodaySources(held: held, sessions: island.cards, activity: activity?.activity.rows ?? [],
                            agents: agents?.agents.agents ?? [], owed: home?.home?.needsYou ?? [], ready: home?.home?.ready)
    }

    private func read() async {
        home?.refresh()
        if shell.supports("agents") == true { await agents?.agents.refresh() }
        await readActivity()
    }

    private func readActivity() async {
        guard shell.supports("activity") == true, let activity else { return }
        let midnight = Calendar.current.startOfDay(for: Date())
        await activity.activity.show(ActivityFilter(since: ISO8601DateFormatter().string(from: midnight)))
    }

    // MARK: Header and strip

    private func header(_ overview: [TodayItem], now: Date) -> some View {
        let needYou = overview.filter { $0.section == .needsYou }.count
        let next = overview.filter { $0.section == .next }.count
        // No Start deep work button: nothing in the runtime maps to one, so none is drawn.
        return PageTitle(title: "Today", subtitle: TodayLines.headline(now, needYou: needYou, next: next,
                                                                        openProjects: TodayLines.openProjects(island.cards)))
    }

    private func strip(_ overview: [TodayItem], now: Date) -> some View {
        let needYou = overview.filter { $0.section == .needsYou }
        let shown = everyUrgent ? needYou.count : min(needYou.count, TodayBoard.urgentShown)
        return WorkStrip {
            StateMark(needYou.isEmpty ? TodayState.done : TodayState.needsYou)
                .hidden(needYou.isEmpty)
            Text(TodayLines.strip(needYou: needYou.count, shown: shown))
                .foregroundStyle(Memnox.Console.foreground)
            if let waits = TodayLines.waits(needYou) { Text(waits) }
            Spacer(minLength: Memnox.Spacing.medium)
            Text(TodayLines.synced(island.cardsReadAt ?? now))
                .font(Memnox.Console.code(Memnox.Console.TextSize.label))
                .foregroundStyle(Memnox.Console.faint)
        }
    }

    // MARK: The table

    @ViewBuilder private func table(_ items: [TodayItem], now: Date) -> some View {
        if items.isEmpty {
            empty
        } else if tab == .overview {
            VStack(alignment: .leading, spacing: ShellMetrics.sectionSpacing) {
                ForEach(TodayBoard.sections(items), id: \.section) { group in
                    section(group.section, group.items, all: items, now: now)
                }
            }
        } else {
            ShellPanel {
                WorkTableHead(columns: Self.columns)
                rows(items, all: items, now: now)
            }
        }
    }

    private func section(_ section: TodaySection, _ held: [TodayItem], all: [TodayItem], now: Date) -> some View {
        let folded = hidden.contains(section)
        let cut = section == .needsYou && !everyUrgent && held.count > TodayBoard.urgentShown
        let shown = cut ? Array(held.prefix(TodayBoard.urgentShown)) : held
        return ShellSection(title: "\(section.title) \u{00B7} \(held.count)") {
            Button(folded ? "Show" : "Hide") {
                withAnimation(.snappy(duration: Memnox.Motion.quick)) {
                    if folded { hidden.remove(section) } else { hidden.insert(section) }
                }
            }
            .buttonStyle(KitButton(kind: .secondary))
        } content: {
            if !folded {
                ShellPanel {
                    WorkTableHead(columns: Self.columns)
                    rows(shown, all: all, now: now)
                }
                if cut { GoLink("Show all \(held.count)") { everyUrgent = true } }
            }
        }
    }

    private func rows(_ shown: [TodayItem], all: [TodayItem], now: Date) -> some View {
        ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
            if index > 0 { ShellDivider() }
            TodayRow(item: item, number: (all.firstIndex { $0.id == item.id } ?? index) + 1, now: now,
                     chosen: shell.inspecting == item.id) {
                shell.inspecting = item.id
                focused = true
            }
        }
    }

    @ViewBuilder private var empty: some View {
        switch tab {
        case .overview:
            EmptyState(symbol: "sun.max", title: "Nothing needs you today",
                       detail: "When an agent asks first, stops, or hands back to you, it waits here, the most urgent first.")
        case .done:
            EmptyState(symbol: "checkmark.circle", title: "Nothing done yet today",
                       detail: "What your agents run today shows here as it goes through, newest first.")
        case .handoffs:
            EmptyState(symbol: "arrow.uturn.left", title: "Nothing handed back",
                       detail: "A session that finished its turn and waits on you shows here, with the way back into it.")
        case .log:
            EmptyState(symbol: "list.bullet.rectangle", title: "Nothing in today's record",
                       detail: shell.supports("activity") == true
                           ? "Every action your agents take today is written here with what your rules decided."
                           : "This Mac's runtime does not answer activity yet, so today's record cannot be read.")
        }
    }

    // MARK: The panel

    private func panel(_ item: TodayItem, in items: [TodayItem], now: Date) -> some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xLarge) {
            HStack(spacing: Memnox.Spacing.small) {
                stepButton("chevron.up", "The item above", enabled: items.first?.id != item.id) { step(-1, items) }
                stepButton("chevron.down", "The item below", enabled: items.last?.id != item.id) { step(1, items) }
                Spacer(minLength: 0)
                Text("Up and Down move, a letter decides, Escape closes")
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.label))
                    .foregroundStyle(Memnox.Console.faint)
            }
            Text(item.title)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.large, .semibold))
                .foregroundStyle(Memnox.Console.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            StateMark(item.state)
            FactList(facts: facts(item, now: now))
            block("RECOMMENDATION") {
                Text(item.recommendation ?? TodayLines.noRecommendation)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
                    .foregroundStyle(item.recommendation == nil ? Memnox.Console.muted : Memnox.Console.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            block("DECIDE") {
                if item.choices.isEmpty {
                    Text(TodayLines.noChoices)
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
                        .foregroundStyle(Memnox.Console.muted)
                } else {
                    VStack(spacing: Memnox.Spacing.small) {
                        ForEach(item.choices, id: \.key) { choice in
                            ChoiceRow(choice: choice, signs: signs(choice, item)) { decide(choice, item, in: items) }
                        }
                    }
                    .disabled(busy(item))
                }
            }
        }
    }

    private func facts(_ item: TodayItem, now: Date) -> [(String, String)] {
        var facts: [(String, String)] = [("From", item.agentName), ("Waiting", TodayLines.waited(item.since, now: now))]
        if let detail = item.detail { facts.append(("About", detail)) }
        if case .held = item.kind, let card = card(item) {
            facts.append(("Signed", HeldSigning.line(touchID: card.touchID, actionDigest: card.actionDigest)))
        }
        return facts
    }

    private func block<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.regular) {
            Text(title)
                .font(Memnox.Console.code(Memnox.Console.TextSize.label, .medium))
                .tracking(Memnox.Console.headingTracking)
                .foregroundStyle(Memnox.Console.faint)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func stepButton(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: Memnox.TextSize.footnote, weight: .semibold))
                .foregroundStyle(Memnox.Console.muted)
                .frame(width: InspectorSize.closeSide, height: InspectorSize.closeSide)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverLight(radius: Memnox.Console.controlRadius, inset: 0)
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }

    // MARK: Acting

    private func key(_ press: KeyPress, items: [TodayItem]) -> KeyPress.Result {
        switch press.key {
        case .downArrow:
            step(1, items)
            return .handled
        case .upArrow:
            step(-1, items)
            return .handled
        default:
            guard press.modifiers.isEmpty, let letter = press.characters.first, let open = items.first(where: { $0.id == shell.inspecting }),
                  let choice = TodayBoard.choice(for: letter, in: open), !busy(open) else { return .ignored }
            decide(choice, open, in: items)
            return .handled
        }
    }

    private func step(_ offset: Int, _ items: [TodayItem]) {
        guard let next = TodayBoard.step(from: shell.inspecting, by: offset, in: items) else { return }
        // Moving onto a row folded away opens it, so the open item is always on screen.
        if let item = items.first(where: { $0.id == next }), let section = item.section {
            hidden.remove(section)
            if section == .needsYou, (items.firstIndex { $0.id == next } ?? 0) >= TodayBoard.urgentShown { everyUrgent = true }
        }
        shell.inspecting = next
    }

    private func decide(_ choice: TodayChoice, _ item: TodayItem, in items: [TodayItem]) {
        switch choice.action {
        case .answer(let answer):
            guard let card = card(item) else { return }
            // The item leaves once answered, so the one after it opens rather than nothing.
            let after = TodayBoard.step(from: item.id, by: 1, in: items)
            // The same three steps the island's buttons take, so its bookkeeping and Touch ID sheet behave as for a tap there.
            island.answering = answer != .deny
            island.pressed = card.subject
            island.answer(card, answer)
            shell.inspecting = after == item.id ? nil : after
        case .handOver:
            if let ready = home?.home?.ready { home?.handOver(ready) }
        case .protect:
            if let home, let agent = item.agent { agents?.protect([agent], with: home) }
        case .openConversation:
            if let session = item.sessionId { island.watchLive(session, host(session)) }
        case .findInApp:
            if let session = item.sessionId { island.openWindow(session, host(session)) }
        case .openActivity:
            shell.go(WindowRoute(.governance, tab: "activity"))
        }
    }

    private func card(_ item: TodayItem) -> HeldCard? {
        island.waiting.entries.first { "held:\($0.subject)" == item.id }?.card
    }

    private func host(_ session: String) -> DisplayHost? {
        island.cards.first { $0.sessionId == session }?.host
    }

    /// An allow is signed unless the daemon placed the call inside its session, which the button says before a press.
    private func signs(_ choice: TodayChoice, _ item: TodayItem) -> Bool {
        guard case .answer(let answer) = choice.action, answer != .deny else { return false }
        return card(item)?.touchID ?? true
    }

    private func busy(_ item: TodayItem) -> Bool {
        if case .held = item.kind { return island.answering || island.settledNote != nil }
        if item.kind == .handOver { return home?.handingOver ?? false }
        if item.kind == .unprotected { return home?.protecting ?? false }
        return false
    }
}

/// One numbered line of the table: what, with its muted line under it, who it is from, how long ago, and its state.
private struct TodayRow: View {
    let item: TodayItem
    let number: Int
    let now: Date
    let chosen: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: Memnox.Spacing.large) {
                Text("\(number)")
                    .font(Memnox.Console.code(Memnox.Console.TextSize.label))
                    .foregroundStyle(Memnox.Console.faint)
                    .frame(width: WorkTable.numberWidth, alignment: .leading)
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                    Text(item.title)
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                        .foregroundStyle(Memnox.Console.foreground)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let under = TodayLines.under(item) {
                        Text(under)
                            .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                            .foregroundStyle(Memnox.Console.muted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: Memnox.Spacing.small) {
                    BrandLogo(agent: item.agent, name: item.agentName, size: WorkTable.logo)
                    Text(item.agentName)
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                        .foregroundStyle(Memnox.Console.foreground)
                        .lineLimit(1)
                }
                .frame(width: WorkTable.fromWidth, alignment: .leading)
                Text(TodayLines.age(item.since, now: now) ?? "")
                    .font(Memnox.Console.code(Memnox.Console.TextSize.label))
                    .foregroundStyle(Memnox.Console.muted)
                    .frame(width: WorkTable.whenWidth, alignment: .leading)
                StateMark(item.state)
                    .frame(width: WorkTable.stateWidth, alignment: .leading)
            }
            .padding(.horizontal, ShellMetrics.rowPaddingH)
            .padding(.vertical, ShellMetrics.rowPaddingV)
            .background(chosen ? Memnox.Console.active : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressDip())
        .hoverLight(radius: 0, inset: 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(number). \(item.title), from \(item.agentName), \(item.state.label)")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// One choice in the panel: its letter on a key, its words, Touch ID where the allow is signed, and the runtime's
/// recommendation marked where it gave one.
private struct ChoiceRow: View {
    let choice: TodayChoice
    let signs: Bool
    let press: () -> Void

    private static let keySide: CGFloat = 22

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous)
        Button(action: press) {
            HStack(spacing: Memnox.Spacing.regular) {
                Text(String(choice.key))
                    .font(Memnox.Console.code(Memnox.Console.TextSize.label, .medium))
                    .foregroundStyle(Memnox.Console.muted)
                    .frame(width: Self.keySide, height: Self.keySide)
                    .background(Memnox.Console.keycap, in: shape)
                    .overlay(shape.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
                Text(choice.title)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                    .foregroundStyle(Memnox.Console.foreground)
                if signs {
                    Image(systemName: "touchid")
                        .font(.system(size: Memnox.TextSize.footnote, weight: .medium))
                        .foregroundStyle(Memnox.Console.muted)
                        .accessibilityLabel("Signed with Touch ID")
                }
                Spacer(minLength: Memnox.Spacing.small)
                if choice.recommended { StatusWord(.good, "Recommended") }
            }
            .padding(.horizontal, Memnox.Spacing.regular)
            .frame(height: Memnox.Console.fieldHeight)
            .background(Memnox.Console.card, in: shape)
            .overlay(shape.strokeBorder(choice.recommended ? Memnox.Console.primary : Memnox.Console.panelEdge,
                                        lineWidth: Memnox.Stroke.hairline))
            .contentShape(shape)
        }
        .buttonStyle(PressDip())
        .hoverLight(radius: Memnox.Console.controlRadius, inset: 0)
        .help("Press \(String(choice.key))")
        .accessibilityLabel("\(choice.title)\(choice.recommended ? ", recommended" : "")")
        .accessibilityHint("Press \(String(choice.key))")
    }
}

private extension View {
    /// Keeps the place of a view it hides, so the strip does not shift as what waits comes and goes.
    @ViewBuilder func hidden(_ hide: Bool) -> some View {
        if hide { self.hidden() } else { self }
    }
}
