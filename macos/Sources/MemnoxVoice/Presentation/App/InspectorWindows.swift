import AppKit
import SwiftUI

/// The details of one item popped out of the page into a window of their own, which stays live because the view it
/// hosts still reads the same models. Each window lives until the person closes it.
@MainActor
enum InspectorWindows {
    private static var open: [NSWindow] = []
    private static let closer = Closer()

    fileprivate static func drop(_ window: NSWindow) {
        open.removeAll { $0 === window }
    }

    private enum Layout {
        static let width: CGFloat = 440
        static let height: CGFloat = 620
        static let minWidth: CGFloat = 320
        static let minHeight: CGFloat = 320
    }

    static func open(title: String, content: AnyView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: Layout.minWidth, height: Layout.minHeight)
        window.contentView = NSHostingView(rootView: InspectorWindowView(content: content))
        window.center()
        open.append(window)
        // Dropped once closed, so a closed window is not held for the life of the app.
        window.delegate = closer
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// The popped out details, laid out as the pane laid them out beside the page.
private struct InspectorWindowView: View {
    let content: AnyView

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Memnox.Spacing.xLarge)
        }
        .background(Memnox.Console.card)
        .consoleLook()
    }
}

private final class Closer: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        MainActor.assumeIsolated { InspectorWindows.drop(window) }
    }
}
