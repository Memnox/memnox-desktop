import Foundation

/// What puts a session in front of the person: its own window, or a card to read along with.
public protocol Presenter: AnyObject {
    /// Brings the session's window forward, and says whether it could.
    func open(_ host: DisplayHost?) async -> Bool
    /// A live window on the session, kept up to date while it is open, with a way to its own window.
    func live(session: String, host: DisplayHost?) async
    /// The session's own terminal tab or editor conversation, brought forward.
    /// Says whether it came forward, so the voice never calls a window open that never appeared.
    func focus(session: String, host: DisplayHost?) async -> Typed
    func card(_ card: SummaryCard) async
    /// Types an instruction into the agent's terminal prompt a key at a time and sends it; the request
    /// is what an editor's extension reads the words from, since its link may carry none.
    func type(_ text: String, into host: DisplayHost?, request: String) async -> Typed
    /// Brings the conversation forward in its editor, types the instruction into its message box and sends it.
    func prefill(_ text: String, session: String, host: DisplayHost?) async -> Typed
    /// Opens a new terminal tab in the folder and types the line that starts an agent there.
    func launch(_ command: String, in folder: String?) async -> Typed
    /// The same line in a new terminal inside the editor at `editor`, opened on the folder, where the
    /// editor's Memnox extension types it from the request; a terminal tab when no editor is named.
    func launch(_ command: String, in folder: String?, editor: String?, request: String) async -> Typed
    /// Opens a window of another terminal app, such as Ghostty, on the folder and types the line that starts the agent.
    func launch(_ command: String, in folder: String?, terminalApp: String) async -> Typed
    /// Opens the editor on the folder and sends the task as a new conversation in its Claude Code panel.
    func startInPanel(_ task: String, in folder: String?, editor: String?) async -> Typed
    /// Opens an agent's own desktop app: the app first when its path is given, then each of its links
    /// in order, then types the words into its message box and sends them, where there are words.
    func openApp(_ start: AppStart) async -> Typed
    /// A card that turns a page per file while the voice walks through the change.
    func walk(_ walk: WalkCard) async
    /// The whole screen: every agent on this Mac, with its logo and what it reaches.
    func scan(_ agents: [AgentNode], title: String) async
    /// A trace as a waterfall card: what ran, inside what, for how long, and what failed.
    func trace(_ trace: TraceData, title: String) async
    /// Every session as its own card, together; the app reads the sessions itself.
    func board(title: String) async
    /// Closes the live window on the session and its own terminal tab, and says whether the tab went;
    /// the request is what an editor's extension checks its close link against.
    func close(session: String, host: DisplayHost?, request: String) async -> Typed
    /// Presses Escape in the session's own terminal, as the person would to stop it, and says whether it went in;
    /// the request is what an editor's extension checks its interrupt link against.
    func interrupt(session: String, host: DisplayHost?, request: String) async -> Typed
    /// Presses the keys in the session's own terminal tab and nowhere else, answering what its agent asks there;
    /// the request is what an editor's extension reads the keys from.
    func press(_ keys: [TerminalPress], session: String, host: DisplayHost?, request: String) async -> Typed
    /// Every card, live window, board and scan off the screen; no session is touched.
    func dismissAll() async
    /// A folder opened in Finder, the editor or a new terminal tab, and whether it opened.
    func openFolder(_ path: String, in opener: FolderOpener) async -> Bool
    /// A web page opened in the person's own browser, and whether it opened.
    func openLink(_ url: URL) async -> Bool
    /// The window in front, or the named app's, captured with its controls; nil when nothing could be seen.
    func look(app: String?) async -> Sight?
    /// The words in a session's own terminal tab, read by the terminal's scripting so no Screen Recording is
    /// needed and no other window is read in its place; nil when it is not in a tab that can be read.
    func readTab(of host: DisplayHost) async -> Sight?
    /// The window an action is aimed at, captured just before or just after it, with the words read off it;
    /// nil when it cannot be seen or is one never captured, such as a password manager.
    func evidence(of host: DisplayHost?, request: String, at moment: WitnessMoment) async -> Witness?
}

extension Presenter {
    public func close(session: String, host: DisplayHost?, request: String) async -> Typed {
        Typed(.failed, "this Mac cannot close a session's tab")
    }

    public func interrupt(session: String, host: DisplayHost?, request: String) async -> Typed {
        Typed(.failed, "this Mac cannot press keys in a session's terminal")
    }

    public func press(_ keys: [TerminalPress], session: String, host: DisplayHost?, request: String) async -> Typed {
        Typed(.failed, "this Mac cannot press keys in a session's terminal")
    }

    public func dismissAll() async {}

    public func launch(_ command: String, in folder: String?, terminalApp: String) async -> Typed {
        Typed(.failed, "this Mac cannot open another terminal app")
    }

    public func startInPanel(_ task: String, in folder: String?, editor: String?) async -> Typed {
        Typed(.failed, "this Mac cannot start a conversation in an editor's panel")
    }

    public func launch(_ command: String, in folder: String?, editor: String?, request: String) async -> Typed {
        guard editor == nil else { return Typed(.failed, "this Mac cannot start a session inside an editor") }
        return await launch(command, in: folder)
    }

    public func openFolder(_ path: String, in opener: FolderOpener) async -> Bool { false }

    public func openLink(_ url: URL) async -> Bool { false }

    public func look(app: String?) async -> Sight? { nil }

    public func readTab(of host: DisplayHost) async -> Sight? { nil }

    public func evidence(of host: DisplayHost?, request: String, at moment: WitnessMoment) async -> Witness? { nil }

    public func openApp(_ start: AppStart) async -> Typed { Typed(.failed, "this Mac cannot open an agent's app") }
}

/// An agent's desktop app to open on a repository, as the runtime worked it out from the app's own links.
public struct AppStart: Equatable, Sendable {
    /// As a person names the app, which the comet flies toward.
    public let name: String
    public let appPath: String?
    public let folder: String?
    public let links: [String]
    public let env: [String: String]
    /// Typed into the app's message box once it is open, and sent, so the person watches it go in.
    public let typed: String?
    /// A new chat started first, rather than typing into the one open.
    public let newChat: Bool
    /// The words the app's own prompt link left in its chat sent with Return, once they are read there.
    public let sendPrefilled: Bool

    public init(name: String, appPath: String?, folder: String?, links: [String], env: [String: String], typed: String?,
                newChat: Bool = false, sendPrefilled: Bool = false) {
        self.newChat = newChat
        self.sendPrefilled = sendPrefilled
        self.name = name
        self.appPath = appPath
        self.folder = folder
        self.links = links
        self.env = env
        self.typed = typed
    }

    /// The query item a prompt link carries its words in, as Cursor's does.
    private static let promptTextItem = "text"

    /// The words the last prompt link carried, read from the link itself so the chat is checked against exactly what was put there.
    public var prefilledWords: String? {
        links.reversed().lazy
            .compactMap { URLComponents(string: $0)?.queryItems?.first { $0.name == Self.promptTextItem }?.value }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
