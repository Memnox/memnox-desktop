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
    @Published var size: CGSize = CGSize(width: LivePanel.width, height: 600)
}

/// A borderless panel that can still take the pointer, so it leans as the person moves over it,
/// without making Memnox the active app and taking their keyboard.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
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
    private static let refreshEvery: UInt64 = 2_000_000_000
    /// Long enough to watch a stretch of work, never a window left up all day.
    private static let showFor: UInt64 = 5 * 60

    init() {
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 520),
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
            let height: CGFloat = min(820, screen.height - 40)
            panel.setFrame(
                NSRect(x: screen.midX - Self.width / 2 - 30, y: screen.midY - height / 2, width: Self.width + 60, height: height),
                display: true
            )
        }
        model.shown = false
        model.tilt = .zero
        panel.orderFrontRegardless()
        panel.makeKey()
        withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) { model.shown = true }
        poll(session)
        hide?.cancel()
        hide = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.showFor * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        polling?.cancel()
        hide?.cancel()
        withAnimation(.easeIn(duration: 0.28)) { model.shown = false }
        Task { [panel] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            panel.orderOut(nil)
        }
    }

    private func poll(_ session: String) {
        polling?.cancel()
        polling = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.refreshEvery)
                guard !Task.isCancelled, let self, let fresh = await self.fetch?(session) else { continue }
                withAnimation(.easeOut(duration: 0.3)) { self.model.view = fresh }
            }
        }
    }
}

struct LiveSessionView: View {
    @ObservedObject var model: LiveModel
    let close: () -> Void
    let jump: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let view = model.view {
                LiveHeader(view: view, close: close).reveal(model.shown, order: 0)
                LiveNow(view: view).reveal(model.shown, order: 1)
                let talk = view.conversation ?? []
                if !talk.isEmpty {
                    LiveConversation(lines: talk, thinking: view.thinking).reveal(model.shown, order: 2)
                }
                // The conversation says most of it, so the record beside it stays short.
                if !view.steps.isEmpty {
                    LiveSteps(steps: view.steps, most: talk.isEmpty ? 8 : 4).reveal(model.shown, order: 3)
                }
                if !view.helpers.isEmpty { LiveHelpers(helpers: view.helpers).reveal(model.shown, order: 4) }
                if !view.files.isEmpty {
                    LiveSection(title: "Changed") {
                        FileList(files: Array(view.files.prefix(talk.isEmpty ? 8 : 4)), counting: model.shown)
                    }
                    .reveal(model.shown, order: 5)
                }
                LiveFooter(view: view, jump: jump, close: close).reveal(model.shown, order: 6)
            } else {
                Text("This session is not on the record yet.")
                    .font(Memnox.sans(14))
                    .foregroundStyle(Memnox.Palette.muted)
                LiveFooter(view: nil, jump: jump, close: close)
            }
        }
        .padding(22)
        .frame(width: LivePanel.width, alignment: .leading)
        .background(surface)
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 18)
        // Settles in the way the island opens, and stays flat so every button is where it is drawn.
        .scaleEffect(model.shown ? 1 : 0.96)
        .offset(y: model.shown ? 0 : -14)
        .blur(radius: model.shown ? 0 : 8)
        .opacity(model.shown ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Solid black, lit from the bottom in the colour of how the session stands, and breathing while it works.
    private var surface: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        let colour = glowColour(model.view)
        return shape.fill(Color.black)
            .overlay(
                RadialGradient(
                    colors: [colour.opacity(0.32), .clear],
                    center: UnitPoint(x: 0.5, y: 1.15),
                    startRadius: 0,
                    endRadius: LivePanel.width
                )
                .phaseAnimator(model.view?.state == "working" ? [0.55, 1.0] : [1.0]) { light, strength in
                    light.opacity(strength)
                } animation: { _ in .easeInOut(duration: 1.6) }
            )
            .clipShape(shape)
            .animation(.easeInOut(duration: 0.5), value: model.view?.state)
    }
}

/// Each part rises into place a beat after the one above it, so the window assembles itself.
private struct Reveal: ViewModifier {
    let shown: Bool
    let order: Int

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 18)
            .blur(radius: shown ? 0 : 6)
            .animation(.spring(response: 0.55, dampingFraction: 0.85).delay(shown ? 0.18 + Double(order) * 0.07 : 0), value: shown)
    }
}

extension View {
    fileprivate func reveal(_ shown: Bool, order: Int) -> some View {
        modifier(Reveal(shown: shown, order: order))
    }
}

