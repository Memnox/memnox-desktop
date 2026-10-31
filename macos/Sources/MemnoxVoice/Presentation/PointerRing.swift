import AppKit
import MemnoxVoiceCore
import SwiftUI

/// A ring pulsing over the spot the brain found on a screen picture, with a short label, so "where do I click" is
/// answered on the screen itself. It never takes a click or the keyboard, and goes on the next one or after a while.
@MainActor
final class PointerRing {
    private let panel: NSPanel
    private var hide: Task<Void, Never>?
    private var watching: [EventMonitor] = []

    /// Long enough to find the ring and move to it, never a mark left on the screen.
    private static let showFor: Duration = .seconds(20)
    /// The ring itself, big enough to catch the eye and small enough to sit on one button.
    static let ring: CGFloat = 64
    /// Room around the ring for its pulse and its label.
    private static let size = NSSize(width: 320, height: 200)
    /// How far below or above the ring's middle its label sits.
    static let labelOffset: CGFloat = 60
    /// Closer than this to the bottom of a display, the label goes above the ring so it stays on screen.
    private static let labelRoom: CGFloat = 90

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Above full screen apps and menus, since what it points at can be anywhere.
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        // Every click goes through to what is under it, which is the thing pointed at.
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true
    }

    /// The ring on the display the spot's picture was taken of, at the spot scaled from picture pixels to that
    /// display's points; false when no display or no spot on it matches.
    func show(_ spot: ScreenSpot, label: String) -> Bool {
        let screens = NSScreen.screens
        guard screens.indices.contains(spot.screen) else { return false }
        let frame = screens[spot.screen].frame
        guard let local = spot.points(across: frame.width, down: frame.height) else { return false }
        // The picture counts down from its top left and AppKit counts up from the bottom left of the whole desktop.
        let center = NSPoint(x: frame.minX + local.x, y: frame.maxY - local.y)
        let below = center.y - frame.minY > Self.labelRoom
        panel.setFrame(NSRect(x: center.x - Self.size.width / 2, y: center.y - Self.size.height / 2,
                              width: Self.size.width, height: Self.size.height), display: false)
        panel.contentView = NSHostingView(rootView: PointerRingView(label: label, labelBelow: below))
        panel.orderFrontRegardless()
        watchForTheNextTouch()
        hide?.cancel()
        hide = Task { [weak self] in
            try? await Task.sleep(for: Self.showFor)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
        return true
    }

    func dismiss() {
        hide?.cancel()
        hide = nil
        watching.forEach { $0.stop() }
        watching = []
        panel.orderOut(nil)
    }

    /// The person moved on once they click or type anywhere, in another app or in Memnox, so the ring goes then.
    private func watchForTheNextTouch() {
        watching.forEach { $0.stop() }
        let touches: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        watching = [
            EventMonitor.global(touches) { [weak self] _ in
                Task { @MainActor in self?.dismiss() }
            },
            EventMonitor.local(touches) { [weak self] event in
                self?.dismiss()
                return event
            },
        ]
    }
}

/// The ring and its label; it breathes in and out unless the person asked macOS to reduce motion.
private struct PointerRingView: View {
    let label: String
    let labelBelow: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var out = false

    /// One breath, slow enough to read as a pulse rather than a flicker.
    private static let breath: TimeInterval = 0.9

    var body: some View {
        ZStack {
            Circle()
                .fill(Memnox.Palette.primary.opacity(0.18))
                .frame(width: PointerRing.ring, height: PointerRing.ring)
            Circle()
                .stroke(Memnox.Palette.primary, lineWidth: 4)
                .frame(width: PointerRing.ring, height: PointerRing.ring)
                .scaleEffect(out ? 1.25 : 1)
                .opacity(out ? 0.45 : 1)
            if !label.isEmpty {
                Text(label)
                    .font(Memnox.sans(13, .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.8)))
                    .offset(y: labelBelow ? PointerRing.labelOffset : -PointerRing.labelOffset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label.isEmpty ? "Here" : label)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: Self.breath).repeatForever(autoreverses: true)) { out = true }
        }
    }
}
