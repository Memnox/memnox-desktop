import Foundation

/// What a press on the Your apps screen was for, so a note that it did not work can say which.
public enum YourAppAct: Equatable, Sendable {
    case connect
    case disconnect
    /// Making one agent the one the voice answers through.
    case voice
    /// The Memnox Cloud sign in that connecting waits on.
    case cloudSignIn
}

/// Something that did not work on the Your apps screen, held on the card it came from where it came from one, so the
/// person reads it beside the app rather than in a banner over every app.
public struct YourAppNote: Equatable, Sendable {
    /// The app the note belongs to, nil for one about the page as a whole.
    public let toolkit: String?
    public let title: String
    public let words: String

    public init(toolkit: String?, title: String, words: String) {
        self.toolkit = toolkit
        self.title = title
        self.words = words
    }

    /// The note for a press that did not work, in the daemon's own words where it gave any and a plain line where not.
    public static func failed(_ act: YourAppAct, toolkit: String?, said: String?) -> YourAppNote {
        let name = toolkit.map(ToolkitName.of) ?? "the app"
        let title: String
        let fallback: String
        switch act {
        case .connect:
            title = "Could not connect \(name)"
            fallback = "Nothing was connected. Try again in a moment."
        case .disconnect:
            title = "Could not disconnect \(name)"
            fallback = "It is still connected. Try again in a moment."
        case .voice:
            title = "Could not change the voice's agent"
            fallback = "The voice answers through the same agent as before."
        case .cloudSignIn:
            title = "Not signed in to Memnox Cloud"
            fallback = YourApps.signInStopped
        }
        return YourAppNote(toolkit: toolkit, title: title, words: sentence(said) ?? fallback)
    }

    /// The daemon's words as one clean sentence: no stray space or line break, and a full stop where it left one off.
    static func sentence(_ said: String?) -> String? {
        guard let said else { return nil }
        let words = said.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        guard let last = words.last else { return nil }
        return sentenceEnds.contains(last) ? words : words + "."
    }

    private static let sentenceEnds: Set<Character> = [".", "!", "?"]
}

/// What a press of Connect does, read from the list the screen already holds, so a second press on an app that works
/// is no failure: the daemon refuses it as a slip, and the person meant only to see it connected.
public enum YourAppPress {
    /// True where the press opens a sign in: always to use another account, else only for an app not working yet.
    public static func opensSignIn(_ toolkit: String, again: Bool, connections: [ToolConnection]) -> Bool {
        again || !isSettled(toolkit, in: connections)
    }

    /// True where the list shows the app working or reached on this Mac itself, so there is nothing left to connect.
    public static func isSettled(_ toolkit: String, in connections: [ToolConnection]) -> Bool {
        let slug = toolkit.lowercased()
        return connections.contains { $0.toolkit.lowercased() == slug && ($0.connected || $0.isLocal) }
    }

    /// The quiet second button on a working app: another sign in, which the daemon opens when asked again, so the
    /// tool runs as the account signed in last.
    public static let anotherAccountButton = "Use another account"
}

/// What the disconnect dialog says, the console's words made true for this Mac: the cloud stops reading the app, the
/// person's agents stop working in it as them, and what was already learned from it stays here.
public enum YourAppDisconnect {
    public static func title(_ name: String) -> String { "Disconnect \(name)?" }

    public static func message(_ name: String) -> String { "Memnox stops reading from \(name) straight away." }

    public static func detail(_ name: String) -> String {
        "Your agents stop working in \(name) as you until you connect it again. What Memnox already learned from it stays on this Mac."
    }

    public static let confirm = "Disconnect"
}
