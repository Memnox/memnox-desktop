import AppKit
import MemnoxVoiceCore
import SwiftUI

/// What the live window shows below its brief, one at a time so each has the room it needs.
enum LiveTab: String, CaseIterable, Identifiable {
    case conversation = "Conversation"
    case changes = "Changes"
    case activity = "Activity"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .conversation: return "bubble.left.and.bubble.right"
        case .changes: return "plusminus"
        case .activity: return "list.bullet.rectangle"
        }
    }

    /// The conversation when there is one, else what it changed, else what it ran.
    static func first(for view: SessionView) -> LiveTab {
        if !(view.conversation ?? []).isEmpty { return .conversation }
        if !view.files.isEmpty { return .changes }
        return .activity
    }
}

/// Lets the borderless window be moved by dragging where this sits, as a title bar moves a window.
struct WindowDragArea: NSViewRepresentable {
    final class Handle: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    }

    func makeNSView(context: Context) -> Handle { Handle() }
    func updateNSView(_ nsView: Handle, context: Context) {}
}

/// What the session was asked, the follow up it is on now, and what is waiting on the person, read before anything else.
struct LiveBrief: View {
    let view: SessionView

    private enum Layout {
        static let askLineLimit = 3
        static let followUpLineLimit = 3
        static let labelTracking: CGFloat = 0.8
        static let labelOpacity = 0.45
        static let accentWidth: CGFloat = 2
    }

    private enum Symbol {
        static let followUp = "arrow.turn.down.right"
        static let waiting = "hand.raised.fill"
    }

