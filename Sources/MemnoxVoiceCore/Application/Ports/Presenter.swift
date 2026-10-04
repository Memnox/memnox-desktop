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
    /// Every card, live window, board and scan off the screen; no session is touched.
    func dismissAll() async
    /// A folder opened in Finder, the editor or a new terminal tab, and whether it opened.
    func openFolder(_ path: String, in opener: FolderOpener) async -> Bool
}

extension Presenter {
    public func close(session: String, host: DisplayHost?, request: String) async -> Typed {
        Typed(.failed, "this Mac cannot close a session's tab")
    }

    public func dismissAll() async {}

    public func openFolder(_ path: String, in opener: FolderOpener) async -> Bool { false }
}
