import AppKit
import MemnoxVoiceCore
import SwiftUI

/// Puts a session in front of the person: its own terminal tab or editor window, or a glass card
/// in the top left corner with the summary the voice is reading.
@MainActor
final class SessionPresenter: Presenter {
    private let card = CardPanel()
    private let wall = CardWall()
    let livePanel = LivePanel()
    private let flight = FlightPanel()
    private let switcher = SwitcherPanel()
    private let scanPanel = ScanPanel()
    /// The sessions lately, for the switcher to turn through; set by the app once the conversation exists.
    var sessions: (() async -> [SessionCard])?
    /// Where the orb is on screen, which is where a sent instruction flies from.
    var orbFrame: (() -> NSRect?)?

    init() {
        livePanel.openOwnWindow = { [weak self] session, host in _ = await self?.bringForward(session: session, host: host) }
    }

    /// Everything Memnox put on screen goes, and nothing else: no tab, no agent.
    func dismissAll() async {
        card.dismiss()
        wall.dismiss()
        livePanel.dismiss()
        scanPanel.dismiss()
    }

    /// Turns through the sessions to this one, then opens a live window on it.
    func live(session: String, host: DisplayHost?) async {
        await turnTo(session)
        await livePanel.present(session: session, host: host)
    }

    /// Turns through the sessions to this one, then brings its own tab or conversation forward.
    func focus(session: String, host: DisplayHost?) async -> Typed {
        await turnTo(session)
        return await bringForward(session: session, host: host)
    }

    /// The live window goes first, then the tab itself, found by its terminal device as focus finds it.
    func close(session: String, host: DisplayHost?, request: String) async -> Typed {
        livePanel.dismiss()
        let app = (host?.app ?? host?.appPath ?? "").lowercased()
        guard let tty = Self.device(host?.tty) else { return Typed(.failed, "it runs in no terminal Memnox knows, such as the Claude Code panel") }
        if !app.contains("iterm"), Self.editors.contains(where: app.contains) {
            // The editor's own terminal, closed by the Memnox extension against the request the runtime wrote.
            guard let link = Self.extensionLink(app: app, path: "/close", query: ["request": request, "tty": tty]) else {
                return Typed(.failed, "the Memnox extension is not in \(host?.app ?? "the editor"), so run memnox protect --vscode")
            }
            guard NSWorkspace.shared.open(link) else { return Typed(.failed, "the editor would not take the Memnox link") }
            return await Self.extensionDelivery(of: request)
        }
        if app.contains("iterm") {
            return Self.run(Self.iTermCloseScript(tty)) ? .landed : Typed(.failed, "no iTerm tab has its terminal")
        }
        if app.contains("terminal") {
            return Self.run(Self.terminalCloseScript(tty))
                ? .landed
                : Typed(.failed, "Terminal closes a whole window, and its window has other tabs")
        }
        return Typed(.failed, "it runs in \(host?.app ?? "an app") rather than iTerm or Terminal")
    }

    private func turnTo(_ session: String) async {
        guard let sessions else { return }
        await switcher.turn(to: session, among: await sessions())
    }

