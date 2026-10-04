import AppKit
import MemnoxVoiceCore
import SwiftUI

/// Talking with live words on, before anything is asked: the orb above what the person is saying.
struct IslandHearing: View {
    @ObservedObject var model: IslandModel

    private enum Layout {
        /// Where the words start below the content top, clear of the orb above them.
        static let wordsBelowTop: CGFloat = 104
        static let wordsSide: CGFloat = 28
        static let wordsHeight: CGFloat = 84
        static let chipTrailing: CGFloat = 18
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if model.ruling, model.heard.isEmpty {
                    Text("Say the rule, then let go")
                        .font(Memnox.sans(Memnox.TextSize.title, .medium))
                        .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
                } else {
                    LiveWords(text: model.heard, size: Memnox.TextSize.title, alignment: .center, listening: model.state == .listening)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: Layout.wordsHeight, alignment: .bottom)
            .padding(.horizontal, Layout.wordsSide)
            .padding(.top, Island.top(model.notch) + Layout.wordsBelowTop)
            Spacer(minLength: 0)
        }
        .overlay(alignment: .topTrailing) {
            // In the header row right of the notch, where the open island counts sessions.
            if model.ruling {
                RuleModeChip()
                    .frame(height: model.notch.height)
                    .padding(.trailing, Layout.chipTrailing)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { model.tapped() }
    }
}

/// A turn on screen: the question in a bubble, and under it the answer as it arrives, or a drafted message.
/// The question gives way to the person's live words the moment they start a follow up.
struct IslandConversation: View {
    @ObservedObject var model: IslandModel
    let exchange: Exchange?
    /// True while talking, which is when the words are live and the answer can be opened up or put back.
    let live: Bool

    /// A card grows out of the bubble's lower edge from just under its size, so it reads as coming from the question.
    private static let cardArrivalScale: CGFloat = 0.97
    private static let arrival = Animation.spring(response: 0.42, dampingFraction: 0.82)

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            if let question = bubbleText {
                QuestionBubble(text: question, live: showsLiveWords, listening: model.state == .listening)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let draft = model.draft {
                IslandDraftCard(model: model, card: draft)
                    .transition(.opacity.combined(with: .scale(scale: Self.cardArrivalScale, anchor: .top)))
            } else if let rule = model.rule {
                IslandRuleCard(model: model, card: rule)
                    .transition(.opacity.combined(with: .scale(scale: Self.cardArrivalScale, anchor: .top)))
            } else if let exchange {
                AnswerCard(model: model, exchange: exchange, live: live)
                    .transition(.opacity.combined(with: .scale(scale: Self.cardArrivalScale, anchor: .top)))
            }
        }
        .animation(Self.arrival, value: model.draft)
        .animation(Self.arrival, value: model.rule)
        .animation(Self.arrival, value: exchange?.id)
        .islandContentInset(model.notch)
    }

    /// Live words while a follow up is being said; otherwise the question this answer is for.
    private var showsLiveWords: Bool { live && model.liveWords && model.state == .listening && !model.heard.isEmpty }

    private var bubbleText: String? {
        if showsLiveWords { return model.heard }
        return exchange?.question
    }
}

/// The person's words in a soft bubble, three lines at most, the newest always in view.
struct QuestionBubble: View {
    let text: String
    let live: Bool
    let listening: Bool

    private enum Layout {
        static let radius: CGFloat = 18
        static let maxHeight: CGFloat = 76
        static let horizontal: CGFloat = 16
        static let vertical: CGFloat = 12
        static let textSize: CGFloat = 15
    }

    private static let fill = 0.07

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Group {
                if live {
                    LiveWords(text: text, size: Layout.textSize, alignment: .leading, listening: listening)
                } else {
                    Text(text)
                        .font(Memnox.sans(Layout.textSize, .medium))
                        .foregroundStyle(Color.white.opacity(Memnox.Ink.primary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Layout.horizontal)
            .padding(.vertical, Layout.vertical)
        }
        .defaultScrollAnchor(.bottom)
        .frame(maxHeight: Layout.maxHeight)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: Layout.radius, style: .continuous).fill(Color.white.opacity(Self.fill)))
    }
}