    private var asked: String? { SessionReading.readable(view.task) }
    private var followUp: String? {
        guard let latest = SessionReading.readable(view.lastAsk), latest != asked else { return nil }
        return latest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.regular) {
            if let asked {
                VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                    label("Asked")
                    Text(asked)
                        .font(Memnox.sans(Memnox.TextSize.callout, .medium))
                        .foregroundStyle(Memnox.Palette.foreground)
                        .lineLimit(Layout.askLineLimit)
                        .textSelection(.enabled)
                }
            }
            if let followUp {
                HStack(alignment: .top, spacing: Memnox.Spacing.medium) {
                    Rectangle().fill(Memnox.Palette.primary).frame(width: Layout.accentWidth)
                    VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                        Label("Follow-up, on it now", systemImage: Symbol.followUp)
                            .font(Memnox.sans(Memnox.TextSize.micro, .semibold))
                            .foregroundStyle(Memnox.Palette.primary)
                        Text(followUp)
                            .font(Memnox.sans(Memnox.TextSize.body))
                            .foregroundStyle(Memnox.Palette.foreground.opacity(Memnox.Ink.primary))
                            .lineLimit(Layout.followUpLineLimit)
                            .textSelection(.enabled)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if view.waitingOnYou > 0 {
                Label(view.waitingOnYou == 1 ? "One call is waiting on you" : "\(view.waitingOnYou) calls are waiting on you",
                      systemImage: Symbol.waiting)
                    .font(Memnox.sans(Memnox.TextSize.footnote, .semibold))
                    .foregroundStyle(Memnox.Palette.warm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Memnox.sans(Memnox.TextSize.micro, .semibold))
            .tracking(Layout.labelTracking)
            .foregroundStyle(Memnox.ink(Layout.labelOpacity))
    }
}

/// The three tabs as one capsule, each with its count, the way a segmented control reads.
struct LiveTabBar: View {
    @Binding var tab: LiveTab
    let counts: [LiveTab: Int]
    @Namespace private var lit

    private enum Layout {
        static let height: CGFloat = 30
        static let inset: CGFloat = 3
        static let trackInk = 0.06
        static let pickedInk = 0.12
        static let countInk = 0.5
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(LiveTab.allCases) { each in
                Button { withAnimation(.snappy) { tab = each } } label: {
                    HStack(spacing: Memnox.Spacing.small) {
                        Image(systemName: each.symbol)
                        Text(each.rawValue)
                        if let count = counts[each], count > 0 {
                            Text(count, format: .number)
                                .foregroundStyle(Memnox.ink(Layout.countInk))
                                .contentTransition(.numericText(value: Double(count)))
                        }
                    }
                    .font(Memnox.sans(Memnox.TextSize.footnote, tab == each ? .semibold : .medium))
                    .foregroundStyle(tab == each ? Memnox.Palette.foreground : Memnox.Palette.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: Layout.height - Layout.inset * 2)
                    .background {
                        if tab == each {
                            Capsule().fill(Memnox.ink(Layout.pickedInk)).matchedGeometryEffect(id: "tab", in: lit)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .pointingHand()
                .accessibilityAddTraits(tab == each ? .isSelected : [])
            }
        }
        .padding(Layout.inset)
        .background(Capsule().fill(Memnox.ink(Layout.trackInk)))
    }
}

/// An agent's reply drawn as markdown means it: headings, lists, code and inline marks, never the marks themselves.
struct ReplyView: View {
    let text: String

    private enum Layout {
        static let blockSpacing: CGFloat = 7
        static let lineSpacing: CGFloat = 2
        static let bulletWidth: CGFloat = 16
        static let codeRadius: CGFloat = 8
        static let codeInk = 0.06
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.blockSpacing) {
            ForEach(Array(ReplyBlock.of(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let words):
                    inline(words).font(Memnox.sans(Memnox.TextSize.callout, .semibold))
                        .foregroundStyle(Memnox.Palette.foreground)
                        .padding(.top, Memnox.Spacing.xSmall)
                case .paragraph(let words):
                    inline(words)
                case .bullet(let words):
                    marked("\u{2022}", words)
                case .numbered(let number, let words):
                    marked("\(number).", words)
                case .code(let code):
                    Text(code)
                        .font(.system(size: Memnox.TextSize.caption, design: .monospaced))
                        .foregroundStyle(Memnox.Palette.foreground.opacity(Memnox.Ink.primary))
                        .padding(Memnox.Spacing.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Layout.codeRadius, style: .continuous).fill(Memnox.ink(Layout.codeInk)))
                }
            }
        }
        .font(Memnox.sans(Memnox.TextSize.body))
        .foregroundStyle(Memnox.Palette.foreground.opacity(Memnox.Ink.primary))
        .lineSpacing(Layout.lineSpacing)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }

    private func marked(_ mark: String, _ words: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(mark).foregroundStyle(Memnox.Palette.muted).frame(width: Layout.bulletWidth, alignment: .leading)
            inline(words)
        }
    }

    /// Bold, italics, code and links as they are meant; words that do not read as markdown stay as written.
    private func inline(_ words: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return Text((try? AttributedString(markdown: words, options: options)) ?? AttributedString(words))
    }
}

/// The whole conversation as a chat, the way the agent's own terminal shows it: the opening ask and each follow-up
/// as the person's bubbles, the agent's replies laid out, the tools it ran between two replies folded into one
/// line that opens into each of them, and while it works a line of how long it has been at it.
struct LiveTalk: View {
    let lines: [ConversationLine]
    let thinking: Bool

    private enum Layout {
        static let lineSpacing: CGFloat = 14
        static let personIndent: CGFloat = 56
        static let bubbleRadius: CGFloat = 14
        static let bubbleInk = 0.28
        static let scrollDuration: TimeInterval = 0.35
        static let bottom = "bottom"
    }

    /// The conversation folded into what a person reads: each run of tool calls is one block.
    private var blocks: [TalkBlock] { TalkBlock.of(lines) }

