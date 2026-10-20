// Adapted from PermissionFlow (github.com/jaywcjlove/PermissionFlow), MIT License, Copyright (c) 2026 小弟调调.
// See THIRD_PARTY_NOTICES.md at the root of this repository.
import AppKit
import CoreGraphics

/// Follows the System Settings window on screen, so the helper under it moves when it moves. The window server alone
/// is read, which needs no grant, since the person may still be on their way to granting Accessibility.
@MainActor
final class SettingsWindowTracker {
    /// The window's frame in AppKit's screen space each time it changes.
    var moved: ((CGRect) -> Void)?
    /// Called once System Settings has gone for good.
    var ended: (() -> Void)?
    private(set) var frame: CGRect?

    private static let bundleId = "com.apple.systempreferences"
    /// Thirty times a second, so the helper never trails a window being dragged.
    private static let pollInterval: TimeInterval = 1.0 / 30.0
    /// Settings briefly has no window while it swaps panes, so only this many misses in a row mean it has quit.
    private static let missesBeforeEnded = 12
    /// Smaller than any real Settings window, so a sheet or a tooltip it puts up is never taken for it.
    private static let smallest = CGSize(width: 320, height: 240)

    private var timer: Timer?
    private var misses = 0

    func start() {
        stop()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
        timer.tolerance = Self.pollInterval / 4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        frame = nil
        misses = 0
    }

    /// The running System Settings, preferring the one with a face over a helper process under the same id.
    static var settings: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .max { ($0.activationPolicy == .prohibited ? 0 : 1) < ($1.activationPolicy == .prohibited ? 0 : 1) }
    }

    private func poll() {
        guard let app = Self.settings, let found = Self.largestWindow(of: app.processIdentifier) else {
            misses += 1
            if misses >= Self.missesBeforeEnded, timer != nil {
                stop()
                ended?()
            }
            return
        }
        misses = 0
        guard found != frame else { return }
        frame = found
        moved?(found)
    }

    /// The largest visible window of the process on the ordinary layer, which is the Settings window itself.
    private static func largestWindow(of pid: pid_t) -> CGRect? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        return windows
            .filter {
                ($0[kCGWindowOwnerPID as String] as? pid_t) == pid
                    && ($0[kCGWindowLayer as String] as? Int ?? 0) == 0
                    && ($0[kCGWindowAlpha as String] as? Double ?? 1) > 0
            }
            .compactMap { window -> CGRect? in
                guard let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                      let rect = CGRect(dictionaryRepresentation: bounds),
                      rect.width > smallest.width, rect.height > smallest.height
                else { return nil }
                return appKitFrame(rect)
            }
            .max { $0.width * $0.height < $1.width * $1.height }
    }

    /// The window server counts from the top left of the main display and AppKit from the bottom left of each screen,
    /// so the frame is moved onto the screen that holds most of it.
    private static func appKitFrame(_ frame: CGRect) -> CGRect {
        let number = NSDeviceDescriptionKey("NSScreenNumber")
        let screens = NSScreen.screens.compactMap { screen -> (appKit: CGRect, display: CGRect)? in
            guard let id = screen.deviceDescription[number] as? NSNumber else { return nil }
            return (screen.frame, CGDisplayBounds(CGDirectDisplayID(id.uint32Value)))
        }
        func overlap(_ display: CGRect) -> CGFloat {
            let shared = display.intersection(frame)
            return shared.isNull ? 0 : shared.width * shared.height
        }
        guard let screen = screens.max(by: { overlap($0.display) < overlap($1.display) }), overlap(screen.display) > 0 else { return frame }
        return CGRect(
            x: screen.appKit.minX + frame.minX - screen.display.minX,
            y: screen.appKit.maxY - (frame.minY - screen.display.minY) - frame.height,
            width: frame.width,
            height: frame.height
        )
    }
}
