import AppKit
import ApplicationServices
import MemnoxVoiceCore
import ScreenCaptureKit
import Vision

/// Brings forward the one window or tab of a terminal app that holds a session, found by the lines on
/// screen in it, since apps such as Ghostty, Warp and kitty offer no way to ask which tab runs which program.
/// Its accessibility text is read first; a window that offers none is read off the screen instead.
enum TabFinder {
    /// How long a tab just pressed takes to draw what it holds.
    private static let tabSettle: TimeInterval = 0.08
    private static let nanosecondsPerSecond: TimeInterval = 1_000_000_000
    /// Enough of the text tree for a terminal's scrollback, bounded so a huge window never stalls.
    private static let deepest = 25
    private static let mostCharacters = 60_000
    /// Text shorter than this is a window with nothing readable in it, which is then read off the screen.
    private static let readable = 20
    /// A window with this many tabs or fewer has only the one thing in it to read.
    private static let soleTab = 1
    /// Where a walk down the accessibility tree begins.
    private static let rootDepth = 0

    /// One place a session could be: a window, and a tab inside it when the window has several.
    private struct View {
        let window: AXUIElement
        let tab: AXUIElement?
    }

    /// Where each session's terminal was last found, by its terminal device, so the next action looks there first.
    @MainActor private static var remembered: [String: View] = [:]

    /// True once the session's own window and tab are in front; false when none, or two, hold its lines.
    /// The tab it was found in last time is looked at first, then the one in front, and the search stops
    /// at the first that shows every line, so tabs flip only when it truly has to look.
    @MainActor
    static func bringForward(in app: NSRunningApplication, marks: [String], tty: String? = nil) async -> Bool {
        guard !marks.isEmpty else { return false }
        let windows = AXTree.elements(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute) ?? []
        // Already in front, or where it was last time: one read each and no tab pressed.
        var quick: [View] = []
        if let tty, let last = remembered[tty], AXTree.string(last.window, kAXRoleAttribute) != nil { quick.append(last) }
        if let front = windows.first { quick.append(View(window: front, tab: tabsOf(front).first(where: isSelected))) }
        for view in quick {
            let chosen = tabsOf(view.window).first(where: isSelected)
            if let tab = view.tab { AXUIElementPerformAction(tab, kAXPressAction as CFString) }
            if TabMatch.isCertain(await textOf(view.window, in: app), marks: marks) {
                return await show(view, of: app, remembering: tty)
            }
            // The tab remembered no longer shows it, so the one the person had chosen goes back.
            if let chosen, view.tab != nil { AXUIElementPerformAction(chosen, kAXPressAction as CFString) }
        }
        var views: [View] = []
        var texts: [String] = []
        var selected: [AXUIElement] = []
        for window in windows {
            let tabs = tabsOf(window)
            if tabs.count <= soleTab {
                let text = await textOf(window, in: app)
                if TabMatch.isCertain(text, marks: marks) { return await show(View(window: window, tab: nil), of: app, remembering: tty) }
                views.append(View(window: window, tab: nil))
                texts.append(text)
                continue
            }
            if let current = tabs.first(where: isSelected) { selected.append(current) }
            for tab in tabs {
                AXUIElementPerformAction(tab, kAXPressAction as CFString)
                try? await Task.sleep(nanoseconds: UInt64(tabSettle * nanosecondsPerSecond))
                let text = await textOf(window, in: app)
                if TabMatch.isCertain(text, marks: marks) { return await show(View(window: window, tab: tab), of: app, remembering: tty) }
                views.append(View(window: window, tab: tab))
                texts.append(text)
            }
        }
        guard let found = TabMatch.best(texts, marks: marks) else {
            // Nothing is left on another tab than the one the person had chosen.
            for tab in selected { AXUIElementPerformAction(tab, kAXPressAction as CFString) }
            diary.note("no single tab of \(app.localizedName ?? "the app") shows this session's lines")
            return false
        }
        return await show(views[found], of: app, remembering: tty)
    }

    /// The view brought to the front and kept as where this session's terminal is.
    @MainActor
    private static func show(_ view: View, of app: NSRunningApplication, remembering tty: String?) async -> Bool {
        if let tab = view.tab { AXUIElementPerformAction(tab, kAXPressAction as CFString) }
        AXUIElementPerformAction(view.window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(view.window, kAXMainAttribute as CFString, kCFBooleanTrue)
        if #available(macOS 14, *) { NSApp.yieldActivation(to: app) }
        app.activate()
        if let tty { remembered[tty] = view }
        try? await Task.sleep(nanoseconds: UInt64(tabSettle * nanosecondsPerSecond))
        diary.note("found the session's tab in \(app.localizedName ?? "the app") by what it shows")
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }

    /// The tab buttons of a window's tab bar, where it draws one.
    private static func tabsOf(_ window: AXUIElement) -> [AXUIElement] {
        let groups = (AXTree.elements(window, kAXChildrenAttribute) ?? [])
            .filter { AXTree.string($0, kAXRoleAttribute) == kAXTabGroupRole }
        return groups.flatMap { AXTree.elements($0, kAXTabsAttribute) ?? AXTree.elements($0, kAXChildrenAttribute) ?? [] }
    }

    private static func isSelected(_ tab: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(tab, kAXValueAttribute as CFString, &value) == .success else { return false }
        return (value as? NSNumber)?.boolValue == true
    }

    /// What the window shows, from its accessibility text, or read off the screen when it offers none.
    private static func textOf(_ window: AXUIElement, in app: NSRunningApplication) async -> String {
        var collected = ""
        collect(window, into: &collected, depth: rootDepth)
        if collected.count >= readable { return collected }
        return await recognised(window, in: app) ?? collected
    }

    private static func collect(_ element: AXUIElement, into text: inout String, depth: Int) {
        guard depth < deepest, text.count < mostCharacters else { return }
        let role = AXTree.string(element, kAXRoleAttribute)
        if role == kAXTextAreaRole || role == kAXStaticTextRole || role == kAXTextFieldRole,
           let value = AXTree.string(element, kAXValueAttribute) {
            text += value + "\n"
        }
        for child in AXTree.elements(element, kAXChildrenAttribute) ?? [] {
            collect(child, into: &text, depth: depth + 1)
        }
    }

    /// The window captured and its words recognised, which needs Screen Recording; nil when it cannot be.
    private static func recognised(_ window: AXUIElement, in app: NSRunningApplication) async -> String? {
        guard CGPreflightScreenCaptureAccess(), let image = await capture(window, in: app) else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    /// The on-screen window matching this one by title and size.
    private static func capture(_ window: AXUIElement, in app: NSRunningApplication) async -> CGImage? {
        let title = AXTree.string(window, kAXTitleAttribute)
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return nil }
        let candidates = content.windows.filter { $0.owningApplication?.processID == app.processIdentifier && $0.frame.width > 1 }
        guard let match = candidates.first(where: { title != nil && $0.title == title }) ?? (candidates.count == soleTab ? candidates.first : nil) else {
            return nil
        }
        let configuration = SCStreamConfiguration()
        let scale = NSScreen.main?.backingScaleFactor ?? 1
        configuration.width = Int(match.frame.width * scale)
        configuration.height = Int(match.frame.height * scale)
        configuration.showsCursor = false
        return try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: match),
            configuration: configuration
        )
    }
}