    /// The exact conversation in an editor through its Claude Code link, or the exact tab in a terminal.
    @discardableResult
    private func bringForward(session: String, host: DisplayHost?) async -> Typed {
        let app = (host?.app ?? host?.appPath ?? "").lowercased()
        let editor = ["code", "cursor", "windsurf"].contains(where: app.contains)
        // A session with a terminal runs in one of the editor's terminals, never in the extension panel.
        // Only the agent's own id opens its conversation; any other id makes the panel start a new one,
        // so without it the editor window is brought forward instead.
        if editor, host?.tty == nil, let conversation = host?.conversation,
           conversation.range(of: #"^[0-9a-fA-F-]{36}$"#, options: .regularExpression) != nil,
           let url = Self.conversationLink(app: app, session: conversation, prompt: nil),
           NSWorkspace.shared.open(url) {
            return .landed
        }
        if await open(host) { return .landed }
        diary.note("could not bring \(session) forward in \(app)")
        guard let host, host.app != nil || host.appPath != nil || host.cwd != nil else {
            return Typed(.failed, "where it runs was never noted, so there is no window or folder to bring up")
        }
        return Typed(.failed, "\(host.app ?? "its app") would not bring its window forward")
    }

    /// The Claude Code extension's own link, which opens that one conversation, with a prompt in its box when given.
    private static func conversationLink(app: String, session: String, prompt: String?) -> URL? {
        var link = URLComponents()
        link.scheme = app.contains("cursor") ? "cursor" : app.contains("windsurf") ? "windsurf" : "vscode"
        link.host = "anthropic.claude-code"
        link.path = "/open"
        link.queryItems = [URLQueryItem(name: "session", value: session)]
            + (prompt.map { [URLQueryItem(name: "prompt", value: $0)] } ?? [])
        return link.url
    }

    func open(_ host: DisplayHost?) async -> Bool {
        guard let host else { return false }
        let app = (host.app ?? host.appPath ?? "").lowercased()
        if let tty = Self.device(host.tty) {
            if app.contains("iterm"), Self.run(Self.iTermScript(tty)) { return true }
            if app.contains("terminal"), Self.run(Self.terminalScript(tty)) { return true }
        }
        let url = host.appPath.map { URL(fileURLWithPath: $0) }
        if let cwd = host.cwd, let url, Self.editors.contains(where: app.contains) {
            // An editor opened on the session's folder brings forward the window already on it.
            let opened = await Self.open([URL(fileURLWithPath: cwd)], with: url)
            // Then the terminal inside it, which only the Memnox extension can choose among several.
            if opened, let tty = host.tty, let link = Self.extensionLink(app: app, path: "/terminal", query: ["tty": tty]) {
                try? await Task.sleep(nanoseconds: 300_000_000)
                NSWorkspace.shared.open(link)
            }
            return opened
        }
        if let url { return await Self.open([], with: url) }
        // Only the folder is known, so it opens in whichever editor is installed, which brings its window forward.
        guard let cwd = host.cwd, let editor = Self.installedEditor() else { return false }
        return await Self.open([URL(fileURLWithPath: cwd)], with: editor)
    }

    /// A link to the Memnox extension, only where that editor has it installed, since a link
    /// nothing handles makes the editor offer to search its marketplace.
    private static func extensionLink(app: String, path: String, query: [String: String]) -> URL? {
        guard let tty = query["tty"], device(tty) != nil else { return nil }
        let (scheme, folder) = app.contains("cursor") ? ("cursor", ".cursor")
            : app.contains("windsurf") ? ("windsurf", ".windsurf")
            : ("vscode", ".vscode")
        let extensions = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("\(folder)/extensions")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: extensions.path)) ?? []
        guard names.contains(where: { $0.hasPrefix("memnox.memnox-terminals-") }) else { return nil }
        var link = URLComponents()
        link.scheme = scheme
        link.host = "memnox.memnox-terminals"
        link.path = path
        link.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return link.url
    }

    /// VS Code first, since Claude Code most often runs inside it, then Cursor.
    private static func installedEditor() -> URL? {
        ["com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf"]
            .lazy
            .compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .first
    }

    func card(_ summary: SummaryCard) async {
        let session = summary.sessionId
        card.present(
            summary,
            open: session.map { id in
                { [weak self] in Task { await self?.bringForward(session: id, host: summary.host) } }
            },
            watch: session.map { id in
                { [weak self] in Task { await self?.livePanel.present(session: id, host: summary.host) } }
            }
        )
    }

    func trace(_ trace: TraceData, title: String) async {
        guard !trace.rows.isEmpty else { return }
        card.present(trace, title: title)
    }

    /// Every session as a card of its own, all on screen at once; the title is the voice's to say.
    func board(title: String) async {
        guard let sessions else { return }
        let cards = await sessions()
        guard !cards.isEmpty else { return }
        wall.present(
            cards,
            fetch: { [weak self] session in await self?.livePanel.fetch?(session) },
            watch: { [weak self] picked in
                Task { await self?.livePanel.present(session: picked.sessionId, host: picked.host) }
            },
            open: { [weak self] picked in
                Task { await self?.bringForward(session: picked.sessionId, host: picked.host) }
            }
        )
    }

    func scan(_ agents: [AgentNode], title: String) async {
        guard !agents.isEmpty else { return }
        scanPanel.present(agents, title: title)
    }

    func walk(_ walk: WalkCard) async {
        guard !walk.pages.isEmpty else { return }
        card.present(walk, open: walk.sessionId.map { id in
            { [weak self] in Task { await self?.bringForward(session: id, host: walk.host) } }
        })
    }

    /// Opens a new tab in the repository and types the line that starts the agent, a key at a time,
    /// so the person watches a session begin. The runtime built the line and quoted the task in it.
    func launch(_ command: String, in folder: String?) async -> Typed {
        guard let folder, FileManager.default.fileExists(atPath: folder) else {
            return Typed(.failed, "the repository folder is not there")
        }
        let iTerm = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") != nil
        let name = iTerm ? "iTerm" : "Terminal"
        await launch(toward: name)
        // Only a bare tab: the line typed into it goes into the repository itself, since a cd sent
        // on its own here reached the shell after the typed line and started the agent in the home folder.
        guard Self.run(iTerm ? Self.iTermNewTab() : Self.terminalNewTab()) else {
            return Typed(.failed, "a new \(name) tab would not open")
        }
        // The new shell needs a moment before it reads keys, or the first few are lost.
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        guard PromptTyping.allowed(),
              let front = NSWorkspace.shared.frontmostApplication,
              (front.localizedName ?? "").lowercased().contains(name.lowercased())
        else {
            // Without leave to press keys, the terminal's own scripting puts the line in all at once.
            let line = Self.quoted(command)
            return Self.run(iTerm ? Self.iTermWriteFront(line) : Self.terminalWriteFront(line))
                ? .landed
                : Typed(.failed, "the line could not be typed into the new tab")
        }
        return await PromptTyping.type(command, into: front)
    }

    /// Brings the agent's own tab forward and types the instruction into its prompt a key at a time,
    /// then sends it. The runtime checked the tab's foreground program is the agent, and the tab is
    /// checked again to be the one in front, so the words never land in a bare shell or another tab.
    func type(_ text: String, into host: DisplayHost?, request: String) async -> Typed {
        guard let host, let tty = Self.device(host.tty) else { return Typed(.failed, "its terminal tab is not known") }
        let app = (host.app ?? host.appPath ?? "").lowercased()
        let iTerm = app.contains("iterm")
        if !iTerm, Self.editors.contains(where: app.contains) {
            return await typeInEditorTerminal(request: request, tty: tty, host: host, app: app)
        }
        guard iTerm || app.contains("terminal") else { return Typed(.failed, "it does not run in iTerm, Terminal or an editor") }
        await launch(toward: host.app ?? app)
        guard PromptTyping.allowed() else {
            // Without leave to press keys, the terminal's own scripting puts the words in all at once.
            let words = Self.quoted(text)
            let typed = Self.run(iTerm ? Self.iTermTypeScript(tty, words) : Self.terminalTypeScript(tty, words))
            return typed ? .landed : Typed(.failed, "no \(iTerm ? "iTerm" : "Terminal") tab has its terminal")
        }
        guard Self.run(iTerm ? Self.iTermScript(tty) : Self.terminalScript(tty)) else {
            return Typed(.failed, "no \(iTerm ? "iTerm" : "Terminal") tab has its terminal")
        }
        // A moment for the tab to come forward before checking it is the one in front.
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard Self.run(iTerm ? Self.iTermInFront(tty) : Self.terminalInFront(tty)),
              let front = NSWorkspace.shared.frontmostApplication,
              (front.localizedName ?? "").lowercased().contains(iTerm ? "iterm" : "terminal")
        else {
            PromptTyping.leaveOnClipboard(text)
            return Typed(.clipboard, "its tab did not come to the front")
        }
        return await PromptTyping.type(text, into: front)
    }

    /// An editor's integrated terminal, typed into by the Memnox extension there, which reads the words
    /// from the request itself and needs no leave to press keys. The editor comes forward first, so the
    /// link reaches the window holding the session and the person watches the words go in.
    private func typeInEditorTerminal(request: String, tty: String, host: DisplayHost, app: String) async -> Typed {
        guard let link = Self.extensionLink(app: app, path: "/type", query: ["request": request, "tty": tty]) else {
            return Typed(.failed, "the Memnox extension is not in \(host.app ?? "the editor"), so run memnox protect --vscode")
        }
        await launch(toward: host.app ?? app)
        _ = await open(host)
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard NSWorkspace.shared.open(link) else { return Typed(.failed, "the editor would not take the Memnox link") }
        return await Self.extensionDelivery(of: request)
    }

    /// What the extension wrote on the request once it typed it, read from the runtime's own folder.
    private static func extensionDelivery(of request: String) async -> Typed {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".memnox/displays/\(request).json")
        // Long enough for a few sentences a key at a time, short of the runtime's own wait.
        for _ in 0..<80 {
            if let data = try? Data(contentsOf: file),
               let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let delivered = record["delivered"] as? [String: Any],
               let outcome = delivered["outcome"] as? String {
                let reason = delivered["reason"] as? String
                return outcome == Delivery.typed.rawValue ? .landed : Typed(.failed, reason ?? "the extension could not type it")
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return Typed(.failed, "the Memnox extension did not answer, so reload the editor window or run memnox protect --vscode")
    }

    /// Brings the conversation forward and types the words into its message box a key at a time.
    /// The link alone cannot carry them, since the extension refuses a prompt for a conversation already open.
    func prefill(_ text: String, session: String, host: DisplayHost?) async -> Typed {
        let app = (host?.app ?? host?.appPath ?? "").lowercased()
        await launch(toward: host?.app ?? app)
        // Opened by its own id only, since any other id starts a new conversation and the words would land there.
        guard let conversation = host?.conversation else {
            PromptTyping.leaveOnClipboard(text)
            return Typed(.clipboard, "which conversation it is in the editor is not known yet")
        }
        guard let url = Self.conversationLink(app: app, session: conversation, prompt: nil), NSWorkspace.shared.open(url) else {
            PromptTyping.leaveOnClipboard(text)
            return Typed(.clipboard, "its conversation could not be opened")
        }
        let typed = await PromptTyping.typeIntoEditor(text, inAppAt: host?.appPath)
        if typed.outcome != .typed { PromptTyping.leaveOnClipboard(text) }
        return typed
    }

    /// The comet leaves the orb, and the words land as it arrives rather than before it.
    private func launch(toward app: String) async {
        let start = orbFrame?().map { NSPoint(x: $0.midX, y: $0.midY) }
            ?? NSScreen.main.map { NSPoint(x: $0.frame.midX, y: $0.frame.minY + 80) }
        guard let start else { return }
        flight.fly(from: start, toApp: app)
        try? await Task.sleep(nanoseconds: UInt64(FlightPanel.duration * 0.85 * 1_000_000_000))
    }

    /// The instruction as an AppleScript string: one line, with its quotes and backslashes escaped.
    private static func quoted(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Typed without a newline and then sent on its own, since an agent reads text and Return arriving together as a paste.
    private static func iTermTypeScript(_ tty: String, _ words: String) -> String {
        """
        tell application "iTerm"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                            tell s to write text "\(words)" newline no
                            delay 0.3
                            tell s to write text ""
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """
    }

    private static func terminalTypeScript(_ tty: String, _ words: String) -> String {
        """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        do script "\(words)" in t
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """
    }

    /// A new tab in the front window, or a first window.
    private static func iTermNewTab() -> String {
        """
        tell application "iTerm"
            activate
            if (count of windows) is 0 then
                create window with default profile
            else
                tell current window to create tab with default profile
            end if
            return true
        end tell
        """
    }

    private static func terminalNewTab() -> String {
        """
        tell application "Terminal"
            activate
            do script ""
            return true
        end tell
        """
    }

    private static func iTermWriteFront(_ line: String) -> String {
        """
        tell application "iTerm"
            tell current session of current window to write text "\(line)"
            return true
        end tell
        """
    }

    private static func terminalWriteFront(_ line: String) -> String {
        """
        tell application "Terminal"
            do script "\(line)" in selected tab of front window
            return true
        end tell
        """
    }

    /// True only when the tab in front of iTerm's front window is the agent's.
    private static func iTermInFront(_ tty: String) -> String {
        """
        tell application "iTerm"
            return (tty of current session of current window) is "\(tty)"
        end tell
        """
    }

    private static func terminalInFront(_ tty: String) -> String {
        """
        tell application "Terminal"
            return (tty of selected tab of front window) is "\(tty)"
        end tell
        """
    }

    /// Editors that bring forward the window on a folder when asked to open it.
    private static let editors = ["code", "cursor", "windsurf", "zed"]

    /// The terminal device as AppleScript names it, and only a real one, since it goes into a script.
    private static func device(_ tty: String?) -> String? {
        guard let tty else { return nil }
        let name = tty.hasPrefix("/dev/") ? String(tty.dropFirst(5)) : tty
        guard name.range(of: #"^ttys?[0-9]+$"#, options: .regularExpression) != nil else { return nil }
        return "/dev/\(name)"
    }

    private static func iTermScript(_ tty: String) -> String {
        """
        tell application "iTerm"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                            select w
                            select t
                            select s
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """
    }

    /// Closing the session closes its tab when it is the only one there, which is how iTerm closes a tab.
    private static func iTermCloseScript(_ tty: String) -> String {
        """
        tell application "iTerm"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                            close s
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """
    }

    /// Terminal can only close a window, so it does so only when the agent's tab is the window's one tab.
    private static func terminalCloseScript(_ tty: String) -> String {
        """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        if (count of tabs of w) is 1 then
                            close w
                            return true
                        end if
                        return false
                    end if
                end repeat
            end repeat
        end tell
        return false
        """
    }

    private static func terminalScript(_ tty: String) -> String {
        """
        tell application "Terminal"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set selected of t to true
                        set index of w to 1
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """
    }

    /// True only when the script ran and found the tab; macOS asks once before Memnox may drive an app.
    private static func run(_ source: String) -> Bool {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { diary.note("could not drive the terminal: \(error)") }
        return result?.booleanValue == true
    }

    private static func open(_ items: [URL], with app: URL) async -> Bool {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            if items.isEmpty {
                _ = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
            } else {
                _ = try await NSWorkspace.shared.open(items, withApplicationAt: app, configuration: configuration)
            }
            return true
        } catch {
            diary.note("could not open \(app.lastPathComponent): \(error)")
            return false
        }
    }
}

/// A hosting view that takes the first click, since a panel that never activates Memnox would
/// otherwise spend that click becoming key and the button under it would do nothing.
final class FirstClickHosting<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Every session as a card of its own, slid onto the screen one after another and laid out in
/// columns from the top left, so all of them can be read at once and each closed on its own.
@MainActor
final class CardWall {
    private var panels: [CardPanel] = []
    /// As many as fit on a laptop screen and can each still be read.
    static let most = 8
    /// A beat between cards, so they slide in one after another rather than all landing at once.
    private static let staggerNanoseconds: UInt64 = 90_000_000
    private static let gap: CGFloat = 16
    private static let refreshNanoseconds: UInt64 = 2_000_000_000
    private var showing: Task<Void, Never>?
    /// Where each column's lowest card ends, so the next card goes under the shortest column.
    private var bottoms: [CGFloat] = []

    func present(
        _ cards: [SessionCard],
        fetch: @escaping (String) async -> SessionView?,
        watch: @escaping (SessionCard) -> Void,
        open: @escaping (SessionCard) -> Void
    ) {
        dismiss()
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let columns = max(1, Int((screen.width - Self.gap) / (CardPanel.width + Self.gap)))
        bottoms = Array(repeating: screen.maxY - 20, count: columns)
        let shown = Array(cards.prefix(Self.most))
        let panels = shown.map { _ in CardPanel() }
        self.panels = panels
        let models = shown.map { _ in LiveModel() }
        showing = Task { [weak self] in
            // Read before any card is drawn, so each one is sized for what it will show.
            for (card, model) in zip(shown, models) { model.view = await fetch(card.sessionId) }
            for (card, (panel, model)) in zip(shown, zip(panels, models)) {
                guard let self, !Task.isCancelled else { return }
                panel.present(
                    SessionPopupView(
                        card: card,
                        model: model,
                        close: { panel.dismiss() },
                        watch: { [weak self] in watch(card); self?.dismiss() },
                        open: card.host == nil ? nil : { [weak self] in open(card); self?.dismiss() },
                        hovering: { panel.hovering($0) }
                    ),
                    place: { size, margin in self.place(size, margin: margin, on: screen) }
                )
                try? await Task.sleep(nanoseconds: Self.staggerNanoseconds)
            }
            // Kept current while the cards are up, the way the live window is.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.refreshNanoseconds)
                for (card, model) in zip(shown, models) {
                    guard !Task.isCancelled, let fresh = await fetch(card.sessionId) else { continue }
                    withAnimation(.easeOut(duration: 0.3)) { model.view = fresh }
                }
            }
        }
    }

    /// The shortest column takes the next card, so the wall stays even.
    private func place(_ size: NSSize, margin: CGFloat, on screen: NSRect) -> NSPoint {
        let column = bottoms.indices.min { bottoms[$0] > bottoms[$1] } ?? 0
        let x = screen.minX + 20 + CGFloat(column) * (CardPanel.width + Self.gap)
        let top = bottoms[column]
        bottoms[column] = top - (size.height - 2 * margin) - Self.gap
        return NSPoint(x: x - margin, y: top - size.height + margin)
    }

    func dismiss() {
        showing?.cancel()
        panels.forEach { $0.dismiss() }
        panels = []
    }
}

