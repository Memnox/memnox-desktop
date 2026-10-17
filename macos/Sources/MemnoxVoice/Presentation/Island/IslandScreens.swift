import AppKit
import MemnoxVoiceCore

/// The island's display as the person chose it in Settings, turned into a real screen for the island and the side panel.
@MainActor
enum IslandScreens {
    /// The defaults key the choice is remembered under.
    static let key = "islandScreen"
    /// Posted when the choice changes, so both panels move at once.
    static let changed = Notification.Name("IslandScreenChanged")
    /// The device description key that holds a screen's display number.
    private static let screenNumber = NSDeviceDescriptionKey("NSScreenNumber")

    /// The screen the island was last put on, which the side panel shares.
    private(set) static var current: NSScreen?

    static var choice: IslandScreen { IslandScreen(stored: UserDefaults.standard.string(forKey: key)) }

    static func choose(_ choice: IslandScreen) {
        UserDefaults.standard.set(choice.stored, forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }

    /// The screen the island goes on now; `open` keeps it where it is while it shows something.
    static func host(open: Bool) -> NSScreen? {
        let screens = NSScreen.screens
        let mouse = NSEvent.mouseLocation
        let facts = screens.map { ScreenFacts(id: id(of: $0), hasNotch: $0.safeAreaInsets.top > 0, holdsPointer: holds(mouse, $0)) }
        let staying = open ? current.flatMap(id(of:)) : nil
        let chosen = islandScreenIndex(choice, among: facts, stayingOn: staying).map { screens[$0] }
        current = chosen
        return chosen
    }

    /// Whether the pointer is on this screen, its edges counted, since the pointer at the very top is still on it.
    static func holds(_ point: NSPoint, _ screen: NSScreen) -> Bool {
        let frame = screen.frame
        return point.x >= frame.minX && point.x <= frame.maxX && point.y >= frame.minY && point.y <= frame.maxY
    }

    /// The display's UUID, which stays the same across reboots while its number does not.
    static func id(of screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[screenNumber] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}
