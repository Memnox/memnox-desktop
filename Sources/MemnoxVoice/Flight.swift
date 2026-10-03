import AppKit
import CoreGraphics
import SwiftUI

/// A sent instruction, seen leaving: a glowing comet arcs from the orb to the window of the
/// session it was sent to, and rings out where it lands. It is drawn on a clear layer over
/// the whole screen that the pointer passes straight through, and gone a moment after.
@MainActor
final class FlightPanel {
    private let panel: NSPanel
    /// Long enough to follow with the eye, short enough that the agent's reply is not kept waiting.
    static let duration: TimeInterval = 0.9

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
            try? await Task.sleep(nanoseconds: UInt64((Self.duration + 0.6) * 1_000_000_000))
            panel.orderOut(nil)
            panel.contentView = nil
        }
    }

    /// The middle of the app's frontmost window, in screen coordinates; bounds need no permission to read.
    private static func windowCentre(of app: String) -> NSPoint? {
        let wanted = app.lowercased()
        guard !wanted.isEmpty,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let mainHeight = NSScreen.screens.first?.frame.height
        else { return nil }
        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let owner = (window[kCGWindowOwnerName as String] as? String)?.lowercased(),
                  matches(owner: owner, app: wanted),
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"], let width = bounds["Width"], let height = bounds["Height"],
                  width > 200, height > 120
            else { continue }
            return NSPoint(x: x + width / 2, y: mainHeight - (y + height / 2))
        }
        return nil
    }

    /// "Visual Studio Code" runs as "Code", and iTerm as "iTerm2", so the names are matched loosely.
    private static func matches(owner: String, app: String) -> Bool {
        if app.contains("code") && !app.contains("cursor") { return owner == "code" || owner.contains("visual studio") }
        if app.contains("iterm") { return owner.contains("iterm") }
        if app.contains("terminal") { return owner == "terminal" }
        return owner.contains(app) || app.contains(owner)
    }
}

/// The comet along a curve, its tail fading behind it, and a ring where it lands.
private struct FlightView: View {
    let from: CGPoint
    let to: CGPoint
    let began: Date

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(began)
            let progress = min(1, elapsed / FlightPanel.duration)
            let landed = max(0, elapsed - FlightPanel.duration)
            ZStack {
                ForEach(0..<7, id: \.self) { index in
                    let behind = max(0, eased(progress) - Double(index) * 0.035)
                    Circle()
                        .fill(index == 0 ? Color.white : Memnox.Palette.sky)
                        .frame(width: CGFloat(14 - index), height: CGFloat(14 - index))
                        .shadow(color: Memnox.Palette.primary, radius: index == 0 ? 14 : 6)
                        .opacity(progress >= 1 ? 0 : 1 - Double(index) * 0.13)
                        .position(point(at: behind))
                }
                if landed > 0 {
                    Circle()
                        .strokeBorder(Memnox.Palette.sky, lineWidth: 2)
                        .frame(width: 30 + landed * 260, height: 30 + landed * 260)
                        .opacity(max(0, 1 - landed / 0.55))
                        .position(to)
                }
            }
        }
        .ignoresSafeArea()
    }

    /// A curve that rises above the straight line between the two, the way something thrown travels.
    private func point(at t: Double) -> CGPoint {
        let lift = min(260, hypot(to.x - from.x, to.y - from.y) * 0.35)
        let control = CGPoint(x: (from.x + to.x) / 2, y: min(from.y, to.y) - lift)
        let u = 1 - t
        return CGPoint(
            x: u * u * from.x + 2 * u * t * control.x + t * t * to.x,
            y: u * u * from.y + 2 * u * t * control.y + t * t * to.y
        )
    }

    private func eased(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }
}
