import AppKit
import MemnoxVoiceCore
import SwiftUI

/// What is about to go out in the person's name, laid out the way its own tool lays it out: a Slack
/// message, a GitHub or Linear comment, a mail. It names the account it goes out as and shows every
/// argument; its words sit in a box ready to change, and Send signs exactly what goes; closing it goes unsigned.
struct IslandWorkCard: View {
    @ObservedObject var model: IslandModel
    let card: WorkCard
    /// The words as they stand in the card, the proposed ones until the person rewrites them.
    @State private var words: String
    /// The addresses as they stand in a mail's To field, the proposed ones until the person retypes them.
    @State private var toText: String
    @FocusState private var typing: Bool
    @FocusState private var addressing: Bool

    init(model: IslandModel, card: WorkCard) {
        self.model = model
        self.card = card
        _words = State(initialValue: card.draft.body ?? "")
        _toText = State(initialValue: (card.draft.to ?? []).joined(separator: ", "))
    }

    private enum Layout {
        static let padding: CGFloat = 14
        static let markSide: CGFloat = 22
        static let avatarSide: CGFloat = 32
        static let closeSide: CGFloat = 24
        static let rowHeight: CGFloat = 30
        static let bodySize: CGFloat = 14
        static let bodyLineSpacing: CGFloat = 4
        static let commentRadius: CGFloat = 8
        static let fieldNameWidth: CGFloat = 96
        /// Tall enough for a few lines of a message, short enough that Send stays on the card.
        static let editorMinHeight: CGFloat = 72
        static let editorMaxHeight: CGFloat = 180
        /// As many recipients as fit on one row; the rest are counted, and named on hover.
        static let shownPeople = 3
        static let dayTileSide: CGFloat = 44
        static let dayTileRadius: CGFloat = 9
        static let dayNumberSize: CGFloat = 20
        static let pageTitleSize: CGFloat = 20
    }

    private enum Shade {
        static let rule = 0.07
        static let chip = 0.1
        static let commentHeader = 0.05
        /// The answers dim while Touch ID is up, so a second press is not invited.
        static let sending = 0.55
    }

    private enum Symbol {
        static let close = "xmark"
        static let touchID = "touchid"
        static let matched = "checkmark.seal.fill"
        static let unverified = "exclamationmark.triangle.fill"
        static let place = "arrow.turn.down.right"
        static let clock = "clock"
        static let page = "doc.text"
    }