/// What is being said, one word at a time: each arrives out of a blur and settles, and a word the
/// recognizer corrects arrives again, so the sentence is seen firming up as it is heard.
struct LiveWords: View {
    let text: String
    let size: CGFloat
    let alignment: HorizontalAlignment
    let listening: Bool

    private static let arrival = Animation.spring(response: 0.34, dampingFraction: 0.78)
    /// The newest word is a touch brighter, so the eye stays where the voice is.
    private static let olderInk = 0.78
    /// The gaps between words and between lines, and the caret's height, as shares of the text size, so they scale with it.
    private static let wordGap: CGFloat = 0.28
    private static let lineGap: CGFloat = 0.3
    private static let caretHeight: CGFloat = 1.1

    var body: some View {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        WordFlow(alignment: alignment, spacing: size * Self.wordGap, lineSpacing: size * Self.lineGap) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Text(word)
                    .font(Memnox.sans(size, .medium))
                    .foregroundStyle(Color.white.opacity(index == words.count - 1 ? 1 : Self.olderInk))
                    .id("\(index):\(word)")
                    .transition(.wordArrival)
            }
            if listening {
                ListeningCaret(height: size * Self.caretHeight)
            }
        }
        .animation(Self.arrival, value: words)
    }
}

/// A thin bar after the last word that breathes while the microphone is open.
struct ListeningCaret: View {
    let height: CGFloat

    private static let width: CGFloat = 2
    private static let period: TimeInterval = 1.1
    private static let dimmest = 0.25

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period) / Self.period
            Capsule()
                .fill(Memnox.Palette.primary)
                .frame(width: Self.width, height: height)
                .opacity(Self.dimmest + (1 - Self.dimmest) * (sin(phase * 2 * .pi) + 1) / 2)
        }
    }
}

/// How a word arrives: out of a blur, rising a little and growing into place.
private struct WordArrival: ViewModifier {
    let shown: Bool

    private static let blur: CGFloat = 7
    private static let rise: CGFloat = 8
    private static let scale: CGFloat = 0.9

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown ? 0 : Self.blur)
            .offset(y: shown ? 0 : Self.rise)
            .scaleEffect(shown ? 1 : Self.scale, anchor: .bottomLeading)
    }
}

extension AnyTransition {
    static var wordArrival: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: WordArrival(shown: false), identity: WordArrival(shown: true)),
            removal: .opacity.animation(.easeOut(duration: Memnox.Motion.quick))
        )
    }
}

/// Words laid out like a paragraph, wrapping at the width it is given, so each one can move on its own.
struct WordFlow: Layout {
    let alignment: HorizontalAlignment
    let spacing: CGFloat
    let lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = lines(for: subviews, width: proposal.width ?? .infinity)
        let width = lines.map(\.width).max() ?? 0
        let height = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(lines.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(for: subviews, width: bounds.width) {
            let slack = bounds.width - line.width
            var x = bounds.minX + (alignment == .center ? slack / 2 : alignment == .trailing ? slack : 0)
            for index in line.members {
                let size = subviews[index].sizeThatFits(.unspecified)
                // Sat on a shared baseline by their bottoms, so a caret and a word line up.
                subviews[index].place(at: CGPoint(x: x, y: y + line.height - size.height), proposal: .unspecified)
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var members: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(for subviews: Subviews, width: CGFloat) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = line.members.isEmpty ? size.width : line.width + spacing + size.width
            if needed > width, !line.members.isEmpty {
                lines.append(line)
                line = Line()
            }
            line.width = line.members.isEmpty ? size.width : line.width + spacing + size.width
            line.height = max(line.height, size.height)
            line.members.append(index)
        }
        if !line.members.isEmpty { lines.append(line) }
        return lines
    }
}

/// The answer as a card: who answered and how long it took, the reply laid out as written, and ways to open it up.
struct AnswerCard: View {
    @ObservedObject var model: IslandModel
    let exchange: Exchange
    let live: Bool

