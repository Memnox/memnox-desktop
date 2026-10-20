// Adapted from PermissionFlow (github.com/jaywcjlove/PermissionFlow), MIT License, Copyright (c) 2026 小弟调调.
// See THIRD_PARTY_NOTICES.md at the root of this repository.
import AppKit
import QuartzCore
import SwiftUI

/// The window the helper lives in: borderless, floating over System Settings and never taking focus from it, docked
/// under the pane's side of the Settings window, and flown there from the pointer when it first appears.
@MainActor
final class SettingsHelperPanel: NSPanel {
    private let hosting: NSHostingView<AnyView>
    /// A second copy of the content, laid out off screen only to learn how tall the panel must be at a width.
    private let sizing: NSHostingView<AnyView>
    /// Clicked on: System Settings comes back in front, so the person never has to find it again.
    var touched: () -> Void = {}

    private enum Layout {
        /// Settings' sidebar, which the panel leaves uncovered so it sits under the pane being changed.
        static let sidebar: CGFloat = 230
        static let narrowest: CGFloat = 340
        static let widest: CGFloat = 560
        static let screenInset: CGFloat = 12
        static let shortest: CGFloat = 96
        static let measureLimit: CGFloat = 2000
        /// Tucked up under the window's edge, which the window server counts with a little framing below it.
        static let tuck: CGFloat = 6
    }

    private enum Launch {
        static let duration: TimeInterval = 0.72
        static let startAlpha: CGFloat = 0.9
        static let startScale: CGFloat = 0.58
        /// How far the flight arcs above the straight line, more for a longer flight, within these bounds.
        static let lowestArc: CGFloat = 44
        static let highestArc: CGFloat = 140
        static let arcShare: CGFloat = 0.18
        static let frameRate: TimeInterval = 1.0 / 60.0
    }

    /// Faint while a drag is under way, so the person sees the list through it as they drop.
    private static let draggingAlpha: CGFloat = 0.72

    private var flight: Timer?
    private var flightStart: CFTimeInterval = 0
    private var flightFrom = CGRect.zero
    private var flightTo = CGRect.zero
    private var flying = false

    init<Content: View>(content: Content) {
        hosting = NSHostingView(rootView: AnyView(content))
        sizing = NSHostingView(rootView: AnyView(content))
        super.init(contentRect: CGRect(x: 0, y: 0, width: Layout.narrowest, height: Layout.shortest),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
        // Left to size itself, the hosting view grows the window past the measured height and undoes every move.
        hosting.sizingOptions = []
        contentView = hosting
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { touched() }
        super.sendEvent(event)
    }

    /// Flies in from the pointer to its place under Settings, or simply appears there when motion is reduced.
    func present(under settings: CGRect, from pointer: CGPoint, reduceMotion: Bool) {
        stopFlight()
        let target = dock(under: settings)
        guard !reduceMotion else {
            alphaValue = 1
            setFrame(target, display: false)
            orderFrontRegardless()
            return
        }
        let start = CGSize(width: target.width * Launch.startScale, height: target.height * Launch.startScale)
        flightFrom = CGRect(x: pointer.x - start.width / 2, y: pointer.y - start.height / 2, width: start.width, height: start.height)
        flightTo = target
        flightStart = CACurrentMediaTime()
        flying = true
        alphaValue = Launch.startAlpha
        setFrame(flightFrom, display: false)
        orderFrontRegardless()
        let timer = Timer(timeInterval: Launch.frameRate, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stepFlight() }
        }
        RunLoop.main.add(timer, forMode: .common)
        flight = timer
    }

    /// Settings moved or resized: a flight under way changes only where it lands, so the motion never jumps.
    func follow(_ settings: CGRect) {
        let target = dock(under: settings)
        if flying {
            flightTo = target
            return
        }
        setFrame(target, display: true)
    }

    /// While the app is dragged the panel lets the pointer through and steps behind, so the drop lands in Settings.
    func dragging(_ on: Bool) {
        ignoresMouseEvents = on
        alphaValue = on ? Self.draggingAlpha : 1
        if on { orderBack(nil) } else { orderFrontRegardless() }
    }

