import Foundation

/// Which display the island lives on, so a MacBook closed on a monitor, or a desk with two, puts it where the
/// person looks. Remembered as its `stored` value.
public enum IslandScreen: Equatable, Sendable {
    /// The built in screen with the notch, or the one with the menu bar when no screen has a notch.
    case notch
    /// Whichever screen holds the pointer, moving only while the island is closed so it never jumps mid answer.
    case pointer
    /// One display by its UUID, which stays the same across reboots and rearranged screens.
    case display(String)

    private static let notchValue = "notch"
    private static let pointerValue = "pointer"
    private static let displayPrefix = "display:"

    /// The saved choice, or the notch when nothing or something unknown was saved.
    public init(stored: String?) {
        switch stored {
        case Self.pointerValue?: self = .pointer
        case let value? where value.hasPrefix(Self.displayPrefix) && value.count > Self.displayPrefix.count:
            self = .display(String(value.dropFirst(Self.displayPrefix.count)))
        default: self = .notch
        }
    }

    public var stored: String {
        switch self {
        case .notch: Self.notchValue
        case .pointer: Self.pointerValue
        case .display(let id): Self.displayPrefix + id
        }
    }
}

/// What choosing a screen needs to know about one, given in the order the Mac lists them, its menu bar screen first.
public struct ScreenFacts: Equatable, Sendable {
    /// The display's UUID, nil for one that gives none.
    public let id: String?
    public let hasNotch: Bool
    public let holdsPointer: Bool

    public init(id: String?, hasNotch: Bool, holdsPointer: Bool) {
        self.id = id
        self.hasNotch = hasNotch
        self.holdsPointer = holdsPointer
    }
}

/// Which of `screens` the island goes on. `stayingOn` is the screen it is on while open, so following the pointer
/// waits until it closes. A chosen display that is gone falls back to the notch, and nil means there is no screen.
public func islandScreenIndex(_ choice: IslandScreen, among screens: [ScreenFacts], stayingOn: String? = nil) -> Int? {
    guard !screens.isEmpty else { return nil }
    let notch = screens.firstIndex { $0.hasNotch } ?? screens.startIndex
    switch choice {
    case .notch:
        return notch
    case .pointer:
        if let stayingOn, let here = screens.firstIndex(where: { $0.id == stayingOn }) { return here }
        return screens.firstIndex { $0.holdsPointer } ?? notch
    case .display(let id):
        return screens.firstIndex { $0.id == id } ?? notch
    }
}