/// One session on its own card, showing what it is doing the way the live window does: what it
/// is on this moment, the last words of its conversation, its latest steps and what it changed,
/// kept short so several fit on a screen and refreshed while it is up.
struct SessionPopupView: View {
    let card: SessionCard
    @ObservedObject var model: LiveModel
    let close: () -> Void
    let watch: () -> Void
    let open: (() -> Void)?
    let hovering: (Bool) -> Void
    @StateObject private var entrance = CardEntrance()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let view = model.view {
                LiveHeader(view: view, close: close)
                LiveNow(view: view)
                let talk = Array((view.conversation ?? []).suffix(2))
                if !talk.isEmpty {
                    LiveSection(title: "Conversation") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(talk.enumerated()), id: \.offset) { _, line in
                                ConversationRow(line: line, typing: false).lineLimit(3)
                            }
                        }
                    }
                }
                if !view.steps.isEmpty { LiveSteps(steps: view.steps, most: 3) }
                if !view.files.isEmpty {
                    LiveSection(title: "Changed") {
                        FileList(files: Array(view.files.prefix(3)), counting: entrance.shown)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(card.agentName)
                        .font(Memnox.display(22))
                        .foregroundStyle(Memnox.Palette.foreground)
                    Spacer()
                    CloseButton(action: close)
                }
                Text(card.task ?? "Nothing recorded for this session yet")
                    .font(Memnox.sans(14))
                    .foregroundStyle(Memnox.Palette.foreground.opacity(0.75))
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                Spacer()
                CardButton(title: "Watch live", icon: "play.circle", primary: open == nil, action: watch)
                if let open {
                    CardButton(title: card.host?.app.map { "Open in \($0)" } ?? "Open its window", icon: "arrow.up.forward.app", primary: true, action: open)
                }
            }
        }
        .modifier(CardFace(entrance: entrance, hovering: hovering))
    }
}