/// Green while it works or thinks, amber when it waits on the person, red when paused, quiet otherwise.
private func glowColour(_ view: SessionView?) -> Color {
    guard let view else { return Memnox.Palette.muted }
    if view.paused != nil || view.state == "paused" { return Memnox.Palette.destructive }
    if view.waitingOnYou > 0 || view.state == "open" { return Memnox.Palette.warm }
    if view.state == "working" || view.thinking { return Memnox.Palette.success }
    return Memnox.Palette.primary.opacity(0.6)
}

struct LiveHeader: View {
    let view: SessionView
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                LogoMark(size: 16)
                Text(view.agentName)
                    .font(Memnox.display(24))
                    .foregroundStyle(Memnox.Palette.foreground)
                StatePill(view: view)
                Spacer()
                CloseButton(action: close)
            }
            if let task = view.task {
                Text(task)
                    .font(Memnox.sans(14))
                    .foregroundStyle(Memnox.Palette.foreground.opacity(0.92))
                    .lineLimit(2)
            }
            Text(meta(view))
                .font(Memnox.sans(12))
                .foregroundStyle(Memnox.Palette.muted)
        }
    }

    private func meta(_ view: SessionView) -> String {
        [view.repository, view.runningIn, view.lastActive.flatMap(ago).map { "active \($0)" }]
            .compactMap { $0 }
            .joined(separator: "  ·  ")
    }
}

/// Working, waiting on the person, paused or quiet, with a dot that breathes while it works.
struct StatePill: View {
    let view: SessionView

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(colour)
                .frame(width: 7, height: 7)
                .phaseAnimator(working ? [false, true] : [false]) { dot, swelling in
                    dot.scaleEffect(swelling ? 1.5 : 1).opacity(swelling ? 0.5 : 1)
                } animation: { _ in .easeInOut(duration: 0.9) }
            Text(label).font(Memnox.sans(11, .medium))
        }
        .foregroundStyle(colour)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(Capsule().fill(colour.opacity(0.14)))
    }

    private var working: Bool { view.state == "working" }

    private var label: String {
        if view.paused != nil || view.state == "paused" { return "Paused" }
        if view.waitingOnYou > 0 { return "Needs you" }
        if view.thinking { return "Thinking" }
        switch view.state {
        case "working": return "Working"
        case "open": return "Waiting on you"
        case "ended": return "Ended"
        default: return "Quiet"
        }
    }

    private var colour: Color {
        if view.paused != nil || view.state == "paused" { return Memnox.Palette.destructive }
        if view.waitingOnYou > 0 || view.state == "open" { return Memnox.Palette.warm }
        if working || view.thinking { return Memnox.Palette.success }
        return Memnox.Palette.muted
    }
}

/// The one line that says what it is doing this moment.
struct LiveNow: View {
    let view: SessionView

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: view.thinking ? "sparkles" : "arrow.right.circle")
                .foregroundStyle(Memnox.Palette.primary)
            Text(now)
                .font(Memnox.sans(13, .medium))
                .foregroundStyle(Memnox.Palette.foreground)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(IslandPalette.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.035), lineWidth: 1))
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

    var body: some View {
        LiveSection(title: "Latest steps") {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(steps.suffix(most).enumerated()), id: \.element.at) { _, step in
                    HStack(spacing: 8) {
                        Image(systemName: icon(step.surface))
                            .font(.system(size: 11))
                            .frame(width: 14)
                            .foregroundStyle(tint(step))
                        Text(step.text)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(tint(step))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 6)
                        Text(ago(step.at) ?? "")
                            .font(Memnox.sans(11))
                            .foregroundStyle(Memnox.Palette.muted)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private func icon(_ surface: String) -> String {
        switch surface {
        case "shell": return "terminal"
        case "filesystem": return "doc.text"
        case "network": return "globe"
        case "mcp": return "puzzlepiece.extension"
        case "git": return "arrow.triangle.branch"
        case "browser": return "safari"
        default: return "circle.fill"
        }
    }

    private func tint(_ step: SessionViewStep) -> Color {
        if step.refused == true { return Memnox.Palette.warm }
        if step.failed == true { return Memnox.Palette.destructive }
        return Memnox.Palette.foreground.opacity(0.88)
    }
}

/// The conversation itself, newest at the bottom and kept in view as it grows: the person on
/// the right, the agent on the left, and each tool it runs as a quiet line between them.
private struct LiveConversation: View {
    let lines: [ConversationLine]
    let thinking: Bool
    private static let dotsKey = "typing-dots"
    /// A new line slides up from below and settles, rather than appearing in place.
    private static let arrives = AnyTransition.asymmetric(
        insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96, anchor: .bottomLeading)),
        removal: .opacity
    )

    /// Each line keyed by what it is, not where it sits, so one arriving moves in instead of every line shifting.
    private var keyed: [(key: String, line: ConversationLine)] {
        var seen: [String: Int] = [:]
        return lines.map { line in
            let base = "\(line.at)|\(line.who)|\(line.text.prefix(48))"
            let count = seen[base, default: 0]
            seen[base] = count + 1
            return (key: count == 0 ? base : "\(base)#\(count)", line: line)
        }
    }

    /// Only the agent's latest words type themselves out; the rest are already said.
    private var newestReply: String? {
        keyed.last { $0.line.who == "agent" }?.key
    }

    private var bottom: String { thinking ? Self.dotsKey : (keyed.last?.key ?? Self.dotsKey) }

    var body: some View {
        LiveSection(title: "Conversation") {
            ScrollViewReader { reader in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(keyed, id: \.key) { item in
                            ConversationRow(line: item.line, typing: item.key == newestReply)
                                .id(item.key)
                                .transition(Self.arrives)
                        }
                        if thinking { TypingDots().id(Self.dotsKey).transition(.opacity) }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 280)
                .onAppear { reader.scrollTo(bottom, anchor: .bottom) }
                .onChange(of: lines) { _, _ in
                    withAnimation(.easeOut(duration: 0.35)) { reader.scrollTo(bottom, anchor: .bottom) }
                }
            }
        }
    }
}

