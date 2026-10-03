import AppKit
import CoreGraphics
import SwiftUI

/// Converts the seconds the panel waits into the nanoseconds `Task.sleep` takes.
private let nanosecondsPerSecond: TimeInterval = 1_000_000_000

/// One on screen window, as much of the Window Server's description of it as the flight reads.
private struct WindowInfo {
    let layer: Int
    let owner: String
    let bounds: CGRect
}

/// The window owner names a spoken app name is matched against, lower cased.
private enum AppName {
    static let code = "code"
    static let visualStudio = "visual studio"
    static let cursor = "cursor"
    static let iTerm = "iterm"
    static let terminal = "terminal"
}

/// A sent instruction, seen leaving: a glowing comet arcs from the orb to the window of the
/// session it was sent to, and rings out where it lands. It is drawn on a clear layer over
/// the whole screen that the pointer passes straight through, and gone a moment after.
@MainActor
final class FlightPanel {
    private let panel: NSPanel
    /// Long enough to follow with the eye, short enough that the agent's reply is not kept waiting.
    static let duration: TimeInterval = 0.9
    /// Room after landing for the ring to spread and fade before the panel goes.
    private static let linger: TimeInterval = 0.6
    /// Layer 0 holds ordinary app windows, above it are menus, the Dock and overlays.
    private static let appWindowLayer = 0
    /// Smaller than this is a palette or a tooltip rather than the window a session lives in.
    private static let minWindowWidth: CGFloat = 200
    private static let minWindowHeight: CGFloat = 120

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    /// Flies from a point on screen to the window of the named app, or the middle of the screen when it cannot be found.
    func fly(from start: NSPoint, toApp app: String) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        let end = Self.windowCentre(of: app) ?? NSPoint(x: frame.midX, y: frame.midY)
        // SwiftUI measures from the top left, the screen from the bottom left.
        let flip = { (point: NSPoint) in CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y) }
        panel.setFrame(frame, display: false)
        panel.contentView = NSHostingView(rootView: FlightView(from: flip(start), to: flip(end), began: Date()))
        panel.orderFrontRegardless()
        Task { [panel] in
            try? await Task.sleep(nanoseconds: UInt64((Self.duration + Self.linger) * nanosecondsPerSecond))
            panel.orderOut(nil)
            panel.contentView = nil
        }
    }

    /// The middle of the app's frontmost window, in screen coordinates; bounds need no permission to read.
    private static func windowCentre(of app: String) -> NSPoint? {
        let wanted = app.lowercased()
        guard !wanted.isEmpty,
              let mainHeight = NSScreen.screens.first?.frame.height
        else { return nil }
        for window in onScreenWindows() {
            let bounds = window.bounds
            guard window.layer == appWindowLayer,
                  matches(owner: window.owner.lowercased(), app: wanted),
                  bounds.size.width > minWindowWidth, bounds.size.height > minWindowHeight
            else { continue }
            return NSPoint(x: bounds.origin.x + bounds.size.width / 2, y: mainHeight - (bounds.origin.y + bounds.size.height / 2))
        }
        return nil
    }

    /// The Window Server describes windows as untyped dictionaries, so they are read into `WindowInfo` here and nowhere else.
    private static func onScreenWindows() -> [WindowInfo] {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        return windows.compactMap { window in
            guard let layer = window[kCGWindowLayer as String] as? Int,
                  let owner = window[kCGWindowOwnerName as String] as? String,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { return nil }
            return WindowInfo(layer: layer, owner: owner, bounds: rect)
        }
    }

    /// "Visual Studio Code" runs as "Code", and iTerm as "iTerm2", so the names are matched loosely.
    private static func matches(owner: String, app: String) -> Bool {
        if app.contains(AppName.code) && !app.contains(AppName.cursor) { return owner == AppName.code || owner.contains(AppName.visualStudio) }
        if app.contains(AppName.iTerm) { return owner.contains(AppName.iTerm) }
        if app.contains(AppName.terminal) { return owner == AppName.terminal }
        return owner.contains(app) || app.contains(owner)
    }
}

/// The comet along a curve, its tail fading behind it, and a ring where it lands.
private struct FlightView: View {
    let from: CGPoint
    let to: CGPoint
    let began: Date

    private enum Comet {
        /// The head and six dots of tail, each a step further behind and a point smaller.
        static let dots = 7
        static let lag = 0.035
        static let headSize: CGFloat = 14
        static let headGlow: CGFloat = 14
        static let tailGlow: CGFloat = 6
        static let fadePerDot = 0.13
    }

    private enum Landing {
        static let lineWidth: CGFloat = 2
        static let startSize = 30.0
        /// Points the ring grows by each second after landing.
        static let growth = 260.0
        static let fade: TimeInterval = 0.55
    }

    private enum Arc {
        /// The curve rises by this share of the distance, capped so a long flight does not leave the screen.
        static let liftShare: CGFloat = 0.35
        static let maxLift: CGFloat = 260
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(began)
            let progress = min(1, elapsed / FlightPanel.duration)
            let landed = max(0, elapsed - FlightPanel.duration)
            ZStack {
                ForEach(0..<Comet.dots, id: \.self) { index in
                    let behind = max(0, eased(progress) - Double(index) * Comet.lag)
                    Circle()
                        .fill(index == 0 ? Color.white : Memnox.Palette.sky)
                        .frame(width: Comet.headSize - CGFloat(index), height: Comet.headSize - CGFloat(index))
                        .shadow(color: Memnox.Palette.primary, radius: index == 0 ? Comet.headGlow : Comet.tailGlow)
                        .opacity(progress >= 1 ? 0 : 1 - Double(index) * Comet.fadePerDot)
                        .position(point(at: behind))
                }
                if landed > 0 {
                    Circle()
                        .strokeBorder(Memnox.Palette.sky, lineWidth: Landing.lineWidth)
                        .frame(width: Landing.startSize + landed * Landing.growth, height: Landing.startSize + landed * Landing.growth)
                        .opacity(max(0, 1 - landed / Landing.fade))
                        .position(to)
                }
            }
        }
        .ignoresSafeArea()
    }

    /// A curve that rises above the straight line between the two, the way something thrown travels.
    private func point(at t: Double) -> CGPoint {
        let lift = min(Arc.maxLift, hypot(to.x - from.x, to.y - from.y) * Arc.liftShare)
        let control = CGPoint(x: (from.x + to.x) / 2, y: min(from.y, to.y) - lift)
        let u = 1 - t
        return CGPoint(
            x: u * u * from.x + 2 * u * t * control.x + t * t * to.x,
            y: u * u * from.y + 2 * u * t * control.y + t * t * to.y
        )
    }

    /// The standard ease in and out quadratic, so the comet speeds up off the orb and slows into the window.
    private func eased(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }
}