/// The card: glass in the top left corner, a heading and the summary, gone on a click or after a while.
@MainActor
final class CardPanel {
    private let panel: KeyablePanel
    private var hide: Task<Void, Never>?
    /// Long enough to read a four sentence summary and glance at the code after the voice has finished it.
    private static let showFor: UInt64 = 60
    /// Once the pointer has been on it and left, the person has read it, so it goes sooner.
    private static let afterLeaving: UInt64 = 15
    static let width: CGFloat = 440

    init() {
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 160),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The card draws its own soft shadow; the window's would trace that shadow's edge as a rough outline.
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
    }

    func present(_ summary: SummaryCard, open: (() -> Void)? = nil, watch: (() -> Void)? = nil) {
        let card = CardView(
            summary: summary,
            close: { [weak self] in self?.dismiss() },
            open: open.map { go in { [weak self] in go(); self?.dismiss() } },
            watch: watch.map { go in { [weak self] in go(); self?.dismiss() } },
            hovering: { [weak self] inside in self?.hovering(inside) }
        )
        host(card, for: Self.showFor)
    }

    /// A trace as a waterfall in the same corner, up long enough to read every step.
    func present(_ trace: TraceData, title: String) {
        let view = TraceView(
            trace: trace,
            title: title,
            close: { [weak self] in self?.dismiss() },
            hovering: { [weak self] inside in self?.hovering(inside) }
        )
        host(view, for: Self.showFor)
    }

    /// Any card, put where `place` says from its size and margin, which is how a wall lays several out.
    func present<Card: View>(_ card: Card, place: @escaping (NSSize, CGFloat) -> NSPoint) {
        host(card, for: Self.showFor, place: place)
    }

    /// The walk through in the same corner, up for as long as the voice takes to say it and a little after.
    func present(_ walk: WalkCard, open: (() -> Void)? = nil) {
        let view = WalkView(
            walk: walk,
            close: { [weak self] in self?.dismiss() },
            open: open.map { go in { [weak self] in go(); self?.dismiss() } },
            hovering: { [weak self] inside in self?.hovering(inside) }
        )
        let speaking = walk.pages.reduce(0) { $0 + WalkView.seconds(for: $1) }
        host(view, for: UInt64(speaking) + Self.afterLeaving)
    }

    private func host<Card: View>(_ card: Card, for seconds: UInt64, place: ((NSSize, CGFloat) -> NSPoint)? = nil) {
        // Room around the card, since standing at an angle carries its edges past its own frame.
        let margin: CGFloat = 40
        let view = FirstClickHosting(rootView: card.padding(margin))
        let size = view.fittingSize
        panel.contentView = view
        if let place {
            panel.setFrame(NSRect(origin: place(size, margin), size: size), display: true)
        } else if let screen = NSScreen.main?.visibleFrame {
            panel.setFrame(
                NSRect(x: screen.minX + 20 - margin, y: screen.maxY - size.height - 20 + margin, width: size.width, height: size.height),
                display: true
            )
        }
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.25; panel.animator().alphaValue = 1 }
        }
        hideAfter(seconds)
    }

    /// Never goes while the pointer is on it, since that is somebody reading it or about to click.
    func hovering(_ inside: Bool) {
        if inside { hide?.cancel() } else { hideAfter(Self.afterLeaving) }
    }

    private func hideAfter(_ seconds: UInt64) {
        hide?.cancel()
        hide = Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        hide?.cancel()
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel.animator().alphaValue = 0 }) { [panel] in
            panel.orderOut(nil)
        }
    }
}