    /// The first thing the person said opened the session; everything after it is a follow-up.
    private var firstAsk: Int? { lines.firstIndex { LineAuthor(rawValue: $0.who) == .person } }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: Layout.lineSpacing) {
                    ForEach(blocks) { block in row(block) }
                    if thinking { LiveWorkingLine(since: lastAsk) }
                    Color.clear.frame(height: 1).id(Layout.bottom)
                }
                .padding(.trailing, Memnox.Spacing.small)
            }
            .onAppear { reader.scrollTo(Layout.bottom, anchor: .bottom) }
            .onChange(of: lines) { _, _ in
                withAnimation(.easeOut(duration: Layout.scrollDuration)) { reader.scrollTo(Layout.bottom, anchor: .bottom) }
            }
        }
    }

    /// When the person last spoke, which is when the agent started on what it is doing now.
    private var lastAsk: Date? {
        lines.last { LineAuthor(rawValue: $0.who) == .person }.flatMap { LiveClock.date($0.at) }
    }

    @ViewBuilder
    private func row(_ block: TalkBlock) -> some View {
        switch block.kind {
        case .person(let line, let index):
            VStack(alignment: .trailing, spacing: Memnox.Spacing.xSmall) {
                Text(index == firstAsk ? "You asked" : "You")
                    .font(Memnox.sans(Memnox.TextSize.micro, .semibold))
                    .foregroundStyle(index == firstAsk ? Memnox.Palette.muted : Memnox.Palette.primary)
                Text(SessionReading.readable(line.text) ?? line.text)
                    .font(Memnox.sans(Memnox.TextSize.body))
                    .foregroundStyle(Memnox.Palette.foreground)
                    .padding(.horizontal, Memnox.Spacing.regular)
                    .padding(.vertical, Memnox.Spacing.small)
                    .background(RoundedRectangle(cornerRadius: Layout.bubbleRadius, style: .continuous)
                        .fill(Memnox.Palette.primary.opacity(Layout.bubbleInk)))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, Layout.personIndent)
        case .tools(let calls):
            LiveToolRun(calls: calls)
        case .agent(let line):
            HStack(alignment: .firstTextBaseline, spacing: Memnox.Spacing.medium) {
                Circle().fill(Memnox.Palette.foreground).frame(width: LiveToolRun.dotSide, height: LiveToolRun.dotSide)
                    .accessibilityHidden(true)
                ReplyView(text: line.text)
            }
        }
    }
}

/// One stretch of the conversation as it is drawn: something the person said, something the agent said, or the
/// tool calls it made in a row between them.
struct TalkBlock: Identifiable {
    enum Kind {
        case person(ConversationLine, index: Int)
        case agent(ConversationLine)
        case tools([ConversationLine])
    }

    let id: Int
    let kind: Kind

    static func of(_ lines: [ConversationLine]) -> [TalkBlock] {
        var blocks: [TalkBlock] = []
        var calls: [ConversationLine] = []
        func closeCalls(at index: Int) {
            guard !calls.isEmpty else { return }
            blocks.append(TalkBlock(id: index - calls.count, kind: .tools(calls)))
            calls = []
        }
        for (index, line) in lines.enumerated() {
            switch LineAuthor(rawValue: line.who) {
            case .tool:
                calls.append(line)
            case .person:
                closeCalls(at: index)
                blocks.append(TalkBlock(id: index, kind: .person(line, index: index)))
            case .agent, nil:
                closeCalls(at: index)
                blocks.append(TalkBlock(id: index, kind: .agent(line)))
            }
        }
        closeCalls(at: lines.count)
        return blocks
    }
}

/// Tool calls in a row, folded to the latest with a count of the rest the way a terminal agent folds them, and
/// opened into every one on a click.
struct LiveToolRun: View {
    let calls: [ConversationLine]
    @State private var open = false

    static let dotSide: CGFloat = 7

    private enum Layout {
        static let callSpacing: CGFloat = 4
        static let railWidth: CGFloat = 1
        static let railInk = 0.12
        static let indent: CGFloat = 14
    }

