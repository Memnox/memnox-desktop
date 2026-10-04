import AppKit
import SwiftUI

/// The history at the left of the screen, a notch on its side: a thin tab rests at the middle of the
/// left edge, swells when the pointer touches it, and grows into the panel after a short rest there.
/// It never takes the keyboard until the search is clicked, so opening it never pulls focus from the editor.
@MainActor
final class SidePanel: NSPanel {
    private let model: IslandModel
    private var outside: EventMonitor?
    private var escape: EventMonitor?
    private var poll: Timer?
    /// When the pointer came to rest on the tab, to open after a short dwell like the notch.
    private var restingSince: Date?
    /// When the pointer left the open panel, to close after a short grace rather than on a stray flick.
    private var leftAt: Date?
    /// Whether the pointer has been over the open panel, since one opened from the notch should not close before it arrives.
    private var visited = false

    private enum Layout {
        static let width: CGFloat = 330
        /// As tall as the screen allows up to this, so a long history reads without the panel filling the screen.
        static let tallest: CGFloat = 700
        /// Off the menu bar and the Dock on a short screen, while its side stays flush with the screen's left edge.
        static let margin: CGFloat = 10
        /// How far past the tab the pointer still counts as touching it, since the edge is easy to overshoot.
        static let tabSlop: CGFloat = 8
        /// How far past the open panel the pointer still counts as inside it.
        static let panelSlop: CGFloat = 6
    }

    private enum Timing {
        /// The pointer is polled at this rate, the same as the notch.
        static let framesPerSecond = 60.0
        /// Long enough that sweeping past the edge to reach a scroll bar does not open it.
        static let dwell: TimeInterval = 0.25
        /// How long the pointer may be away from the open panel before it folds back into the tab.
        static let grace: TimeInterval = 0.45
    }

    init(model: IslandModel) {
        self.model = model
        super.init(
            contentRect: NSRect(origin: .zero, size: NSSize(width: Layout.width, height: Layout.tallest)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        // A shadow would draw along the screen edge the panel is meant to be part of.
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        appearance = NSAppearance(named: .darkAqua)
        let host = FirstClickHosting(rootView: SideView(model: model))
        // The window keeps its own size, since the tab grows into the panel inside it rather than with it.
        host.sizingOptions = []
        contentView = host
        place()
        orderFrontRegardless()
        // Polled rather than tracked, because the window is larger than the tab and must let clicks past it.
        poll = Timer.scheduledTimer(withTimeInterval: 1 / Timing.framesPerSecond, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.follow() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }
    }

    /// Key only when the search is clicked, which a nonactivating panel allows without bringing the app forward.
    override var canBecomeKey: Bool { true }

    func toggle() {
        model.sideOpen ? close(animated: true) : open()
    }

    func open() {
        guard !model.sideOpen else { return }
        restingSince = nil
        leftAt = nil
        visited = false
        ignoresMouseEvents = false
        withAnimation(SideMotion.grow) {
            model.sideHovering = false
            model.sideOpen = true
        }
        watchForDismissal()
    }

    func close(animated: Bool) {
        guard model.sideOpen else { return }
        outside?.stop()
        escape?.stop()
        leftAt = nil
        model.query = ""
        withAnimation(animated ? SideMotion.shrink : nil) { model.sideOpen = false }
        if isKeyWindow { resignKey() }
    }

    /// At the middle of the left edge of the screen with the notch, or the main one on a Mac without.
    private func place() {
        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let height = min(visible.height - 2 * Layout.margin, Layout.tallest)
        // Centred on the screen's height, so it sits level with the eye rather than hanging from the menu bar.
        setFrame(NSRect(x: visible.minX, y: visible.midY - height / 2, width: Layout.width, height: height), display: true)
    }

    /// Every frame: lets clicks through outside what is drawn, opens on a rest at the tab, and folds back once left.
    private func follow() {
        let mouse = NSEvent.mouseLocation
        let now = Date()
        if model.sideOpen {
            let over = frame.insetBy(dx: -Layout.panelSlop, dy: -Layout.panelSlop).contains(mouse)
            if over {
                visited = true
                leftAt = nil
            } else if visited, !model.sidePinned, !isKeyWindow {
                let since = leftAt ?? now
                leftAt = since
                if now.timeIntervalSince(since) >= Timing.grace { close(animated: true) }
            }
            return
        }
        let size = SideMotion.tab(hovering: model.sideHovering)
        let tab = NSRect(x: frame.minX, y: frame.midY - size.height / 2, width: size.width, height: size.height)
        let touching = tab.insetBy(dx: -Layout.tabSlop, dy: -Layout.tabSlop).contains(mouse)
        if ignoresMouseEvents == touching { ignoresMouseEvents = !touching }
        if touching != model.sideHovering {
            withAnimation(SideMotion.swell) { model.sideHovering = touching }
        }
        guard touching else {
            restingSince = nil
            return
        }
        let since = restingSince ?? now
        restingSince = since
        if now.timeIntervalSince(since) >= Timing.dwell { open() }
    }

    /// A click in another app closes it unless it is pinned; Escape closes it once it has the keyboard.
    private func watchForDismissal() {
        outside = EventMonitor.global([.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.model.sidePinned else { return }
                self.close(animated: true)
            }
        }
        escape = EventMonitor.local(.keyDown) { [weak self] event in
            guard event.keyCode == KeyCode.escape, let self, self.isKeyWindow else { return event }
            self.close(animated: true)
            return nil
        }
    }
}

/// The tab's sizes and the springs it moves with, shared by the panel that hit tests it and the view that draws it.
enum SideMotion {
    /// Barely there at rest, a sliver of black at the edge like the notch, and a little fuller under the pointer.
    private static let restingTab = CGSize(width: 6, height: 64)
    private static let hoveringTab = CGSize(width: 12, height: 96)
    /// The tab's own flare, smaller than the panel's so the resting sliver stays a few points deep.
    static let tabFlare: CGFloat = 4

    /// The tab as drawn from the screen edge, its flare included.
    static func tab(hovering: Bool) -> CGSize { hovering ? hoveringTab : restingTab }

    static let grow = Animation.spring(response: 0.38, dampingFraction: 0.78)
    static let shrink = Animation.spring(response: 0.3, dampingFraction: 0.9)
    static let swell = Animation.spring(response: 0.28, dampingFraction: 0.6)
}