/// Whether the card has swung in yet, so it turns out of the screen rather than fading up flat.
@MainActor
final class CardEntrance: ObservableObject {
    @Published var shown = false
    /// The pointer is on it: it turns to face the person, so every button sits where it is drawn.
    @Published var facing = false
}

struct CardView: View {
    let summary: SummaryCard
    let close: () -> Void
    /// Goes straight to the session's own window, where it is known.
    let open: (() -> Void)?
    /// Opens the live window on the session, in the middle of the screen.
    let watch: (() -> Void)?
    let hovering: (Bool) -> Void
    @StateObject private var entrance = CardEntrance()

    private var openLabel: String {
        guard let app = summary.host?.app else { return "Open session" }
        return "Open in \(app)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                LogoMark(size: 16)
                Text(summary.title)
                    .font(Memnox.display(22))
                    .foregroundStyle(Memnox.Palette.foreground)
                    .lineLimit(2)
                Spacer()
                CloseButton(action: close)
            }
            MarkdownText(source: summary.text)
            if !summary.files.isEmpty { FileList(files: summary.files, counting: entrance.shown) }
            if let excerpt = summary.excerpt { CodeExcerpt(excerpt: excerpt) }
            if open != nil || watch != nil {
                HStack(spacing: 8) {
                    Spacer()
                    if let watch { CardButton(title: "Watch live", icon: "play.circle", primary: false, action: watch) }
                    if let open { CardButton(title: openLabel, icon: "arrow.up.forward.app", primary: true, action: open) }
                }
            }
        }
        .modifier(CardFace(entrance: entrance, hovering: hovering))
    }
}

