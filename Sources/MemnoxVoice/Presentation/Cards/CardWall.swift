import AppKit
import MemnoxVoiceCore
import SwiftUI

/// A hosting view that takes the first click, since a panel that never activates Memnox would
/// otherwise spend that click becoming key and the button under it would do nothing.
final class FirstClickHosting<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Every session as a card of its own, slid onto the screen one after another and laid out in
/// columns from the top left, so all of them can be read at once and each closed on its own.
@MainActor
final class CardWall {
    private var panels: [CardPanel] = []
    /// As many as fit on a laptop screen and can each still be read.
    static let most = 8
    /// A beat between cards, so they slide in one after another rather than all landing at once.
    private static let stagger: TimeInterval = 0.09
    private static let gap: CGFloat = 16
    /// How often the cards on the wall are read again while they are up.
    private static let refresh: TimeInterval = 2
    private static let nanosecondsPerSecond: TimeInterval = 1_000_000_000
    /// How far the wall stands in from the screen's top and left edges, as a single card does.
    private static let screenInset: CGFloat = 20
    private var showing: Task<Void, Never>?
    /// Where each column's lowest card ends, so the next card goes under the shortest column.
    private var bottoms: [CGFloat] = []

    func present(
        _ cards: [SessionCard],
        fetch: @escaping (String) async -> SessionView?,
        watch: @escaping (SessionCard) -> Void,
        open: @escaping (SessionCard) -> Void
    ) {
        dismiss()
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let columns = max(1, Int((screen.width - Self.gap) / (CardPanel.width + Self.gap)))
        bottoms = Array(repeating: screen.maxY - Self.screenInset, count: columns)
        let shown = Array(cards.prefix(Self.most))
        let panels = shown.map { _ in CardPanel() }
        self.panels = panels
        let models = shown.map { _ in LiveModel() }
        showing = Task { [weak self] in
            // Read before any card is drawn, so each one is sized for what it will show.
            for (card, model) in zip(shown, models) { model.view = await fetch(card.sessionId) }
            for (card, (panel, model)) in zip(shown, zip(panels, models)) {
                guard let self, !Task.isCancelled else { return }
                panel.present(
                    SessionPopupView(
                        card: card,
                        model: model,
                        close: { panel.dismiss() },
                        watch: { [weak self] in watch(card); self?.dismiss() },
                        open: card.host == nil ? nil : { [weak self] in open(card); self?.dismiss() },
                        hovering: { panel.hovering($0) }
                    ),
                    place: { size, margin in self.place(size, margin: margin, on: screen) }
                )
                try? await Task.sleep(nanoseconds: Self.nanoseconds(Self.stagger))
            }
            // Kept current while the cards are up, the way the live window is.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.nanoseconds(Self.refresh))
                for (card, model) in zip(shown, models) {
                    guard !Task.isCancelled, let fresh = await fetch(card.sessionId) else { continue }
                    withAnimation(.easeOut(duration: Memnox.Motion.standard)) { model.view = fresh }
                }
            }
        }
    }

    /// The shortest column takes the next card, so the wall stays even.
    private func place(_ size: NSSize, margin: CGFloat, on screen: NSRect) -> NSPoint {
        let column = bottoms.indices.min { bottoms[$0] > bottoms[$1] } ?? 0
        let x = screen.minX + Self.screenInset + CGFloat(column) * (CardPanel.width + Self.gap)
        let top = bottoms[column]
        bottoms[column] = top - (size.height - 2 * margin) - Self.gap
        return NSPoint(x: x - margin, y: top - size.height + margin)
    }

    /// A sleep length in seconds as the nanoseconds `Task.sleep` takes.
    private static func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
        UInt64((seconds * nanosecondsPerSecond).rounded())
    }

    func dismiss() {
        showing?.cancel()
        panels.forEach { $0.dismiss() }
        panels = []
    }
}