    private enum Layout {
        static let markSide: CGFloat = 14
        static let padding: CGFloat = 14
        static let footerSize: CGFloat = 12.5
    }

    private enum Symbol {
        static let more = "chevron.down"
        static let less = "chevron.up"
        static let copy = "doc.on.doc"
        static let open = "arrow.up.forward.square"
        static let done = "checkmark.circle.fill"
    }

    /// A faint blue rising from the bottom while the reply is still arriving.
    private static let answeringVeil = 0.22
    /// Where the reply starts fading into the footer, so a long one shows there is more below.
    private static let fadeFrom = 0.86

    var body: some View {
        IslandCard(veil: exchange.isAnswering ? Memnox.Palette.primary.opacity(Self.answeringVeil) : nil) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.regular) {
                header
                bodyText
                footer
            }
            .padding(Layout.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        HStack(spacing: Memnox.Spacing.medium) {
            Circle()
                .fill(LinearGradient(colors: [Memnox.Palette.sky, Memnox.Palette.primary], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: Layout.markSide, height: Layout.markSide)
            Text("Memnox")
                .font(Memnox.sans(Memnox.TextSize.body, .semibold))
                .foregroundStyle(Color.white.opacity(Memnox.Ink.primary))
            Spacer(minLength: Memnox.Spacing.medium)
            if exchange.isAnswering {
                ShimmerText(text: "Working")
            } else {
                Label("Done", systemImage: Symbol.done)
                    .font(Memnox.sans(Memnox.TextSize.footnote, .semibold))
                    .foregroundStyle(IslandPalette.green)
            }
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(clock(exchange.elapsed(now: timeline.date)))
                    .font(Memnox.sans(Memnox.TextSize.footnote, .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(Memnox.Ink.tertiary))
            }
        }
    }

    @ViewBuilder private var bodyText: some View {
        if exchange.answer.isEmpty {
            // Nothing written yet: what the brain is reading, so a long lookup never looks stuck.
            ShimmerText(text: model.caption.isEmpty || model.state != .thinking ? "Thinking" : model.caption)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                MarkdownText(source: exchange.answer)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeOut(duration: Memnox.Motion.quick), value: exchange.answer)
            }
            .defaultScrollAnchor(exchange.isAnswering ? .bottom : .top)
            .mask(
                LinearGradient(stops: [.init(color: .black, location: Self.fadeFrom), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
            )
        }
    }

    private var footer: some View {
        HStack(spacing: Memnox.Spacing.medium) {
            if live {
                Button {
                    withAnimation(Island.motion(growing: !model.expanded)) { model.expanded.toggle() }
                    model.settle()
                } label: {
                    Label(model.expanded ? "Show less" : "Show more", systemImage: model.expanded ? Symbol.less : Symbol.more)
                        .labelStyle(TrailingIcon())
                }
                .buttonStyle(IslandButton(primary: false))
            }
            Spacer(minLength: 0)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(exchange.answer, forType: .string)
            } label: { Label("Copy", systemImage: Symbol.copy) }
                .buttonStyle(IslandButton(primary: false))
                .disabled(exchange.answer.isEmpty)
            Button { model.openAnswer(exchange) } label: { Label("Open answer", systemImage: Symbol.open) }
                .buttonStyle(IslandButton(primary: true))
                .disabled(exchange.answer.isEmpty)
        }
        .font(Memnox.sans(Layout.footerSize, .medium))
    }
}

/// Minutes and seconds, the way a stopwatch shows how long an answer has taken.
func clock(_ seconds: TimeInterval) -> String {
    let whole = max(0, Int(seconds))
    return "\(whole / secondsPerMinute):\(String(format: twoDigits, whole % secondsPerMinute))"
}

private let secondsPerMinute = 60
private let twoDigits = "%02d"

/// A label with its symbol after the words, as a disclosure reads.
private struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Memnox.Spacing.xSmall) {
            configuration.title
            configuration.icon.font(.system(size: Memnox.TextSize.caption, weight: .semibold))
        }
    }
}