/// What a card sits on and how it moves, in the island's own language: solid black with a hairline
/// edge and a faint blue light rising from the bottom, settling into place with the island's spring.
/// It stays flat, so every button is drawn exactly where it takes a click.
struct CardFace: ViewModifier {
    @ObservedObject var entrance: CardEntrance
    let hovering: (Bool) -> Void

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        content
            .padding(20)
            .frame(width: CardPanel.width, alignment: .leading)
            .background(
                shape.fill(Color.black)
                    .overlay(
                        RadialGradient(
                            colors: [Memnox.Palette.primary.opacity(entrance.facing ? 0.26 : 0.18), .clear],
                            center: UnitPoint(x: 0.5, y: 1.3),
                            startRadius: 0,
                            endRadius: CardPanel.width
                        )
                    )
                    .clipShape(shape)
            )
            .overlay(shape.strokeBorder(Color.white.opacity(entrance.facing ? 0.12 : 0.06), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
            .contentShape(shape)
            .onHover { inside in
                withAnimation(.easeOut(duration: 0.25)) { entrance.facing = inside }
                hovering(inside)
            }
            .scaleEffect(entrance.shown ? 1 : 0.96, anchor: .topLeading)
            .offset(y: entrance.shown ? 0 : -10)
            .blur(radius: entrance.shown ? 0 : 8)
            .opacity(entrance.shown ? 1 : 0)
            .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { entrance.shown = true } }
    }
}