    /// Fades out and closes.
    func leave(reduceMotion: Bool) {
        stopFlight()
        guard !reduceMotion else {
            orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Memnox.Motion.standard
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.orderOut(nil)
                self?.alphaValue = 1
            }
        }
    }

    /// Under the pane's side of the Settings window, as wide as that side, kept on the screen it is on.
    private func dock(under settings: CGRect) -> CGRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(settings) }?.visibleFrame ?? settings
        let width = min(max(settings.width - Layout.sidebar, Layout.narrowest), Layout.widest, screen.width - 2 * Layout.screenInset)
        sizing.setFrameSize(NSSize(width: width, height: Layout.measureLimit))
        sizing.layoutSubtreeIfNeeded()
        let height = max(Layout.shortest, sizing.fittingSize.height)
        let x = min(max(settings.minX + Layout.sidebar, screen.minX + Layout.screenInset), screen.maxX - width - Layout.screenInset)
        let y = min(max(settings.minY - height + Layout.tuck, screen.minY + Layout.screenInset), screen.maxY - height - Layout.screenInset)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func stepFlight() {
        let elapsed = CACurrentMediaTime() - flightStart
        guard elapsed < Launch.duration else {
            stopFlight()
            alphaValue = 1
            setFrame(flightTo, display: true)
            return
        }
        // A critically damped spring: quick off the mark and settling without overshooting the window it docks to.
        let omega = 2 * Double.pi / Launch.duration
        let progress = CGFloat(min(max(1 - exp(-omega * elapsed) * (1 + omega * elapsed), 0), 1))
        alphaValue = Launch.startAlpha + (1 - Launch.startAlpha) * progress
        setFrame(arc(progress), display: true)
    }

    /// Along a curve that rises above the straight line, so the panel is seen to fly rather than slide.
    private func arc(_ progress: CGFloat) -> CGRect {
        let from = CGPoint(x: flightFrom.midX, y: flightFrom.midY), to = CGPoint(x: flightTo.midX, y: flightTo.midY)
        let lift = min(Launch.highestArc, max(Launch.lowestArc, hypot(to.x - from.x, to.y - from.y) * Launch.arcShare))
        let control = CGPoint(x: (from.x + to.x) / 2, y: max(from.y, to.y) + lift)
        let rest = 1 - progress
        let center = CGPoint(
            x: rest * rest * from.x + 2 * rest * progress * control.x + progress * progress * to.x,
            y: rest * rest * from.y + 2 * rest * progress * control.y + progress * progress * to.y
        )
        let size = CGSize(width: flightFrom.width + (flightTo.width - flightFrom.width) * progress,
                          height: flightFrom.height + (flightTo.height - flightFrom.height) * progress)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }

    private func stopFlight() {
        flight?.invalidate()
        flight = nil
        flying = false
    }
}

/// The app as a tile that drags like a file from Finder, which is the drag System Settings takes into its lists.
struct AppDragTile: NSViewRepresentable {
    let app: URL
    let dragging: (Bool) -> Void

    func makeNSView(context: Context) -> AppDragSource {
        AppDragSource(app: app, dragging: dragging)
    }

    func updateNSView(_ view: AppDragSource, context: Context) {
        view.dragging = dragging
    }
}

final class AppDragSource: NSView, NSDraggingSource {
    private let app: URL
    var dragging: (Bool) -> Void
    private var downAt: NSPoint?

    /// Far enough that a click is never taken for a drag.
    private static let dragAfter: CGFloat = 4
    private static let iconSide: CGFloat = 56

    init(app: URL, dragging: @escaping (Bool) -> Void) {
        self.app = app
        self.dragging = dragging
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        downAt = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downAt else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - downAt.x, point.y - downAt.y) > Self.dragAfter else { return }
        self.downAt = nil
        let item = NSDraggingItem(pasteboardWriter: AppFileWriter(app: app))
        let icon = NSWorkspace.shared.icon(forFile: app.path)
        icon.size = NSSize(width: Self.iconSide, height: Self.iconSide)
        item.setDraggingFrame(NSRect(x: point.x - Self.iconSide / 2, y: point.y - Self.iconSide / 2, width: Self.iconSide, height: Self.iconSide), contents: icon)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .none
    }

    override func mouseUp(with event: NSEvent) {
        downAt = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) { dragging(true) }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { dragging(false) }
}

/// Every type Finder puts on the pasteboard for a file, since System Settings takes a drop more readily the closer it
/// looks to one from Finder.
private final class AppFileWriter: NSObject, NSPasteboardWriting {
    private let app: URL
    private static let filenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    private static let promised = NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")

    init(app: URL) {
        self.app = app
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.fileURL, .URL, Self.filenames, Self.promised, .string]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type {
        case .fileURL, .URL, Self.promised: return app.absoluteString
        case Self.filenames: return [app.path]
        case .string: return app.path
        default: return nil
        }
    }
}
