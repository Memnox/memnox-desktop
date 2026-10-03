import AppKit
import MemnoxVoiceCore
import SwiftUI

/// The card: glass in the top left corner, a heading and the summary, gone on a click or after a while.
@MainActor
final class CardPanel {
    private let panel: KeyablePanel
    private var hide: Task<Void, Never>?
    /// Long enough to read a four sentence summary and glance at the code after the voice has finished it.
    private static let showFor: UInt64 = 60
    /// Once the pointer has been on it and left, the person has read it, so it goes sooner.
    private static let afterLeaving: UInt64 = 15
    static let width: CGFloat = 440
    /// Only a starting height, since every card is sized to its content before it shows.
    private static let initialHeight: CGFloat = 160
    /// Room around the card, since standing at an angle carries its edges past its own frame.
    private static let margin: CGFloat = 40
    /// How far the card stands in from the screen's top and left edges.
    private static let screenInset: CGFloat = 20
    private static let fadeIn: TimeInterval = 0.25
    private static let nanosecondsPerSecond: UInt64 = 1_000_000_000

    init() {
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.initialHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The card draws its own soft shadow; the window's would trace that shadow's edge as a rough outline.
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
    }

    func present(_ summary: SummaryCard, open: (() -> Void)? = nil, watch: (() -> Void)? = nil) {
        let card = CardView(
            summary: summary,
            close: { [weak self] in self?.dismiss() },
            open: open.map { go in { [weak self] in go(); self?.dismiss() } },
            watch: watch.map { go in { [weak self] in go(); self?.dismiss() } },
            hovering: { [weak self] inside in self?.hovering(inside) }
        )
        host(card, for: Self.showFor)
    }

    /// A trace as a waterfall in the same corner, up long enough to read every step.
    func present(_ trace: TraceData, title: String) {
        let view = TraceView(
            trace: trace,
            title: title,
            close: { [weak self] in self?.dismiss() },
            hovering: { [weak self] inside in self?.hovering(inside) }
        )
        host(view, for: Self.showFor)
    }

    /// Any card, put where `place` says from its size and margin, which is how a wall lays several out.
    func present<Card: View>(_ card: Card, place: @escaping (NSSize, CGFloat) -> NSPoint) {
        host(card, for: Self.showFor, place: place)
    }

    /// The walk through in the same corner, up for as long as the voice takes to say it and a little after.
    func present(_ walk: WalkCard, open: (() -> Void)? = nil) {
        let view = WalkView(
            walk: walk,
            close: { [weak self] in self?.dismiss() },
            open: open.map { go in { [weak self] in go(); self?.dismiss() } },
            hovering: { [weak self] inside in self?.hovering(inside) }
        )
        let speaking = walk.pages.reduce(0) { $0 + WalkView.seconds(for: $1) }
        host(view, for: UInt64(speaking) + Self.afterLeaving)
    }

    private func host<Card: View>(_ card: Card, for seconds: UInt64, place: ((NSSize, CGFloat) -> NSPoint)? = nil) {
        let margin = Self.margin
        let view = FirstClickHosting(rootView: card.padding(margin))
        let size = view.fittingSize
        panel.contentView = view
        if let place {
            panel.setFrame(NSRect(origin: place(size, margin), size: size), display: true)
        } else if let screen = NSScreen.main?.visibleFrame {
            panel.setFrame(
                NSRect(
                    x: screen.minX + Self.screenInset - margin,
                    y: screen.maxY - size.height - Self.screenInset + margin,
                    width: size.width,
                    height: size.height
                ),
                display: true
            )
        }
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = Self.fadeIn; panel.animator().alphaValue = 1 }
        }
        hideAfter(seconds)
    }

    /// Never goes while the pointer is on it, since that is somebody reading it or about to click.
    func hovering(_ inside: Bool) {
        if inside { hide?.cancel() } else { hideAfter(Self.afterLeaving) }
    }

    private func hideAfter(_ seconds: UInt64) {
        hide?.cancel()
        hide = Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * Self.nanosecondsPerSecond)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        hide?.cancel()
        NSAnimationContext.runAnimationGroup({ $0.duration = Memnox.Motion.standard; panel.animator().alphaValue = 0 }) { [panel] in
            panel.orderOut(nil)
        }
    }
}

/// Whether the card has swung in yet, so it turns out of the screen rather than fading up flat.
@MainActor
final class CardEntrance: ObservableObject {
    @Published var shown = false
    /// The pointer is on it: it turns to face the person, so every button sits where it is drawn.
    @Published var facing = false
}