/// The walk through: one page per file, turning on its own at the pace the voice says each note,
/// until the person turns a page themselves, after which the pages are theirs to turn.
struct WalkView: View {
    let walk: WalkCard
    let close: () -> Void
    let open: (() -> Void)?
    let hovering: (Bool) -> Void
    @StateObject private var entrance = CardEntrance()
    @State private var page = 0
    @State private var turning: Task<Void, Never>?
    /// Tall enough for a note and twelve changed lines, so turning a page never resizes the card.
    private static let pageHeight: CGFloat = 300

    /// Roughly how long the voice takes to say a page's note, about fourteen characters a second.
    static func seconds(for page: WalkPage) -> Double {
        max(4, Double(page.note.count) / 14)
    }

    var body: some View {
        let current = walk.pages[min(page, walk.pages.count - 1)]
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                LogoMark(size: 16)
                Text(walk.title)
                    .font(Memnox.display(22))
                    .foregroundStyle(Memnox.Palette.foreground)
                    .lineLimit(1)
                Spacer()
                Text("\(page + 1) of \(walk.pages.count)")
                    .font(Memnox.sans(11, .medium))
                    .foregroundStyle(Memnox.Palette.muted)
                    .contentTransition(.numericText(value: Double(page)))
                CloseButton(action: close)
            }
            VStack(alignment: .leading, spacing: 10) {
                FileList(files: [CardFile(path: current.path, added: current.added, removed: current.removed)], counting: entrance.shown)
                Text(current.note)
                    .font(Memnox.sans(14))
                    .foregroundStyle(Memnox.Palette.foreground.opacity(0.92))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                if !current.lines.isEmpty {
                    CodeExcerpt(excerpt: CardExcerpt(path: current.path, lines: current.lines))
                }
            }
            .id(page)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .frame(height: Self.pageHeight, alignment: .top)
            .clipped()
            HStack(spacing: 8) {
                PageDots(count: walk.pages.count, current: page)
                Spacer()
                CardButton(title: "Back", icon: "chevron.left", primary: false) { turn(to: page - 1) }
                    .opacity(page == 0 ? 0.35 : 1)
                    .disabled(page == 0)
                CardButton(title: "Next", icon: "chevron.right", primary: false) { turn(to: page + 1) }
                    .opacity(page == walk.pages.count - 1 ? 0.35 : 1)
                    .disabled(page == walk.pages.count - 1)
                if let open { CardButton(title: "Open", icon: "arrow.up.forward.app", primary: true, action: open) }
            }
        }
        .modifier(CardFace(entrance: entrance, hovering: hovering))
        .onAppear { turnOnItsOwn() }
        .onDisappear { turning?.cancel() }
    }

    /// The person turned it, so it stops turning on its own and stays where they put it.
    private func turn(to target: Int) {
        turning?.cancel()
        move(to: target)
    }

    private func move(to target: Int) {
        guard walk.pages.indices.contains(target) else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { page = target }
    }

    private func turnOnItsOwn() {
        let pages = walk.pages
        turning = Task { @MainActor in
            for index in pages.indices.dropLast() {
                try? await Task.sleep(nanoseconds: UInt64(Self.seconds(for: pages[index]) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                move(to: index + 1)
            }
        }
    }
}

/// A trace, the way Logfire draws one: each step indented under what it ran inside, with a bar on
/// the trace's own clock, green when it went well, red when it failed, amber when it was refused.
struct TraceView: View {
    let trace: TraceData
    let title: String
    let close: () -> Void
    let hovering: (Bool) -> Void
    @StateObject private var entrance = CardEntrance()
    private static let track: CGFloat = 170

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                LogoMark(size: 16)
                Text(title)
                    .font(Memnox.display(22))
                    .foregroundStyle(Memnox.Palette.foreground)
                    .lineLimit(1)
                Spacer()
                Text(seconds(trace.totalMs))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Memnox.Palette.primary)
                CloseButton(action: close)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(trace.rows.enumerated()), id: \.offset) { index, row in
                    TraceRow(row: row, total: max(trace.totalMs, 1), track: Self.track, shown: entrance.shown)
                        .animation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.25 + Double(index) * 0.05), value: entrance.shown)
                }
            }
        }
        .modifier(CardFace(entrance: entrance, hovering: hovering))
    }
}

private struct TraceRow: View {
    let row: TraceData.Row
    let total: Double
    let track: CGFloat
    let shown: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(stepName(row.name))
                .font(Memnox.sans(12, row.depth == 0 ? .semibold : .regular))
                .foregroundStyle(Memnox.Palette.foreground.opacity(row.depth == 0 ? 1 : 0.85))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, CGFloat(min(row.depth, 4)) * 12)
                .frame(width: 150, alignment: .leading)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06)).frame(width: track, height: 6)
                Capsule()
                    .fill(colour)
                    .frame(width: shown ? max(3, track * row.durationMs / total) : 0, height: 6)
                    .offset(x: track * row.offsetMs / total)
            }
            .frame(width: track, alignment: .leading)
            Text(seconds(row.durationMs))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Memnox.Palette.muted)
                .frame(width: 52, alignment: .trailing)
        }
    }

    private var colour: Color {
        switch row.status {
        case "error": return Memnox.Palette.destructive
        case "refused": return Memnox.Palette.warm
        default: return row.depth == 0 ? Memnox.Palette.primary : Memnox.Palette.success
        }
    }
}

