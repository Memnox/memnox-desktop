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

    /// Apps as their names read lowercased, which is how a host's app is matched.
    private enum AppName {
        static let iTerm = "iterm"
        static let terminal = "terminal"
        static let code = "code"
        static let cursor = "cursor"
        static let windsurf = "windsurf"
        static let zed = "zed"
        /// The names the apps go by, which the front app's own name is matched against.
        static let iTermTitle = "iTerm"
        static let terminalTitle = "Terminal"
    }

    /// The apps looked up by bundle identifier.
    private enum BundleID {
        static let vscode = "com.microsoft.VSCode"
        static let cursor = "com.todesktop.230313mzl4w4u92"
        static let windsurf = "com.exafunction.windsurf"
        static let iTerm = "com.googlecode.iterm2"
    }

    /// The URL schemes, hosts and paths of the Claude Code extension's links and the Memnox extension's.
    private enum Link {
        static let vscodeScheme = "vscode"
        static let cursorScheme = "cursor"
        static let windsurfScheme = "windsurf"
        static let claudeCodeHost = "anthropic.claude-code"
        static let openPath = "/open"
        static let extensionHost = "memnox.memnox-terminals"
        /// An installed extension's folder is its identifier followed by its version.
        static let extensionFolderPrefix = "memnox.memnox-terminals-"
        static let closePath = "/close"
        static let terminalPath = "/terminal"
        static let typePath = "/type"
    }

    /// The query items the extensions read.
    private enum QueryKey {
        static let session = "session"
        static let prompt = "prompt"
        static let request = "request"
        static let tty = "tty"
    }

    /// Folders under the home folder: each editor's own, and the runtime's displays.
    private enum Folder {
        static let vscode = ".vscode"
        static let cursor = ".cursor"
        static let windsurf = ".windsurf"
        static let extensions = "extensions"
        static let displays = ".memnox/displays"
        static let recordExtension = "json"
    }

    private enum Pattern {
        /// The agent's own conversation id is a UUID.
        static let conversationId = #"^[0-9a-fA-F-]{36}$"#
    }

    private enum Timing {
        /// A moment for the editor's window to come forward before the extension's link reaches it.
        static let editorSettle: TimeInterval = 0.3
        /// The new shell needs this long before it reads keys, or the first few are lost.
        static let shellStartup: TimeInterval = 1
        /// A moment for the tab to come forward before checking it is the one in front.
        static let tabSettle: TimeInterval = 0.35
        static let deliveryPoll: TimeInterval = 0.25
        /// Long enough for a few sentences a key at a time, short of the runtime's own wait.
        static let deliveryAttempts = 80
        /// The share of the comet's flight after which the words land, so they arrive with it.
        static let flightLanding = 0.85
        static let nanosecondsPerSecond: TimeInterval = 1_000_000_000
    }

    /// How far above the bottom of the screen the comet starts when the orb's frame is not known.
    private static let fallbackLaunchHeight: CGFloat = 80

    /// What the Memnox extension writes on a request once it has tried to type it.
    private struct DeliveryRecord: Decodable {
        struct Delivered: Decodable {
            let outcome: String
            let reason: String?

            private enum CodingKeys: String, CodingKey { case outcome, reason }

            /// A reason of any other type reads as none, so the record still counts as answered.
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                outcome = try container.decode(String.self, forKey: .outcome)
                reason = try? container.decode(String.self, forKey: .reason)
            }
        }

        let delivered: Delivered?
    }

    /// A sleep length in seconds as the nanoseconds `Task.sleep` takes.
    private static func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
        UInt64((seconds * Timing.nanosecondsPerSecond).rounded())
    }

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
        guard let tty = AppleScriptText.device(host?.tty) else { return Typed(.failed, "it runs in no terminal Memnox knows, such as the Claude Code panel") }
        if !app.contains(AppName.iTerm), Self.editors.contains(where: app.contains) {
            // The editor's own terminal, closed by the Memnox extension against the request the runtime wrote.
            guard let link = Self.extensionLink(app: app, path: Link.closePath, query: [QueryKey.request: request, QueryKey.tty: tty]) else {
                return Typed(.failed, "the Memnox extension is not in \(host?.app ?? "the editor"), so run memnox protect --vscode")
            }
            guard NSWorkspace.shared.open(link) else { return Typed(.failed, "the editor would not take the Memnox link") }
            return await Self.extensionDelivery(of: request)
        }
        if app.contains(AppName.iTerm) {
            return Self.run(Self.iTermCloseScript(tty)) ? .landed : Typed(.failed, "no iTerm tab has its terminal")
        }
        if app.contains(AppName.terminal) {
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
        let editor = Self.conversationEditors.contains(where: app.contains)
        // A session with a terminal runs in one of the editor's terminals, never in the extension panel.
        // Only the agent's own id opens its conversation; any other id makes the panel start a new one,
        // so without it the editor window is brought forward instead.
        if editor, host?.tty == nil, let conversation = host?.conversation,
           conversation.range(of: Pattern.conversationId, options: .regularExpression) != nil,
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
        link.scheme = app.contains(AppName.cursor) ? Link.cursorScheme
            : app.contains(AppName.windsurf) ? Link.windsurfScheme
            : Link.vscodeScheme
        link.host = Link.claudeCodeHost
        link.path = Link.openPath
        link.queryItems = [URLQueryItem(name: QueryKey.session, value: session)]
            + (prompt.map { [URLQueryItem(name: QueryKey.prompt, value: $0)] } ?? [])
        return link.url
    }

    func open(_ host: DisplayHost?) async -> Bool {
        guard let host else { return false }
        let app = (host.app ?? host.appPath ?? "").lowercased()
        if let tty = AppleScriptText.device(host.tty) {
            if app.contains(AppName.iTerm), Self.run(Self.iTermScript(tty)) { return true }
            if app.contains(AppName.terminal), Self.run(Self.terminalScript(tty)) { return true }
        }
        let url = host.appPath.map { URL(fileURLWithPath: $0) }
        if let cwd = host.cwd, let url, Self.editors.contains(where: app.contains) {
            // An editor opened on the session's folder brings forward the window already on it.
            let opened = await Self.open([URL(fileURLWithPath: cwd)], with: url)
            // Then the terminal inside it, which only the Memnox extension can choose among several.
            if opened, let tty = host.tty, let link = Self.extensionLink(app: app, path: Link.terminalPath, query: [QueryKey.tty: tty]) {
                try? await Task.sleep(nanoseconds: Self.nanoseconds(Timing.editorSettle))
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
        guard let tty = query[QueryKey.tty], AppleScriptText.device(tty) != nil else { return nil }
        let (scheme, folder) = app.contains(AppName.cursor) ? (Link.cursorScheme, Folder.cursor)
            : app.contains(AppName.windsurf) ? (Link.windsurfScheme, Folder.windsurf)
            : (Link.vscodeScheme, Folder.vscode)
        let extensions = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("\(folder)/\(Folder.extensions)")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: extensions.path)) ?? []
        guard names.contains(where: { $0.hasPrefix(Link.extensionFolderPrefix) }) else { return nil }
        var link = URLComponents()
        link.scheme = scheme
        link.host = Link.extensionHost
        link.path = path
        link.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return link.url
    }

    /// VS Code first, since Claude Code most often runs inside it, then Cursor.
    private static func installedEditor() -> URL? {
        [BundleID.vscode, BundleID.cursor, BundleID.windsurf]
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
        let iTerm = NSWorkspace.shared.urlForApplication(withBundleIdentifier: BundleID.iTerm) != nil
        let name = iTerm ? AppName.iTermTitle : AppName.terminalTitle
        await launch(toward: name)
        // Only a bare tab: the line typed into it goes into the repository itself, since a cd sent
        // on its own here reached the shell after the typed line and started the agent in the home folder.
        guard Self.run(iTerm ? Self.iTermNewTab() : Self.terminalNewTab()) else {
            return Typed(.failed, "a new \(name) tab would not open")
        }
        try? await Task.sleep(nanoseconds: Self.nanoseconds(Timing.shellStartup))
        guard PromptTyping.allowed(),
              let front = NSWorkspace.shared.frontmostApplication,
              (front.localizedName ?? "").lowercased().contains(name.lowercased())
        else {
            // Without leave to press keys, the terminal's own scripting puts the line in all at once.
            let line = AppleScriptText.quoted(command)
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
        guard let host, let tty = AppleScriptText.device(host.tty) else { return Typed(.failed, "its terminal tab is not known") }
        let app = (host.app ?? host.appPath ?? "").lowercased()
        let iTerm = app.contains(AppName.iTerm)
        if !iTerm, Self.editors.contains(where: app.contains) {
            return await typeInEditorTerminal(request: request, tty: tty, host: host, app: app)
        }
        guard iTerm || app.contains(AppName.terminal) else { return Typed(.failed, "it does not run in iTerm, Terminal or an editor") }
        await launch(toward: host.app ?? app)
        guard PromptTyping.allowed() else {
            // Without leave to press keys, the terminal's own scripting puts the words in all at once.
            let words = AppleScriptText.quoted(text)
            let typed = Self.run(iTerm ? Self.iTermTypeScript(tty, words) : Self.terminalTypeScript(tty, words))
            return typed ? .landed : Typed(.failed, "no \(iTerm ? "iTerm" : "Terminal") tab has its terminal")
        }
        guard Self.run(iTerm ? Self.iTermScript(tty) : Self.terminalScript(tty)) else {
            return Typed(.failed, "no \(iTerm ? "iTerm" : "Terminal") tab has its terminal")
        }
        try? await Task.sleep(nanoseconds: Self.nanoseconds(Timing.tabSettle))
        guard Self.run(iTerm ? Self.iTermInFront(tty) : Self.terminalInFront(tty)),
              let front = NSWorkspace.shared.frontmostApplication,
              (front.localizedName ?? "").lowercased().contains(iTerm ? AppName.iTerm : AppName.terminal)
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
        guard let link = Self.extensionLink(app: app, path: Link.typePath, query: [QueryKey.request: request, QueryKey.tty: tty]) else {
            return Typed(.failed, "the Memnox extension is not in \(host.app ?? "the editor"), so run memnox protect --vscode")
        }
        await launch(toward: host.app ?? app)
        _ = await open(host)
        try? await Task.sleep(nanoseconds: Self.nanoseconds(Timing.editorSettle))
        guard NSWorkspace.shared.open(link) else { return Typed(.failed, "the editor would not take the Memnox link") }
        return await Self.extensionDelivery(of: request)
    }

    /// What the extension wrote on the request once it typed it, read from the runtime's own folder.
    private static func extensionDelivery(of request: String) async -> Typed {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("\(Folder.displays)/\(request).\(Folder.recordExtension)")
        for _ in 0..<Timing.deliveryAttempts {
            if let data = try? Data(contentsOf: file),
               let record = try? JSONDecoder().decode(DeliveryRecord.self, from: data),
               let delivered = record.delivered {
                return delivered.outcome == Delivery.typed.rawValue
                    ? .landed
                    : Typed(.failed, delivered.reason ?? "the extension could not type it")
            }
            try? await Task.sleep(nanoseconds: nanoseconds(Timing.deliveryPoll))
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
            ?? NSScreen.main.map { NSPoint(x: $0.frame.midX, y: $0.frame.minY + Self.fallbackLaunchHeight) }
        guard let start else { return }
        flight.fly(from: start, toApp: app)
        try? await Task.sleep(nanoseconds: UInt64(FlightPanel.duration * Timing.flightLanding * Timing.nanosecondsPerSecond))
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
    private static let editors = [AppName.code, AppName.cursor, AppName.windsurf, AppName.zed]

    /// Editors whose Claude Code extension opens one conversation by its link.
    private static let conversationEditors = [AppName.code, AppName.cursor, AppName.windsurf]

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