    private enum Symbol {
        static let opened = "chevron.down"
        static let closed = "chevron.right"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.callSpacing) {
            Button { withAnimation(.snappy) { open.toggle() } } label: {
                HStack(alignment: .firstTextBaseline, spacing: Memnox.Spacing.medium) {
                    Circle().fill(Memnox.Palette.success).frame(width: Self.dotSide, height: Self.dotSide)
                    Text(calls.last?.text ?? "")
                        .font(.system(size: Memnox.TextSize.footnote, weight: .medium, design: .monospaced))
                        .foregroundStyle(Memnox.Palette.foreground.opacity(LiveStyle.softTextOpacity))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if calls.count > 1 {
                        Text(open ? "hide" : "+\(calls.count - 1)")
                            .font(Memnox.sans(Memnox.TextSize.caption, .semibold))
                            .foregroundStyle(Memnox.Palette.muted)
                        Image(systemName: open ? Symbol.opened : Symbol.closed)
                            .font(.system(size: Memnox.TextSize.micro, weight: .bold))
                            .foregroundStyle(Memnox.Palette.muted)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(calls.count < 2)
            .pointingHand()
            .help(open ? "Fold these steps" : "Show every step it ran here")
            if open {
                VStack(alignment: .leading, spacing: Layout.callSpacing) {
                    ForEach(Array(calls.enumerated()), id: \.offset) { _, call in
                        Text(call.text)
                            .font(.system(size: Memnox.TextSize.caption, design: .monospaced))
                            .foregroundStyle(Memnox.Palette.muted)
                            .textSelection(.enabled)
                    }
                }
                .padding(.leading, Layout.indent)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Memnox.ink(Layout.railInk)).frame(width: Layout.railWidth).padding(.leading, Self.dotSide / 2)
                }
                .transition(.opacity)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(calls.count == 1 ? "Ran \(calls.last?.text ?? "")" : "Ran \(calls.count) steps, the latest \(calls.last?.text ?? "")")
    }
}

/// While the agent works: a star that turns and how long it has been at it, the way its own terminal shows it.
struct LiveWorkingLine: View {
    let since: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let star = "asterisk"
    private static let turnSeconds: Double = 2.4

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            HStack(spacing: Memnox.Spacing.medium) {
                Image(systemName: Self.star)
                    .font(.system(size: Memnox.TextSize.footnote, weight: .bold))
                    .foregroundStyle(Memnox.Palette.warm)
                    .rotationEffect(.degrees(reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate / Self.turnSeconds * 360))
                ShimmerText(text: words(at: timeline.date))
            }
        }
        .accessibilityLabel("Working")
    }

    private func words(at now: Date) -> String {
        guard let since else { return "Working\u{2026}" }
        return "Working\u{2026} \(LiveClock.span(now.timeIntervalSince(since)))"
    }
}

/// The transcript's moments read as dates, and how long a stretch has run said the way a terminal says it.
enum LiveClock {
    static func date(_ text: String) -> Date? {
        let reader = ISO8601DateFormatter()
        reader.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = reader.date(from: text) { return date }
        reader.formatOptions = [.withInternetDateTime]
        return reader.date(from: text)
    }

    /// "42s", "3m 05s" or "1h 12m", never a negative.
    static func span(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds))
        let hours = whole / 3_600, minutes = (whole % 3_600) / 60, rest = whole % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return String(format: "%dm %02ds", minutes, rest) }
        return "\(rest)s"
    }
}

/// The reply box at the bottom of the window, which types into the session the way the notch's does, signed alike.
struct LiveReply: View {
    @ObservedObject var island: IslandModel
    let session: String
    let agentName: String
    @State private var words = ""
    @State private var sending = false
    @State private var replied: String?

    private static let symbol = "arrow.turn.down.right"

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
            SearchField(prompt: "Message \(agentName)", text: $words, symbol: Self.symbol, submit: send)
                .disabled(sending)
            if let replied {
                Text(replied)
                    .font(Memnox.sans(Memnox.TextSize.caption))
                    .foregroundStyle(Memnox.Palette.muted)
                    .lineLimit(1)
                    .padding(.leading, Memnox.Spacing.medium)
            }
        }
    }

    private func send() {
        let said = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !said.isEmpty, !sending else { return }
        sending = true
        Task { @MainActor in
            let state = await island.followUp(said, session)
            sending = false
            if case .sent = state { words = "" }
            replied = FollowUpWords.of(state)
        }
    }
}