/// A step as a person would name it, rather than the name it was recorded under.
private func stepName(_ name: String) -> String {
    let known = [
        "voice.turn": "Your question", "voice.context": "Reading the sessions", "brain.turn": "Thinking",
        "mac.waiting for the end": "Waiting for you to finish", "mac.first sentence ready": "Answer arriving",
        "mac.speaking": "Speaking",
    ]
    if let said = known[name] { return said }
    if name.hasPrefix("brain.") { return "Asked \(name.dropFirst(6))" }
    if name.hasPrefix("operator.") { return "Ran \(name.dropFirst(9))" }
    return name
}

/// Milliseconds under a second, seconds with one place above, the way a waterfall is read.
private func seconds(_ ms: Double) -> String {
    ms < 1_000 ? "\(Int(ms)) ms" : String(format: "%.1f s", ms / 1_000)
}

/// A dot per page, the current one long and lit, so where the walk is reads at a glance.
private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Memnox.Palette.primary : Color.white.opacity(0.22))
                    .frame(width: index == current ? 16 : 6, height: 6)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: current)
    }
}

/// A button on a card or the live window: a generous target, a pointing hand, and a lift on hover,
/// so it is plain it can be clicked and plain when it was.
struct CardButton: View {
    let title: String
    let icon: String
    let primary: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(Memnox.sans(12.5, .medium))
                .foregroundStyle(primary ? IslandPalette.primaryText : Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(fill))
                .contentShape(Capsule())
        }
        .buttonStyle(PressDown())
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) { hovered = inside }
            pointing(inside)
        }
    }

    private var fill: Color {
        primary
            ? IslandPalette.primaryFill.opacity(hovered ? 1 : 0.92)
            : Color.white.opacity(hovered ? 0.15 : 0.09)
    }
}

/// The close cross, with a target a finger's width across rather than the glyph's.
struct CloseButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovered ? Memnox.Palette.foreground : Memnox.Palette.muted)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(hovered ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressDown())
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) { hovered = inside }
            pointing(inside)
        }
    }
}

/// Sinks a little while held, which is the only sign a borderless panel gives that a click landed.
struct PressDown: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// The pointing hand over anything clickable, set and undone in pairs so it never sticks.
@MainActor
func pointing(_ inside: Bool) {
    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
}

/// The files it changed, each by its short name with the lines it added and removed.
struct FileList: View {
    let files: [CardFile]
    /// Counts roll up from zero once this turns true, so the size of the change is felt, not just read.
    var counting = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(files, id: \.path) { file in
                HStack(spacing: 8) {
                    Text(shortPath(file.path))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Memnox.Palette.foreground.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer(minLength: 8)
                    if let added = file.added {
                        Text("+\(counting ? added : 0)")
                            .foregroundStyle(Memnox.Palette.success)
                            .contentTransition(.numericText(value: Double(counting ? added : 0)))
                    }
                    if let removed = file.removed, removed > 0 {
                        Text("\u{2212}\(counting ? removed : 0)")
                            .foregroundStyle(Memnox.Palette.destructive)
                            .contentTransition(.numericText(value: Double(counting ? removed : 0)))
                    }
                }
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            }
        }
        .animation(.easeOut(duration: 1.1).delay(counting ? 0.55 : 0), value: counting)
        .padding(.top, 2)
    }
}

/// A few changed lines of the file that changed most, coloured the way a diff is read.
private struct CodeExcerpt: View {
    let excerpt: CardExcerpt

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(extensionBadge)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Memnox.Palette.primary))
                Text(shortPath(excerpt.path))
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Color.white.opacity(0.03))
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(excerpt.lines.enumerated()), id: \.offset) { _, line in
                    let tint = colour(of: line)
                    Text(line.dropFirst())
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(line.hasPrefix("-") ? Color.white.opacity(0.45) : IslandPalette.soft)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(tint.opacity(0.09))
                        .overlay(alignment: .leading) { Rectangle().fill(tint.opacity(0.7)).frame(width: 2) }
                }
            }
            .padding(.vertical, 6)
        }
        .background(shape.fill(Color(hex: 0x0D0E10)))
        .overlay(shape.strokeBorder(Color.white.opacity(0.05), lineWidth: 1))
        .clipShape(shape)
    }

    /// The extension as a badge, the way an editor tab marks a file's language.
    private var extensionBadge: String {
        let ext = (excerpt.path as NSString).pathExtension
        return ext.isEmpty ? "TXT" : String(ext.prefix(3)).uppercased()
    }

    private func colour(of line: String) -> Color {
        if line.hasPrefix("+") { return IslandPalette.green }
        if line.hasPrefix("-") { return IslandPalette.red }
        return Color.white.opacity(0.2)
    }
}

/// The last two parts of a path, which is how somebody names a file out loud.
private func shortPath(_ path: String) -> String {
    let parts = path.split(separator: "/")
    return parts.suffix(2).joined(separator: "/")
}