    private var draft: WorkDraft { card.draft }
    /// Words that were there and are now all gone, so there is nothing to send.
    private var empty: Bool { draft.body != nil && words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var changed: Bool { draft.body != nil && words != draft.body }
    /// The addresses typed in the To field, nil while any is not a plain address, so Send waits for a real one.
    private var addresses: [String]? { MailAddresses.parse(toText) }
    private var badAddress: Bool { draft.readdressable && addresses == nil }
    private var readdressed: Bool { draft.readdressable && addresses != nil && addresses != (draft.to ?? []) }

    /// What the footer says now: Touch ID up, nothing left to send, the person's own words, or the promise.
    private var footnote: String {
        if model.sending { return "Waiting for Touch ID" }
        if empty { return "Write something to send." }
        if badAddress { return "Check the address before you send." }
        if readdressed { return "It goes to the address you typed." }
        if changed { return "Your words go out as you wrote them." }
        return "Nothing goes out until you send it."
    }
    private var tool: String { ToolkitName.of(draft.toolkit) }

    var body: some View {
        // Plain black like the rest of the tool surfaces: the logo and the Send button carry the brand.
        IslandCard(veil: nil) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.regular) {
                header
                account
                rule
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Memnox.Spacing.regular) {
                        content
                        if !draft.fields.isEmpty { fields }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
                footer
            }
            .padding(Layout.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(kindWord) on \(tool), waiting for you to send it")
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: Memnox.Spacing.medium) {
            ToolMark(toolkit: draft.toolkit, side: Layout.markSide)
            Text("\(kindWord) on \(tool)")
                .font(Memnox.sans(Memnox.TextSize.callout, .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
            Spacer()
            Button { answer(send: false) } label: {
                Image(systemName: Symbol.close)
                    .font(.system(size: Memnox.TextSize.footnote, weight: .bold))
                    .foregroundStyle(Color.white.opacity(Memnox.Ink.primary))
                    .frame(width: Layout.closeSide, height: Layout.closeSide)
                    .background(Circle().fill(Color.white.opacity(Shade.chip)))
            }
            .buttonStyle(PressableStyle())
            .help("Close without sending")
            .accessibilityLabel("Close without sending")
            // Not while Touch ID is up, so a stray click cannot turn a send into a decline halfway.
            .disabled(model.sending)
        }
    }

    /// Whose name it goes out under, and whether the workspace could tell that account is theirs.
    private var account: some View {
        let shown = draft.account?.shown
        let check = draft.account?.accountCheck ?? .unknown
        return HStack(spacing: Memnox.Spacing.small) {
            Text(shown.map { "As \($0)" } ?? "As you")
                .font(Memnox.sans(Memnox.TextSize.footnote, .medium))
                .foregroundStyle(Color.white.opacity(Memnox.Ink.primary))
            if check == .matched {
                Image(systemName: Symbol.matched).foregroundStyle(IslandPalette.green)
                    .accessibilityLabel("your account")
            } else {
                Label("not tied to you, check the name", systemImage: Symbol.unverified)
                    .foregroundStyle(IslandPalette.amber)
            }
        }
        .font(Memnox.sans(Memnox.TextSize.caption, .medium))
        .lineLimit(1)
    }

    private var rule: some View {
        Rectangle().fill(Color.white.opacity(Shade.rule)).frame(height: Memnox.Stroke.hairline)
    }

    private var footer: some View {
        HStack(spacing: Memnox.Spacing.medium) {
            Text(footnote)
                .font(Memnox.sans(Memnox.TextSize.caption))
                .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeOut(duration: Memnox.Motion.quick), value: footnote)
            Spacer()
            Button { answer(send: true) } label: {
                HStack(spacing: Memnox.Spacing.small) {
                    Image(systemName: Symbol.touchID)
                    Text(ToolBrand.sendLabel(draft.toolkit))
                }
                .font(Memnox.sans(Memnox.TextSize.callout, .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, Memnox.Spacing.xLarge)
                .padding(.vertical, Memnox.Spacing.medium)
                .background(Capsule().fill(ToolBrand.color(draft.toolkit)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(Memnox.Ink.edge)))
            }
            .buttonStyle(PressableStyle())
            .help(empty ? "Write something to send" : badAddress ? "Check the address" : "Send with Touch ID")
            .accessibilityLabel("\(ToolBrand.sendLabel(draft.toolkit)) on \(tool), with Touch ID")
            // Command Return sends from the box, the way a message is sent in most apps.
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(empty || badAddress)
        }
        .disabled(model.sending)
        .opacity(model.sending ? Shade.sending : 1)
    }

    // MARK: Each tool's own layout

    @ViewBuilder private var content: some View {
        switch draft.draftKind {
        case .message: message
        case .comment: comment
        case .email: email
        case .event: event
        case .page: page
        case .issue, .other: generic
        }
    }

    /// Slack: where it goes, then the message as it will sit in the channel, under their name.
    private var message: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            if let to = draft.to, !to.isEmpty { chips("To", to) }
            HStack(alignment: .top, spacing: Memnox.Spacing.regular) {
                avatar
                VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                    HStack(spacing: Memnox.Spacing.small) {
                        Text(draft.account?.shown ?? "You")
                            .font(Memnox.sans(Memnox.TextSize.body, .bold))
                            .foregroundStyle(Color.white)
                        Text("now")
                            .font(Memnox.sans(Memnox.TextSize.caption))
                            .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
                    }
                    bodyText
                }
            }
        }
    }

    /// GitHub and Linear: where it lands, then a comment box headed by who wrote it.
    private var comment: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            if let place = draft.where {
                Label(place, systemImage: Symbol.place)
                    .font(Memnox.mono(Memnox.TextSize.footnote, .medium))
                    .foregroundStyle(Color.white.opacity(Memnox.Ink.primary))
                    .lineLimit(1)
            }
            let shape = RoundedRectangle(cornerRadius: Layout.commentRadius, style: .continuous)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Memnox.Spacing.small) {
                    avatar.scaleEffect(0.6).frame(width: Layout.avatarSide * 0.6, height: Layout.avatarSide * 0.6)
                    Text(draft.account?.shown ?? "You").font(Memnox.sans(Memnox.TextSize.footnote, .bold))
                    Text("commenting").font(Memnox.sans(Memnox.TextSize.footnote))
                        .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, Memnox.Spacing.regular)
                .frame(height: Layout.rowHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(Shade.commentHeader))
                rule
                bodyText.padding(Memnox.Spacing.regular)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(Memnox.Ink.edge)))
        }
    }

    /// Gmail: recipients, subject, then the words; the real address in a field the person can correct before Touch ID.
    private var email: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            if draft.readdressable {
                addressField
            } else if let to = draft.to, !to.isEmpty {
                chips("To", to)
            }
            if let subject = draft.subject {
                Text(subject)
                    .font(Memnox.sans(Memnox.TextSize.callout, .semibold))
                    .foregroundStyle(Color.white)
            }
            rule
            bodyText
        }
    }

    /// A calendar: the day as a calendar leaf, the title and the hours it books, then who is invited and the words.
    private var event: some View {
        let start = EventTime(draft.starts)
        let end = EventTime(draft.ends)
        return VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            HStack(alignment: .center, spacing: Memnox.Spacing.regular) {
                dayTile(start)
                VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                    Text(draft.subject ?? "New event")
                        .font(Memnox.sans(Memnox.TextSize.callout, .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(2)
                    if let hours = EventTime.span(start, end) {
                        Label(hours, systemImage: Symbol.clock)
                            .font(Memnox.sans(Memnox.TextSize.footnote, .medium))
                            .foregroundStyle(Color.white.opacity(Memnox.Ink.primary))
                            .lineLimit(1)
                    }
                }
            }
            if let to = draft.to, !to.isEmpty { chips("With", to) }
            if draft.body != nil { bodyText }
        }
    }

    /// The month over the day number, like the leaf of a desk calendar, or a blank leaf when no day was given.
    private func dayTile(_ start: EventTime) -> some View {
        let shape = RoundedRectangle(cornerRadius: Layout.dayTileRadius, style: .continuous)
        return VStack(spacing: 0) {
            Text(start.month ?? "")
                .font(Memnox.sans(Memnox.TextSize.caption, .bold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .background(ToolBrand.color(draft.toolkit))
            Text(start.day ?? "?")
                .font(.system(size: Layout.dayNumberSize, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: Layout.dayTileSide, height: Layout.dayTileSide)
        .background(Color.white.opacity(Shade.chip))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(Memnox.Ink.edge)))
        .accessibilityHidden(true)
    }

    /// Notion and other documents: where the page lands, its title set large the way a page heads itself, then its words.
    private var page: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            if let place = draft.where {
                Label(place, systemImage: Symbol.page)
                    .font(Memnox.sans(Memnox.TextSize.footnote, .medium))
                    .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
                    .lineLimit(1)
            }
            Text(draft.subject ?? "Untitled")
                .font(Memnox.sans(Layout.pageTitleSize, .bold))
                .foregroundStyle(Color.white)
                .lineLimit(2)
            if draft.body != nil { bodyText }
        }
    }

    /// Anything else: a title where there is one, then the words, with every argument listed below.
    private var generic: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            if let place = draft.where {
                Label(place, systemImage: Symbol.place)
                    .font(Memnox.mono(Memnox.TextSize.footnote, .medium))
                    .foregroundStyle(Color.white.opacity(Memnox.Ink.primary))
            }
            if let subject = draft.subject {
                Text(subject)
                    .font(Memnox.sans(Memnox.TextSize.callout, .semibold))
                    .foregroundStyle(Color.white)
            }
            if draft.body != nil { bodyText }
        }
    }

    // MARK: Parts

    private var avatar: some View {
        Text(String((draft.account?.shown ?? "You").prefix(1)).uppercased())
            .font(Memnox.sans(Memnox.TextSize.callout, .bold))
            .foregroundStyle(Color.white)
            .frame(width: Layout.avatarSide, height: Layout.avatarSide)
            .background(RoundedRectangle(cornerRadius: Memnox.radius, style: .continuous)
                .fill(ToolBrand.color(draft.toolkit)))
            .accessibilityHidden(true)
    }

    /// The words in a box from the start, so the person changes them where they read them and just sends.
    private var bodyText: some View {
        TextEditor(text: $words)
            .font(Memnox.sans(Layout.bodySize))
            .lineSpacing(Layout.bodyLineSpacing)
            .foregroundStyle(Color.white)
            .scrollContentBackground(.hidden)
            .focused($typing)
            // Escape leaves the box and keeps the words, rather than closing the draft.
            .onExitCommand { typing = false }
            .padding(Memnox.Spacing.small)
            .frame(minHeight: Layout.editorMinHeight, maxHeight: Layout.editorMaxHeight)
            .background(RoundedRectangle(cornerRadius: Layout.commentRadius, style: .continuous)
                .fill(Color.white.opacity(Shade.chip)))
            // A click into the box hands the island the keys; until then typing stays in the app the person is in.
            .simultaneousGesture(TapGesture().onEnded(startTyping))
            .help("Change the words, then send them")
            .accessibilityLabel("The words that will be sent")
    }

    /// The address itself, never only a name, since a misheard address read as the right person until it had gone out.
    private var addressField: some View {
        HStack(spacing: Memnox.Spacing.medium) {
            Text("To")
                .font(Memnox.sans(Memnox.TextSize.body))
                .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
            TextField("name@example.com", text: $toText)
                .textFieldStyle(.plain)
                .font(Memnox.mono(Memnox.TextSize.footnote, .medium))
                .foregroundStyle(Color.white)
                .focused($addressing)
                .onExitCommand { addressing = false }
                .simultaneousGesture(TapGesture().onEnded(startAddressing))
                .help("Change who it goes to, then send it")
                .accessibilityLabel("The address it goes to")
            if let name = draft.toName {
                Text(name)
                    .font(Memnox.sans(Memnox.TextSize.caption, .medium))
                    .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Memnox.Spacing.regular)
        .padding(.vertical, Memnox.Spacing.small)
        .background(RoundedRectangle(cornerRadius: Layout.commentRadius, style: .continuous)
            .fill(Color.white.opacity(Shade.chip)))
        .overlay(RoundedRectangle(cornerRadius: Layout.commentRadius, style: .continuous)
            .strokeBorder(badAddress ? IslandPalette.amber : Color.clear))
    }

    /// The island takes keys for the To field too, so a corrected address lands there and not in the app behind it.
    private func startAddressing() {
        NSApp.windows.first { $0 is IslandPanel }?.makeKey()
        addressing = true
    }

    /// The island takes keys only now, so typing lands in the box and not in the app behind it.
    private func startTyping() {
        NSApp.windows.first { $0 is IslandPanel }?.makeKey()
        typing = true
    }

    private func chips(_ label: String, _ people: [String]) -> some View {
        HStack(spacing: Memnox.Spacing.medium) {
            Text(label)
                .font(Memnox.sans(Memnox.TextSize.body))
                .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
            ForEach(people.prefix(Layout.shownPeople), id: \.self) { person in
                Text(person)
                    .font(Memnox.sans(Memnox.TextSize.body, .medium))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .padding(.horizontal, Memnox.Spacing.regular)
                    .padding(.vertical, Memnox.Spacing.xSmall)
                    .background(Capsule().fill(Color.white.opacity(Shade.chip)))
            }
            if people.count > Layout.shownPeople {
                Text("and \(people.count - Layout.shownPeople) more")
                    .font(Memnox.sans(Memnox.TextSize.body))
                    .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
                    .lineLimit(1)
                    .help(people.joined(separator: ", "))
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Every argument the layout did not show, so nothing is sent that the person did not see.
    private var fields: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
            Text("Also sends")
                .font(Memnox.sans(Memnox.TextSize.caption, .semibold))
                .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
            ForEach(draft.fields, id: \.name) { field in
                HStack(alignment: .firstTextBaseline, spacing: Memnox.Spacing.medium) {
                    Text(field.name)
                        .font(Memnox.mono(Memnox.TextSize.caption))
                        .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
                        .frame(width: Layout.fieldNameWidth, alignment: .leading)
                        .lineLimit(1)
                    Text(field.value)
                        .font(Memnox.mono(Memnox.TextSize.caption))
                        .foregroundStyle(Color.white.opacity(Memnox.Ink.primary))
                }
            }
        }
    }

    private var kindWord: String {
        switch draft.draftKind {
        case .message: return "Message"
        case .comment: return draft.toolkit == "github" ? "Review comment" : "Comment"
        case .email: return "Email"
        case .issue: return "Issue"
        case .event: return "Event"
        case .page: return "Page"
        case .other: return "Action"
        }
    }

    private func answer(send: Bool) {
        model.sending = send
        // A draft with no words of its own has nothing to rewrite, so it goes exactly as proposed.
        let shown = draft.body == nil ? nil : words
        if draft.readdressable, let addresses {
            model.answerWork(card.with(words: shown, to: addresses), send)
        } else {
            model.answerWork(shown.map { card.with(words: $0) } ?? card, send)
        }
    }
}

/// An event's start or end as the tool was given it, read for the card's calendar leaf and hours; text no clock
/// reads is shown as it came, so the card never claims a time it could not read.
struct EventTime {
    let raw: String?
    let date: Date?
    /// Whether the text named an hour, since an all day event has only a date.
    let timed: Bool

    init(_ raw: String?) {
        self.raw = raw
        guard let raw else { date = nil; timed = false; return }
        if let full = Self.read(raw) {
            date = full; timed = true
        } else if let day = Self.dayOnly.date(from: raw) {
            date = day; timed = false
        } else {
            date = nil; timed = false
        }
    }

    var month: String? { date.map { $0.formatted(.dateTime.month(.abbreviated)).uppercased() } }
    var day: String? { date.map { $0.formatted(.dateTime.day()) } }

    /// "Fri 24 Oct, 10:00 to 10:30", the day once when both ends fall on it, else whatever each end reads as.
    static func span(_ start: EventTime, _ end: EventTime) -> String? {
        guard let from = start.date else { return start.raw }
        let day = from.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        guard start.timed else { return day }
        let hours = from.formatted(date: .omitted, time: .shortened)
        guard let to = end.date else { return "\(day), \(hours)" }
        let sameDay = Calendar.current.isDate(from, inSameDayAs: to)
        let until = sameDay ? to.formatted(date: .omitted, time: .shortened) : to.formatted(date: .abbreviated, time: .shortened)
        return "\(day), \(hours) to \(until)"
    }

    /// With or without a zone and fractional seconds, the shapes calendar tools take a start in.
    private static func read(_ text: String) -> Date? {
        for options in fullShapes {
            let reader = ISO8601DateFormatter()
            reader.formatOptions = options
            if let date = reader.date(from: text) { return date }
        }
        return localTime.date(from: text)
    }

    private static let fullShapes: [ISO8601DateFormatter.Options] = [
        [.withInternetDateTime, .withFractionalSeconds],
        [.withInternetDateTime],
    ]

    /// A start with no zone is the person's own local time, the way a calendar reads it.
    private static let localTime: DateFormatter = {
        let reader = DateFormatter()
        reader.locale = Locale(identifier: "en_US_POSIX")
        reader.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return reader
    }()

    private static let dayOnly: DateFormatter = {
        let reader = DateFormatter()
        reader.locale = Locale(identifier: "en_US_POSIX")
        reader.dateFormat = "yyyy-MM-dd"
        return reader
    }()
}