/// Every file it changed with its counts; a file opens into its real diff, read from the daemon when opened.
struct LiveChanges: View {
    let files: [CardFile]
    let diffs: [String: [DiffLine]]
    let missing: Set<String>
    let load: (String) -> Void
    @State private var open: Set<String> = []

    private enum Layout {
        static let rowHeight: CGFloat = 32
        static let rowRadius: CGFloat = 10
        static let openInk = 0.05
        static let chevronTurn: Double = 90
    }

    private enum Symbol {
        static let file = "doc.text"
        static let chevron = "chevron.right"
    }

    private var added: Int { files.compactMap(\.added).reduce(0, +) }
    private var removed: Int { files.compactMap(\.removed).reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
            HStack(spacing: Memnox.Spacing.medium) {
                Text(files.count == 1 ? "1 file changed" : "\(files.count) files changed")
                    .font(Memnox.sans(Memnox.TextSize.footnote, .semibold))
                    .foregroundStyle(Memnox.Palette.foreground)
                Spacer()
                LineCounts(added: added, removed: removed)
            }
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                    ForEach(files, id: \.path) { file in fileRow(file) }
                }
            }
        }
        // The busiest file opens on its own, so the code itself is the first thing in this tab.
        .onAppear {
            guard open.isEmpty, let busiest = files.max(by: { size($0) < size($1) }) else { return }
            toggle(busiest.path)
        }
    }

    private func size(_ file: CardFile) -> Int { (file.added ?? 0) + (file.removed ?? 0) }

    @ViewBuilder
    private func fileRow(_ file: CardFile) -> some View {
        let isOpen = open.contains(file.path)
        VStack(alignment: .leading, spacing: 0) {
            Button { toggle(file.path) } label: {
                HStack(spacing: Memnox.Spacing.medium) {
                    Image(systemName: Symbol.chevron)
                        .font(.system(size: Memnox.TextSize.micro, weight: .bold))
                        .foregroundStyle(Memnox.Palette.muted)
                        .rotationEffect(.degrees(isOpen ? Layout.chevronTurn : 0))
                    Image(systemName: Symbol.file).foregroundStyle(Memnox.Palette.muted)
                    Text((file.path as NSString).lastPathComponent)
                        .font(Memnox.sans(Memnox.TextSize.footnote, .semibold))
                        .foregroundStyle(Memnox.Palette.foreground)
                        .lineLimit(1)
                    Text((file.path as NSString).deletingLastPathComponent)
                        .font(Memnox.sans(Memnox.TextSize.caption))
                        .foregroundStyle(Memnox.Palette.muted)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer(minLength: Memnox.Spacing.medium)
                    LineCounts(added: file.added ?? 0, removed: file.removed ?? 0)
                }
                .padding(.horizontal, Memnox.Spacing.medium)
                .frame(height: Layout.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHand()
            .help(file.path)
            if isOpen {
                diff(file.path)
                    .padding([.horizontal, .bottom], Memnox.Spacing.small)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(RoundedRectangle(cornerRadius: Layout.rowRadius, style: .continuous).fill(Memnox.ink(isOpen ? Layout.openInk : 0)))
        .hoverLight(radius: Layout.rowRadius, inset: 0)
    }

    @ViewBuilder
    private func diff(_ path: String) -> some View {
        if let lines = diffs[path] {
            DiffView(lines: lines)
        } else if missing.contains(path) {
            Text("The diff for this file is not readable now. It may have been committed or moved.")
                .font(Memnox.sans(Memnox.TextSize.caption))
                .foregroundStyle(Memnox.Palette.muted)
                .padding(Memnox.Spacing.medium)
        } else {
            HStack(spacing: Memnox.Spacing.small) {
                ProgressView().controlSize(.small)
                Text("Reading the diff").font(Memnox.sans(Memnox.TextSize.caption)).foregroundStyle(Memnox.Palette.muted)
            }
            .padding(Memnox.Spacing.medium)
        }
    }

    private func toggle(_ path: String) {
        withAnimation(.snappy) {
            if open.remove(path) == nil {
                open.insert(path)
                // Read again on every opening, so a file the agent is still writing shows its latest lines.
                load(path)
            }
        }
    }
}

/// Lines added in green and removed in red, as every diff counts them.
struct LineCounts: View {
    let added: Int
    let removed: Int

    var body: some View {
        HStack(spacing: Memnox.Spacing.small) {
            Text("+\(added)").foregroundStyle(Memnox.Palette.success)
            Text("\u{2212}\(removed)").foregroundStyle(removed > 0 ? Memnox.Palette.destructive : Memnox.Palette.muted)
        }
        .font(.system(size: Memnox.TextSize.caption, weight: .semibold, design: .monospaced))
        .monospacedDigit()
    }
}

/// A file's diff as a code review shows it: both line numbers in a gutter, added lines on green, removed on red,
/// and long lines scrolled sideways rather than cut.
struct DiffView: View {
    let lines: [DiffLine]

    private enum Layout {
        static let maxHeight: CGFloat = 300
        static let gutter: CGFloat = 34
        static let rowHeight: CGFloat = 17
        static let radius: CGFloat = 8
        static let addedInk = 0.16
        static let removedInk = 0.16
        static let hunkInk = 0.06
        static let pageInk = 0.03
        static let numberInk = 0.35
        static let codeSize: CGFloat = 11
    }

    var body: some View {
        ScrollView([.vertical, .horizontal], showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in row(line) }
            }
            .font(.system(size: Layout.codeSize, design: .monospaced))
            .textSelection(.enabled)
        }
        .frame(maxHeight: Layout.maxHeight)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: Layout.radius, style: .continuous).fill(Memnox.ink(Layout.pageInk)))
        .clipShape(RoundedRectangle(cornerRadius: Layout.radius, style: .continuous))
    }

    @ViewBuilder
    private func row(_ line: DiffLine) -> some View {
        switch line.kind {
        case .hunk:
            Text(line.text.isEmpty ? "\u{22EF}" : "\u{22EF}  \(line.text)")
                .foregroundStyle(Memnox.Palette.primary)
                .padding(.leading, Layout.gutter * 2)
                .frame(maxWidth: .infinity, minHeight: Layout.rowHeight + Memnox.Spacing.xSmall, alignment: .leading)
                .background(Memnox.Palette.primary.opacity(Layout.hunkInk))
        case .added, .removed, .context:
            HStack(spacing: 0) {
                number(line.old)
                number(line.new)
                Text(sign(line.kind)).foregroundStyle(tint(line.kind)).frame(width: Memnox.Spacing.large)
                Text(line.text.isEmpty ? " " : line.text)
                    .foregroundStyle(line.kind == .context ? Memnox.Palette.foreground.opacity(Memnox.Ink.secondary) : Memnox.Palette.foreground)
                    .fixedSize()
                    .padding(.trailing, Memnox.Spacing.large)
            }
            .frame(maxWidth: .infinity, minHeight: Layout.rowHeight, alignment: .leading)
            .background(fill(line.kind))
        }
    }

    private func number(_ value: Int?) -> some View {
        Text(value.map(String.init) ?? "")
            .foregroundStyle(Memnox.ink(Layout.numberInk))
            .frame(width: Layout.gutter, alignment: .trailing)
            .padding(.trailing, Memnox.Spacing.xSmall)
    }

    private func sign(_ kind: DiffLine.Kind) -> String {
        switch kind {
        case .added: return "+"
        case .removed: return "\u{2212}"
        case .hunk, .context: return " "
        }
    }

    private func tint(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added: return Memnox.Palette.success
        case .removed: return Memnox.Palette.destructive
        case .hunk, .context: return Memnox.Palette.muted
        }
    }

    private func fill(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added: return Memnox.Palette.success.opacity(Layout.addedInk)
        case .removed: return Memnox.Palette.destructive.opacity(Layout.removedInk)
        case .hunk, .context: return .clear
        }
    }
}