struct ConversationRow: View {
    let line: ConversationLine
    let typing: Bool

    var body: some View {
        switch line.who {
        case "person":
            HStack {
                Spacer(minLength: 60)
                Text(line.text)
                    .font(Memnox.sans(13))
                    .foregroundStyle(Memnox.Palette.foreground)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Memnox.Palette.primary.opacity(0.32)))
            }
        case "tool":
            Label(line.text, systemImage: "gearshape")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Memnox.Palette.muted)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, 4)
        default:
            Group {
                if typing { TypedText(text: line.text) } else { Text(line.text) }
            }
                .font(Memnox.sans(13))
                .foregroundStyle(Memnox.Palette.foreground.opacity(0.92))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 40)
        }
    }
}

/// Words that appear a few at a time, the way a reply is being written, then stay.
@MainActor
final class Typing: ObservableObject {
    @Published var shown = 0
    private var target = ""
    private var task: Task<Void, Never>?

    func type(_ text: String) {
        guard text != target else { return }
        // Picks up where it was when the reply grows, rather than starting it again.
        let from = text.hasPrefix(target) ? shown : 0
        target = text
        shown = from
        task?.cancel()
        task = Task { [weak self] in
            while let self, !Task.isCancelled, self.shown < text.count {
                try? await Task.sleep(nanoseconds: 14_000_000)
                self.shown = min(text.count, self.shown + 2)
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
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { dot in
                Circle()
                    .fill(Memnox.Palette.muted)
                    .frame(width: 6, height: 6)
                    .phaseAnimator([false, true]) { circle, up in
                        circle.offset(y: up ? -3 : 1).opacity(up ? 1 : 0.4)
                    } animation: { _ in .easeInOut(duration: 0.45).delay(Double(dot) * 0.15) }
            }
        }
        .padding(.leading, 4)
        .padding(.vertical, 4)
    }
}

private struct LiveHelpers: View {
    let helpers: [String]

    var body: some View {
        LiveSection(title: "Helpers") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(helpers, id: \.self) { helper in
                    Label(helper, systemImage: "person.2")
                        .font(Memnox.sans(12))
                        .foregroundStyle(Memnox.Palette.foreground.opacity(0.88))
                }
            }
        }
    }
}

struct LiveSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(Memnox.sans(10, .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.white.opacity(0.4))
                .padding(.leading, 4)
            content()
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(IslandPalette.card))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.035), lineWidth: 1))
        }
    }
}

private struct LiveFooter: View {
    let view: SessionView?
    let jump: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Spacer()
            CardButton(title: "Close", icon: "xmark", primary: false, action: close)
            CardButton(title: jumpLabel, icon: "arrow.up.forward.app", primary: true, action: jump)
        }
    }

    private var jumpLabel: String {
        guard let app = view?.runningIn else { return "Open its window" }
        return "Open in \(app)"
    }
}

/// "2 min ago" from an ISO moment, the way a glance wants it.
func ago(_ moment: String) -> String? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = formatter.date(from: moment) ?? ISO8601DateFormatter().date(from: moment) else { return nil }
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 45 { return "just now" }
    if seconds < 3_600 { return "\(seconds / 60 == 0 ? 1 : seconds / 60) min ago" }
    if seconds < 86_400 { return "\(seconds / 3_600) h ago" }
    return "\(seconds / 86_400) d ago"
}
