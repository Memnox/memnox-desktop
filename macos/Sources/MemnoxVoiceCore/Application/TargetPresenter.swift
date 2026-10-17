import Foundation

/// The presenter while a server may be the target: cards, boards and live views of its sessions still show,
/// and nothing that types, opens, focuses or closes is tried, since a server's sessions have no window or tty on this Mac.
public final class TargetPresenter: Presenter {
    private let inner: Presenter
    private let remote: () -> Bool

    public init(_ inner: Presenter, remote: @escaping () -> Bool) {
        self.inner = inner
        self.remote = remote
    }

    /// Said for every act refused, so the voice never calls a window open that never appeared.
    public static let elsewhere = "that session runs on a server, so this Mac only shows it"

    private var refused: Typed { Typed(.failed, Self.elsewhere) }

    public func open(_ host: DisplayHost?) async -> Bool {
        remote() ? false : await inner.open(host)
    }

    public func live(session: String, host: DisplayHost?) async {
        await inner.live(session: session, host: remote() ? nil : host)
    }

    public func focus(session: String, host: DisplayHost?) async -> Typed {
        remote() ? refused : await inner.focus(session: session, host: host)
    }

    public func card(_ card: SummaryCard) async {
        await inner.card(card)
    }

    public func type(_ text: String, into host: DisplayHost?, request: String) async -> Typed {
        remote() ? refused : await inner.type(text, into: host, request: request)
    }

    public func prefill(_ text: String, session: String, host: DisplayHost?) async -> Typed {
        remote() ? refused : await inner.prefill(text, session: session, host: host)
    }

    public func launch(_ command: String, in folder: String?) async -> Typed {
        remote() ? refused : await inner.launch(command, in: folder)
    }

    public func launch(_ command: String, in folder: String?, editor: String?, request: String) async -> Typed {
        remote() ? refused : await inner.launch(command, in: folder, editor: editor, request: request)
    }

    public func launch(_ command: String, in folder: String?, terminalApp: String) async -> Typed {
        remote() ? refused : await inner.launch(command, in: folder, terminalApp: terminalApp)
    }

    public func startInPanel(_ task: String, in folder: String?, editor: String?) async -> Typed {
        remote() ? refused : await inner.startInPanel(task, in: folder, editor: editor)
    }

    public func openApp(_ start: AppStart) async -> Typed {
        remote() ? refused : await inner.openApp(start)
    }

    public func walk(_ walk: WalkCard) async {
        await inner.walk(walk)
    }

    public func scan(_ agents: [AgentNode], title: String) async {
        await inner.scan(agents, title: title)
    }

    public func trace(_ trace: TraceData, title: String) async {
        await inner.trace(trace, title: title)
    }

    public func board(title: String) async {
        await inner.board(title: title)
    }

    public func close(session: String, host: DisplayHost?, request: String) async -> Typed {
        remote() ? refused : await inner.close(session: session, host: host, request: request)
    }

    public func interrupt(session: String, host: DisplayHost?, request: String) async -> Typed {
        remote() ? refused : await inner.interrupt(session: session, host: host, request: request)
    }

    public func press(_ keys: [TerminalPress], session: String, host: DisplayHost?, request: String) async -> Typed {
        remote() ? refused : await inner.press(keys, session: session, host: host, request: request)
    }

    public func dismissAll() async {
        await inner.dismissAll()
    }

    public func openFolder(_ path: String, in opener: FolderOpener) async -> Bool {
        remote() ? false : await inner.openFolder(path, in: opener)
    }

    /// A web page is the same page from any machine, so it opens on this Mac whichever one is the target.
    public func openLink(_ url: URL) async -> Bool {
        await inner.openLink(url)
    }

    /// The screen in front is this Mac's, which says nothing about a server's session.
    public func look(app: String?) async -> Sight? {
        remote() ? nil : await inner.look(app: app)
    }

    /// A tab on this Mac, which says nothing about a server's session.
    public func readTab(of host: DisplayHost) async -> Sight? {
        remote() ? nil : await inner.readTab(of: host)
    }
}
