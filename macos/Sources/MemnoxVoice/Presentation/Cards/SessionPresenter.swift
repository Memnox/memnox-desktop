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
    /// Whether words go to a session without taking the person's window, the person's own setting.
    var inBackground: () -> Bool = { true }
    /// The app the person was last in, which is the one looked at when the brain names none.
    var frontApp: () -> String? = { nil }
    /// That app as it runs, so the person is put back in it after a delivery had to borrow the screen.
    var personsApp: () -> NSRunningApplication? = { nil }

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
        static let terminal = "com.apple.Terminal"
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
        static let interruptPath = "/interrupt"
        static let terminalPath = "/terminal"
        static let typePath = "/type"
        static let pressPath = "/press"
        static let launchPath = "/launch"
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
        static let obsolete = ".obsolete"
        static let displays = ".memnox/displays"
        static let recordExtension = "json"
    }

    private enum Pattern {
        /// The agent's own conversation id is a UUID.
        static let conversationId = #"^[0-9a-fA-F-]{36}$"#
    }

    private enum Timing {
        /// A moment for the editor's window to come forward before the extension's link reaches it.
        static let editorSettle: TimeInterval = 0.2
        /// The new shell needs this long before it reads keys, or the first few are lost.
        static let shellStartup: TimeInterval = 1
        /// A moment for the tab to come forward before checking it is the one in front.
        static let tabSettle: TimeInterval = 0.12
        /// A beat between the last key and Return, since an agent reads text and Return arriving together as a paste.
        static let beforeReturn: TimeInterval = 0.15
        static let deliveryPoll: TimeInterval = 0.1
        /// Long enough for a few sentences a key at a time, short of the runtime's own wait.
        static let deliveryAttempts = 200
        /// Between an app's links, so a prompt link reaches the window the link before it opened.
        static let appSettle: TimeInterval = 1.5
        /// How often an unanswered extension link is sent again, since a window still starting drops the first.
        static let linkResendEvery = 30
        /// The pause in the person's typing waited for before the screen is borrowed, so no key of theirs lands elsewhere.
        static let typingPause: TimeInterval = 0.8
        static let typingPauseChecks = 20
        static let typingPauseCheck: TimeInterval = 0.2
        static let nanosecondsPerSecond: TimeInterval = 1_000_000_000
        /// Long enough for an editor's restarted extensions to come back before the link is sent to them.
        static let extensionsRestart: TimeInterval = 1.5
        /// How long each other editor window is given to answer, past the extension's own wait for a claim.
        static let windowAttempts = 40
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
        /// Set by the extension when no integrated terminal holds the device, which leaves the request for the Mac.
        let noTerminal: Bool?
        /// The extension host of the window holding the terminal, which is typing it whatever another window wrote.
        let claimedBy: Int?
    }

    /// A sleep length in seconds as the nanoseconds `Task.sleep` takes.
    private static func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
        UInt64((seconds * Timing.nanosecondsPerSecond).rounded())
    }

    /// True while a server is the target, whose sessions have no tab on this Mac, so the live window's jump does nothing.
    var remote: () -> Bool = { false }

    init() {
        livePanel.openOwnWindow = { [weak self] session, host in
            guard let self, !self.remote() else { return }
            _ = await self.bringForward(session: session, host: host)
        }
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
        guard let tty = AppleScriptText.device(host?.tty) else {
            // A desktop app the person named: its window closes and the app keeps the chat.
            if let host, host.appPath != nil, !Self.editors.contains(where: app.contains) { return await closeWindow(of: host) }
            return Typed(.failed, "it runs in no terminal Memnox knows, such as the Claude Code panel")
        }
        if !app.contains(AppName.iTerm), Self.editors.contains(where: app.contains) {
            // The editor's own terminal, closed by the Memnox extension against the request the runtime wrote.
            guard let link = Self.extensionLink(app: app, path: Link.closePath, query: [QueryKey.request: request, QueryKey.tty: tty]) else {
                return Typed(.failed, "the Memnox extension is not in \(host?.app ?? "the editor") yet, which the daemon puts in as it starts",
                             hint: .installExtension(app: host?.app ?? Self.anEditor))
            }
            return await borrowingScreen {
                guard NSWorkspace.shared.open(link) else { return Typed(.failed, "the editor would not take the Memnox link") }
                return await Self.extensionDelivery(of: request, resending: link).withEditorHint(host?.app ?? Self.anEditor)
            }
        }
        if app.contains(AppName.iTerm) {
            return Self.run(Self.iTermCloseScript(tty)) ? .landed : Typed(.failed, "no iTerm tab has its terminal")
        }
        if app.contains(AppName.terminal) {
            if Self.run(Self.terminalCloseScript(tty)) { return .landed }
            return await closeTerminalTab(tty)
        }
        guard let host else { return Typed(.failed, "where it runs is not known") }
        return await closeWindow(of: host, onlyIfAlone: true)
    }

    /// A Terminal tab in a window with others, which its scripting cannot close: brought to the front and
    /// closed with Command W. The runtime ended the agent first, so Terminal has nothing to ask about.
    private func closeTerminalTab(_ tty: String) async -> Typed {
        guard PromptTyping.allowed() else {
            return Typed(.failed, "Memnox may not press keys until it is switched on under Accessibility, so its tab stays open")
        }
        guard Self.run(Self.terminalScript(tty)) else { return Typed(.failed, Self.noTab(AppName.terminalTitle)) }
        try? await Task.sleep(nanoseconds: Self.nanoseconds(Timing.tabSettle))
        guard Self.run(Self.terminalInFront(tty)),
              (NSWorkspace.shared.frontmostApplication?.localizedName ?? "").lowercased().contains(AppName.terminal)
        else { return Typed(.failed, "its Terminal tab did not come to the front") }
        PromptTyping.pressCommand(PromptTyping.wKey)
        return .landed
    }

    /// The app's window closed with Command W; for a terminal app only when it shows one window with one
    /// tab, which can only be the session's, since closing another would end somebody else's work.
    private func closeWindow(of host: DisplayHost, onlyIfAlone: Bool = false) async -> Typed {
        let name = Self.appName(of: host) ?? "the app"
        guard let target = Self.running(host) else { return Typed(.failed, "\(name) is not running") }
        guard PromptTyping.allowed() else {
            return Typed(.failed, "Memnox may not press keys until it is switched on under Accessibility")
        }
        if #available(macOS 14, *) { NSApp.yieldActivation(to: target) }
        target.activate()
        try? await Task.sleep(nanoseconds: Self.nanoseconds(Timing.tabSettle))
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
            return Typed(.failed, "\(name) did not come to the front")
        }
        if onlyIfAlone, !(await Self.itsOwnView(of: target, host: host)) {
            return Typed(.failed, "\(name) has several windows or tabs, and none of them alone shows this session")
        }
        PromptTyping.pressCommand(PromptTyping.wKey)
        return .landed
    }

    /// Escape in the session's own terminal, as the person would press it: the turn stops there and the tab stays.
    /// iTerm takes it as a key through its scripting with nothing brought forward; an editor's terminal through
    /// the Memnox extension; Terminal only as a real key press, so its tab comes forward first.
    func interrupt(session: String, host: DisplayHost?, request: String) async -> Typed {
        let app = (host?.app ?? host?.appPath ?? "").lowercased()
        guard let tty = AppleScriptText.device(host?.tty) else { return await interruptWithoutTerminal(session: session, host: host, app: app) }
        if !app.contains(AppName.iTerm), Self.editors.contains(where: app.contains) {
            guard let link = Self.extensionLink(app: app, path: Link.interruptPath, query: [QueryKey.request: request, QueryKey.tty: tty]) else {
                return Typed(.failed, "the Memnox extension is not in \(host?.app ?? "the editor") yet, which the daemon puts in as it starts",
                             hint: .installExtension(app: host?.app ?? Self.anEditor))
            }
            return await borrowingScreen {
                guard NSWorkspace.shared.open(link) else { return Typed(.failed, "the editor would not take the Memnox link") }
                return await Self.extensionDelivery(of: request, resending: link).withEditorHint(host?.app ?? Self.anEditor)
            }
        }
        if app.contains(AppName.iTerm) {
            return Self.run(Self.iTermEscapeScript(tty, marks: host?.marks ?? [])) ? .landed : Typed(.failed, Self.noTab(AppName.iTermTitle))
        }
        guard app.contains(AppName.terminal) else { return await interruptOtherTerminal(host) }
        guard PromptTyping.allowed() else {
            return Typed(.failed, "Memnox may not press keys until it is switched on under Accessibility in System Settings")
        }
        guard Self.run(Self.terminalScript(tty, marks: host?.marks ?? [])) else { return Typed(.failed, Self.noTab(AppName.terminalTitle)) }
        try? await Task.sleep(nanoseconds: Self.nanoseconds(Timing.tabSettle))
        // Only into its own tab: Escape pressed anywhere else would stop whatever the person is doing there.
        guard Self.run(Self.terminalInFront(tty, marks: host?.marks ?? [])),
              let front = NSWorkspace.shared.frontmostApplication,
              (front.localizedName ?? "").lowercased().contains(AppName.terminal)
        else { return Typed(.failed, "its Terminal tab did not come to the front") }
        PromptTyping.pressEscape()
        return .landed
    }

    /// Keys pressed in the session's own tab to answer what its agent asks there, such as whether to trust a
    /// folder. iTerm takes them as text through its scripting with nothing brought forward; an editor's terminal
    /// through the Memnox extension; Terminal only as real key presses, so its tab comes forward first and
    /// nothing is pressed unless that tab is in front.
    func press(_ keys: [TerminalPress], session: String, host: DisplayHost?, request: String) async -> Typed {
        let app = (host?.app ?? host?.appPath ?? "").lowercased()
        guard let tty = AppleScriptText.device(host?.tty) else {
            return Typed(.failed, "the tab it runs in was never noted, so there is nowhere to answer it")
        }
        if !app.contains(AppName.iTerm), Self.editors.contains(where: app.contains), let host {
            return await pressInEditorTerminal(request: request, tty: tty, host: host, app: app)
        }
        if app.contains(AppName.iTerm) {
            return Self.run(Self.iTermWriteScript(tty, keys, marks: host?.marks ?? [])) ? .landed : Typed(.failed, Self.noTab(AppName.iTermTitle))
        }
        guard app.contains(AppName.terminal) else {
            return Typed(.failed, "its question can be answered only in a Terminal or iTerm tab, and it runs in \(host?.app ?? "another app")")
        }
        guard PromptTyping.allowed() else {
            return Typed(.failed, "Memnox may not press keys until it is switched on under Accessibility in System Settings")
        }
        guard Self.run(Self.terminalScript(tty, marks: host?.marks ?? [])) else { return Typed(.failed, Self.noTab(AppName.terminalTitle)) }
        try? await Task.sleep(nanoseconds: Self.nanoseconds(Timing.tabSettle))
        // Only into its own tab: keys pressed anywhere else would answer for whatever the person is doing there.
        guard Self.run(Self.terminalInFront(tty, marks: host?.marks ?? [])),
              let front = NSWorkspace.shared.frontmostApplication,
              (front.localizedName ?? "").lowercased().contains(AppName.terminal)
        else { return Typed(.failed, "its Terminal tab did not come to the front") }
        await PromptTyping.press(keys)
        return .landed
    }

    /// Keys pressed in an editor's integrated terminal by the Memnox extension, which reads them from the request
    /// itself; the window holding that terminal answers, whichever of the editor's windows the link reached.
    private func pressInEditorTerminal(request: String, tty: String, host: DisplayHost, app: String) async -> Typed {
        let name = host.app ?? Self.anEditor
        guard let link = Self.extensionLink(app: app, path: Link.pressPath, query: [QueryKey.request: request, QueryKey.tty: tty]) else {
            return Typed(.failed, "the Memnox extension is not in \(name) yet, which the daemon puts in as it starts",
                         hint: .installExtension(app: name))
        }
        return await borrowingScreen {
            _ = await open(host)
            try? await Task.sleep(nanoseconds: Self.nanoseconds(Timing.editorSettle))
            guard NSWorkspace.shared.open(link) else { return Typed(.failed, "the editor would not take the Memnox link") }
            let delivered = await Self.extensionDelivery(of: request, resending: link)
            if delivered.reason == Self.noEditorTerminal,
               let found = await inOtherWindows(request: request, tty: tty, host: host, app: app, path: Link.pressPath) {
                return found
            }
            // Silent is a window on an extension from before keys could be pressed, which takes the new one on a restart.
            if delivered.reason == Self.extensionSilent,
               let again = await retypeAfterRestart(request: request, tty: tty, host: host, app: app, path: Link.pressPath) {
                return again.withEditorHint(name)
            }
            return delivered.withEditorHint(name)
        }
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
            if app.contains(AppName.iTerm), Self.run(Self.iTermScript(tty, marks: host.marks ?? [])) { return true }
            if app.contains(AppName.terminal), Self.run(Self.terminalScript(tty, marks: host.marks ?? [])) { return true }
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
        if url != nil || host.app != nil, let target = Self.running(host) {
            // Another terminal app: its window whose title names the session's folder, where it shows one.
            if #available(macOS 14, *) { NSApp.yieldActivation(to: target) }
            target.activate()
            if let marks = host.marks, await TabFinder.bringForward(in: target, marks: marks, tty: host.tty) { return true }
            if let cwd = host.cwd { PromptTyping.raiseWindow(of: target, titled: (cwd as NSString).lastPathComponent) }
            return true
        }
        if let url { return await Self.open([], with: url) }
        // Only the folder is known, so it opens in whichever editor is installed, which brings its window forward.
        guard let cwd = host.cwd, let editor = Self.installedEditor() else { return false }
        return await Self.open([URL(fileURLWithPath: cwd)], with: editor)
    }

    /// A link to the Memnox extension, only where that editor has it installed, since a link
    /// nothing handles makes the editor offer to search its marketplace.
    private static func extensionLink(app: String, path: String, query: [String: String]) -> URL? {
        // Every link but a launch names the terminal it acts on, and only a real one.
        if path != Link.launchPath {
            guard let tty = query[QueryKey.tty], AppleScriptText.device(tty) != nil else { return nil }
        }
        let (scheme, folder) = app.contains(AppName.cursor) ? (Link.cursorScheme, Folder.cursor)
            : app.contains(AppName.windsurf) ? (Link.windsurfScheme, Folder.windsurf)
            : (Link.vscodeScheme, Folder.vscode)
        let extensions = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("\(folder)/\(Folder.extensions)")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: extensions.path)) ?? []
        // An uninstalled copy stays on disk until the editor restarts, listed in .obsolete and never loaded.
        let removed = (try? Data(contentsOf: extensions.appendingPathComponent(Folder.obsolete)))
            .flatMap { try? JSONDecoder().decode([String: Bool].self, from: $0) } ?? [:]
        guard names.contains(where: { $0.hasPrefix(Link.extensionFolderPrefix) && removed[$0] != true }) else { return nil }
        var link = URLComponents()
        link.scheme = scheme
        link.host = Link.extensionHost
        link.path = path
        link.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return link.url
    }

    /// VS Code first, since Claude Code most often runs inside it, then Cursor.
    /// Finder shows it, the editor opens on it, or a terminal starts a tab in it, iTerm when it is installed.
    func openFolder(_ path: String, in opener: FolderOpener) async -> Bool {
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        switch opener {
        case .finder:
            return NSWorkspace.shared.open(folder)
        case .editor:
            guard let editor = Self.installedEditor() else { return NSWorkspace.shared.open(folder) }
            return await Self.open([folder], with: editor)
        case .terminal:
            let terminal = [BundleID.iTerm, BundleID.terminal].lazy
                .compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
                .first
            guard let terminal else { return false }
            return await Self.open([folder], with: terminal)
        }
    }

    /// The page in the person's default browser, or the app that claims its address, as clicking the link would.
    func openLink(_ url: URL) async -> Bool {
        NSWorkspace.shared.open(url)
    }

    /// The app first when the runtime named it, with what it reads as it opens, then each of its own
    /// links a moment apart, and the words on the clipboard when no link could carry them.
    func openApp(_ start: AppStart) async -> Typed {
        await launch(toward: start.name)
        if let path = start.appPath {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.environment = start.env
            do {
                _ = try await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration)
            } catch {
                diary.note("could not open \(path): \(error)")
                return Typed(.failed, "\(start.name) would not open")
            }
        }
        for (index, text) in start.links.enumerated() {
            if index > 0 { try? await Task.sleep(nanoseconds: Self.nanoseconds(Timing.appSettle)) }
            guard let link = URL(string: text), NSWorkspace.shared.open(link) else {
                return Typed(.failed, "\(start.name) did not answer its link, so it may not be installed")
            }
        }
        guard let words = start.typed else { return await sendPrefilled(start) }
        guard let path = start.appPath else {
            PromptTyping.leaveOnClipboard(words)
            return Typed(.clipboard, "where \(start.name) is installed was not said, so it could not be typed into")
        }
        // A new chat the link just opened is still drawing its message box.
        if !start.links.isEmpty { try? await Task.sleep(nanoseconds: Self.nanoseconds(Timing.appSettle)) }
        // Command N is a new chat in the chat apps people use, pressed only with the app itself in front.
        if start.newChat, PromptTyping.allowed(), let app = Self.running(at: URL(fileURLWithPath: path)) {
            try? await Task.sleep(nanoseconds: Self.nanoseconds(Timing.appSettle))
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                PromptTyping.pressCommand(PromptTyping.nKey)
                try? await Task.sleep(nanoseconds: Self.nanoseconds(Timing.appSettle))
            }
        }
        let typed = await PromptTyping.typeIntoApp(words, inAppAt: path)
        if !typed.wentIn { PromptTyping.leaveOnClipboard(words) }
        return typed
    }

    /// What a prompt link left in the app's chat, such as Cursor's, sent with Return once it is read in the focused
    /// chat input with the app in front; otherwise left there for the person, which reads as only opened.
    private func sendPrefilled(_ start: AppStart) async -> Typed {
        guard start.sendPrefilled, let path = start.appPath, let words = start.prefilledWords else { return .landed }
        // The chat the link opened is still drawing and filling its input.
        try? await Task.sleep(nanoseconds: Self.nanoseconds(Timing.appSettle))
        return await PromptTyping.sendPrefilled(words, inAppAt: path) ?? .landed
    }

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

    /// In an editor: its window on the repository comes forward, then the Memnox extension there
    /// opens a new terminal and types the line, read from the request rather than the link.
    func launch(_ command: String, in folder: String?, editor: String?, request: String) async -> Typed {
        guard let editor else { return await launch(command, in: folder) }
        guard let folder, FileManager.default.fileExists(atPath: folder) else {
            return Typed(.failed, "the repository folder is not there")
        }
        let app = URL(fileURLWithPath: editor)
        let name = app.deletingPathExtension().lastPathComponent
        guard let link = Self.extensionLink(app: name.lowercased(), path: Link.launchPath, query: [QueryKey.request: request]) else {
            return Typed(.failed, "the Memnox extension is not in \(name) yet, which the daemon puts in as it starts",
                         hint: .installExtension(app: name))
        }
        await launch(toward: name)
        return await borrowingScreen {
            guard await Self.open([URL(fileURLWithPath: folder, isDirectory: true)], with: app) else {
                return Typed(.failed, "\(name) would not open on the repository")
            }
            // A window just opened is still starting its extensions, and a link sent sooner is lost, so it is sent again until answered.
            try? await Task.sleep(nanoseconds: Self.nanoseconds(Timing.appSettle))
            guard NSWorkspace.shared.open(link) else { return Typed(.failed, "\(name) would not take the Memnox link") }
            return await Self.extensionDelivery(of: request, resending: link).withEditorHint(name)
        }
    }

    /// Another terminal app, such as Ghostty or Warp, opened on the folder, and the line typed into the window it
    /// opened. Typed only when a new window or tab appeared, since a terminal that only came forward has a tab
    /// in front that may be another agent; the line then waits on the clipboard.
    func launch(_ command: String, in folder: String?, terminalApp: String) async -> Typed {
        guard let folder, FileManager.default.fileExists(atPath: folder) else {
            return Typed(.failed, "the repository folder is not there")
        }
        let app = URL(fileURLWithPath: terminalApp)
        let name = app.deletingPathExtension().lastPathComponent
        guard PromptTyping.allowed() else {
            PromptTyping.leaveOnClipboard(command)
            return Typed(.clipboard, "Memnox may not press keys until it is switched on under Accessibility", hint: .pasteIn(app: name))
        }
        await launch(toward: name)
        let before = PromptTyping.viewCount(Self.running(at: app))
        guard await Self.open([URL(fileURLWithPath: folder, isDirectory: true)], with: app) else {
            return Typed(.failed, "\(name) would not open on the repository")
        }
        try? await Task.sleep(nanoseconds: Self.nanoseconds(Timing.appSettle))
        guard let terminal = Self.running(at: app), PromptTyping.viewCount(terminal) > before,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == terminal.processIdentifier
        else {
            PromptTyping.leaveOnClipboard(command)
            return Typed(.clipboard, "\(name) did not open a new window to start it in", hint: .pasteIn(app: name))
        }
        return await PromptTyping.type(command, into: terminal)
    }

    /// The editor opened on the folder, a new conversation in its Claude Code panel, and the task sent as its first message.
    func startInPanel(_ task: String, in folder: String?, editor: String?) async -> Typed {
        guard let editor, let folder, FileManager.default.fileExists(atPath: folder) else {
            return Typed(.failed, "the repository folder or the editor is not there")
        }
        let app = URL(fileURLWithPath: editor)
        let name = app.deletingPathExtension().lastPathComponent
        await launch(toward: name)
        return await borrowingScreen {
            guard await Self.open([URL(fileURLWithPath: folder, isDirectory: true)], with: app) else {
                return Typed(.failed, "\(name) would not open on the repository")
            }
            try? await Task.sleep(nanoseconds: Self.nanoseconds(Timing.appSettle))
            guard let link = Self.newConversationLink(app: name.lowercased()), NSWorkspace.shared.open(link) else {
                return Typed(.failed, "\(name) would not open a Claude Code conversation, so the Claude Code extension may not be installed there")
            }
            try? await Task.sleep(nanoseconds: Self.nanoseconds(Timing.appSettle))
            let typed = await PromptTyping.typeIntoEditor(task, inAppAt: editor)
            if !typed.wentIn { PromptTyping.leaveOnClipboard(task) }
            return typed
        }
    }

    /// The Claude Code extension's link with no conversation named, which opens a new one.
    private static func newConversationLink(app: String) -> URL? {
        var link = URLComponents()
        link.scheme = app.contains(AppName.cursor) ? Link.cursorScheme
            : app.contains(AppName.windsurf) ? Link.windsurfScheme
            : Link.vscodeScheme
        link.host = Link.claudeCodeHost
        link.path = Link.openPath
        return link.url
    }

    /// The app running from this bundle, or nil when it is not running.
    private static func running(at app: URL) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleURL?.standardizedFileURL == app.standardizedFileURL }
    }

    /// The screen borrowed for a delivery that only lands with its window in front, then handed back to the
    /// app the person was in. Their typing is waited out first, so none of their keys land in the agent.
    private func borrowingScreen(_ work: () async -> Typed) async -> Typed {
        guard inBackground() else { return await work() }
        let person = personsApp()
        await Self.untilTypingPauses()
        let typed = await work()
        if let person, !person.isTerminated, NSWorkspace.shared.frontmostApplication != person {
            if #available(macOS 14, *) { NSApp.yieldActivation(to: person) }
            person.activate()
            diary.note("handed the screen back to \(person.localizedName ?? "the app they were in")")
        }
        return typed
    }

    /// Waits, briefly, for a gap in the person's typing; it never waits long, since they asked for this.
    private static func untilTypingPauses() async {
        for _ in 0..<Timing.typingPauseChecks {
            if CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) >= Timing.typingPause { return }
            try? await Task.sleep(nanoseconds: nanoseconds(Timing.typingPauseCheck))
        }
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
        if inBackground() {
            // A tab opened and the line written by the terminal's own scripting, with no window brought forward.
            let line = AppleScriptText.quoted(command)
            return Self.run(iTerm ? Self.iTermLaunchBehind(line) : Self.terminalLaunchBehind(line))
                ? .landed
                : Typed(.failed, "a new \(name) tab would not open")
        }
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
            // An editor brings its own window forward for any link it takes, so the screen is borrowed and handed back.
            return await borrowingScreen { await self.typeInEditorTerminal(text, request: request, tty: tty, host: host, app: app) }
        }
        guard iTerm || app.contains(AppName.terminal) else { return await typeInOtherTerminal(text, host: host) }
        let terminal: Readback.Terminal = iTerm ? .iTerm : .terminal
        let before = Readback.text(terminal, tty: tty)
        await launch(toward: host.app ?? app)
        if inBackground() {
            let typed = typeBehind(PromptTyping.oneLine(text), into: terminal, tty: tty)
            return await checked(typed, words: text, in: terminal, tty: tty, before: before, request: request)
        }
        let typed = await typeInFront(text, into: terminal, tty: tty)
        return await checked(typed, words: text, in: terminal, tty: tty, before: before, request: request)
    }

    /// An editor's agent panel, stopped with Escape in its conversation once that is brought forward, or a desktop
    /// app, stopped with its own Stop button where it shows one and Escape where it does not.
    private func interruptWithoutTerminal(session: String, host: DisplayHost?, app: String) async -> Typed {
        guard let host else { return Typed(.failed, "where it runs is not known") }
        if Self.conversationEditors.contains(where: app.contains) {
            guard host.conversation != nil else { return Typed(.failed, "which conversation it is in the editor is not known yet") }
            return await borrowingScreen {
                _ = await self.bringForward(session: session, host: host)
                try? await Task.sleep(nanoseconds: Self.nanoseconds(Timing.editorSettle))
                return await PromptTyping.escapeInEditor(inAppAt: host.appPath)
                    ? .landed
                    : Typed(.failed, "the Claude Code panel's message box could not be found to press Escape in")
            }
        }
        guard let target = Self.running(host) else { return Typed(.failed, "\(host.app ?? "the app") is not running") }
        guard PromptTyping.allowed() else {
            return Typed(.failed, "Memnox may not press keys until it is switched on under Accessibility")
        }
        if #available(macOS 14, *) { NSApp.yieldActivation(to: target) }
        target.activate()
        try? await Task.sleep(nanoseconds: Self.nanoseconds(Timing.tabSettle))
        if PromptTyping.pressStop(in: target) { return .landed }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
            return Typed(.failed, "\(host.app ?? "the app") did not come to the front")
        }
        PromptTyping.pressEscape()
        return .landed
    }

    /// Escape in any other terminal app, pressed only when it has one window with one tab, which can only be the session's.
    private func interruptOtherTerminal(_ host: DisplayHost?) async -> Typed {
        guard let host, let terminal = Self.running(host) else { return Typed(.failed, "the app it runs in is not running") }
        let name = host.app ?? terminal.localizedName ?? "its terminal"
        guard PromptTyping.allowed() else {
            return Typed(.failed, "Memnox may not press keys until it is switched on under Accessibility in System Settings")
        }
        if #available(macOS 14, *) { NSApp.yieldActivation(to: terminal) }
        terminal.activate()
        try? await Task.sleep(nanoseconds: Self.nanoseconds(Timing.tabSettle))
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == terminal.processIdentifier,
              await Self.itsOwnView(of: terminal, host: host)
        else { return Typed(.failed, "\(name) has several windows or tabs, and none of them alone shows this session; press Escape in its tab") }
        PromptTyping.pressEscape()
        return .landed
    }

    /// Any other terminal app, which offers no way to find a tab by its terminal: typed into only when it has
    /// one window with one tab, which can only be the session's, and otherwise left on the clipboard.
    private func typeInOtherTerminal(_ text: String, host: DisplayHost) async -> Typed {
        let name = Self.appName(of: host) ?? "its terminal"
        guard let terminal = Self.running(host) else { return Typed(.failed, "\(name) is not running, so its session cannot be reached") }
        guard PromptTyping.allowed() else {
            PromptTyping.leaveOnClipboard(text)
            return Typed(.clipboard, "Memnox may not press keys until it is switched on under Accessibility", hint: .pasteIn(app: name))
        }
        if #available(macOS 14, *) { NSApp.yieldActivation(to: terminal) }
        terminal.activate()
        try? await Task.sleep(nanoseconds: Self.nanoseconds(Timing.tabSettle))
        guard await Self.itsOwnView(of: terminal, host: host) else {
            PromptTyping.leaveOnClipboard(text)
            return Typed(.clipboard, "\(name) has several windows or tabs, and none of them alone shows this session", hint: .pasteIn(app: name))
        }
        return await PromptTyping.type(text, into: terminal)
    }

    /// The session's own window and tab in front: the only one the app has, or the one showing its lines.
    private static func itsOwnView(of terminal: NSRunningApplication, host: DisplayHost) async -> Bool {
        if PromptTyping.showsOneView(terminal) { return true }
        guard let marks = host.marks, !marks.isEmpty else { return false }
        return await TabFinder.bringForward(in: terminal, marks: marks, tty: host.tty)
    }

    /// The app a session runs in, by its bundle when that was noted and by its name otherwise.
    private static func running(_ host: DisplayHost) -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications
        if let path = host.appPath, let found = apps.first(where: { $0.bundleURL?.path == path }) { return found }
        guard let name = host.app?.lowercased() else { return nil }
        return apps.first { ($0.localizedName ?? "").lowercased() == name }
    }

    /// The words written into the tab by the terminal's own scripting, which needs no window in front,
    /// so the person carries on where they are while the agent gets them.
    private func typeBehind(_ line: String, into terminal: Readback.Terminal, tty: String) -> Typed {
        let quoted = AppleScriptText.quoted(line)
        let sent = terminal == .iTerm
            // Text then Return as two writes, since both at once reads to an agent as a paste.
            ? Self.run(Self.iTermTypeScript(tty, quoted, newline: false)) && Self.run(Self.iTermTypeScript(tty, "", newline: true))
            : Self.run(Self.terminalTypeScript(tty, quoted))
        return sent ? .landed : Typed(.failed, Self.noTab(terminal.name))
    }

    /// Read back after it was sent, with the tab's window captured as it was left, so landed means seen.
    private func checked(_ typed: Typed, words: String, in terminal: Readback.Terminal, tty: String, before: String?, request: String) async -> Typed {
        guard typed.wentIn, let proof = await Readback.landed(PromptTyping.oneLine(words), in: terminal, tty: tty, before: before) else { return typed }
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: terminal == .iTerm ? BundleID.iTerm : BundleID.terminal).first
        let image = app == nil ? nil : await ScreenSight.proof(of: app!, request: request)
        return typed.verified(proof.with(image: image))
    }

    /// The tab brought forward and typed into a key at a time, for a person who chose to watch it go in.
    private func typeInFront(_ text: String, into terminal: Readback.Terminal, tty: String) async -> Typed {
        let iTerm = terminal == .iTerm
        guard PromptTyping.allowed() else {
            // Without leave to press keys, iTerm's own scripting still types it a key at a time; Terminal's
            // can only put a whole line in, so the person is told how to let Memnox type it there.
            if iTerm { return await typeThroughITerm(PromptTyping.oneLine(text), tty: tty) }
            guard Self.run(Self.terminalTypeScript(tty, AppleScriptText.quoted(PromptTyping.oneLine(text)))) else {
                return Typed(.failed, Self.noTab(AppName.terminalTitle))
            }
            return Typed(.typed, hint: .allowTyping)
        }
        guard Self.run(iTerm ? Self.iTermScript(tty) : Self.terminalScript(tty)) else {
            return Typed(.failed, Self.noTab(iTerm ? AppName.iTermTitle : AppName.terminalTitle))
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
    private func typeInEditorTerminal(_ text: String, request: String, tty: String, host: DisplayHost, app: String) async -> Typed {
        guard let link = Self.extensionLink(app: app, path: Link.typePath, query: [QueryKey.request: request, QueryKey.tty: tty]) else {
            return Typed(.failed, "the Memnox extension is not in \(host.app ?? "the editor") yet, which the daemon puts in as it starts",
                         hint: .installExtension(app: host.app ?? Self.anEditor))
        }
        await launch(toward: host.app ?? app)
        _ = await open(host)
        try? await Task.sleep(nanoseconds: Self.nanoseconds(Timing.editorSettle))
        guard NSWorkspace.shared.open(link) else { return Typed(.failed, "the editor would not take the Memnox link") }
        let delivered = await Self.extensionDelivery(of: request, resending: link)
        // No window answered at all, which is a window still running the copy from before this memnox.
        if delivered.reason == Self.extensionSilent,
           let again = await retypeAfterRestart(request: request, tty: tty, host: host, app: app) {
            return again.wentIn ? again : Self.unansweredAfterRestart(text, app: host.app ?? Self.anEditor, answered: again)
        }
        // An editor started from a shell hands that shell's terminal to its agent panel too, so a
        // terminal nobody can find in the editor means the session is in the panel, typed into there.
        guard delivered.outcome == .failed, delivered.reason == Self.noEditorTerminal,
              let session = host.conversation
        else { return delivered.withEditorHint(host.app ?? Self.anEditor) }
        // The agent running in front on its terminal means the session is in a terminal, and its panel
        // would open a new conversation instead of following up, so the words wait on the clipboard.
        if TerminalFront.agentInFront(Self.foreground(tty)) {
            diary.note("the \(host.app ?? Self.anEditor) window in front does not hold \(tty), though the agent runs there, so each other window is asked")
            if let found = await inOtherWindows(request: request, tty: tty, host: host, app: app, path: Link.typePath) {
                return found
            }
            if let again = await retypeAfterRestart(request: request, tty: tty, host: host, app: app) {
                return again.wentIn ? again : Self.unansweredAfterRestart(text, app: host.app ?? Self.anEditor, answered: again)
            }
            PromptTyping.leaveOnClipboard(text)
            return Typed(.clipboard, "none of \(host.app ?? Self.anEditor)'s windows answered for the terminal the session runs in, so its extensions may need restarting there")
                .with(hint: .restartExtensions(app: host.app ?? Self.anEditor))
        }
        diary.note("no editor terminal holds \(tty), so typing into the agent panel")
        if delivered.toldFailedFirst {
            diary.note("the Memnox extension in \(host.app ?? "the editor") is older than this memnox; the daemon puts the new one in as it starts, and the window takes it once its extensions restart")
        }
        let typed = await prefillInFront(text, session: session, host: host)
        return Typed(typed.outcome, typed.reason, toldFailedFirst: delivered.toldFailedFirst, hint: typed.hint)
            .withEditorHint(host.app ?? Self.anEditor, older: delivered.toldFailedFirst)
    }

    /// Each other window of the editor brought forward in turn with the request sent again under an id of its own,
    /// since a link reaches only the window in front and one still on an older extension never looks for requests.
    /// Nil when the editor has no other window or none of them holds the terminal.
    private func inOtherWindows(request: String, tty: String, host: DisplayHost, app: String, path: String) async -> Typed? {
        guard let editor = Self.running(host) else { return nil }
        for (index, window) in EditorWindows.others(of: editor).enumerated() {
            guard EditorWindows.raise(window, of: editor),
                  let again = Self.copyOfRequest(request, seenIn: host.app ?? Self.anEditor, attempt: index + 1),
                  let link = Self.extensionLink(app: app, path: path, query: [QueryKey.request: again, QueryKey.tty: tty])
            else { continue }
            try? await Task.sleep(nanoseconds: Self.nanoseconds(Timing.editorSettle))
            guard NSWorkspace.shared.open(link) else { continue }
            let answered = await Self.extensionDelivery(of: again, attempts: Timing.windowAttempts)
            if answered.reason == Self.noEditorTerminal || answered.reason == Self.extensionSilent { continue }
            diary.note("another \(host.app ?? Self.anEditor) window holds \(tty), and it answered \(again)")
            return answered
        }
        return nil
    }

    /// What the person used to be told to do by hand, done where they watch: the editor's extensions restart, so
    /// a copy put in since the window opened is the one answering, and the words go once more under a request of
    /// their own, since the extension answers each request once. Nil when the editor could not be restarted.
    private func retypeAfterRestart(request: String, tty: String, host: DisplayHost, app: String,
                                    path: String = Link.typePath) async -> Typed? {
        guard let editor = Self.running(host), await PromptTyping.restartExtensionHost(in: editor),
              let again = Self.copyOfRequest(request, seenIn: host.app ?? Self.anEditor),
              let link = Self.extensionLink(app: app, path: path, query: [QueryKey.request: again, QueryKey.tty: tty])
        else { return nil }
        diary.note("restarted the extensions in \(host.app ?? Self.anEditor) and sent the words again as \(again)")
        try? await Task.sleep(nanoseconds: Self.nanoseconds(Timing.extensionsRestart))
        guard NSWorkspace.shared.open(link) else { return nil }
        return await Self.extensionDelivery(of: again, resending: link)
    }

    /// The words left on the clipboard once the editor's extensions were restarted and still nothing answered, with
    /// no step for the person, since the one they would have been told to take was just taken.
    private static func unansweredAfterRestart(_ text: String, app: String, answered: Typed) -> Typed {
        PromptTyping.leaveOnClipboard(text)
        // A window that said the terminal is not its own is another window's, so the person hears where to look.
        if answered.reason == noEditorTerminal {
            return Typed(.clipboard, "the \(app) window that answered does not hold the session's terminal, so it is in another \(app) window, whose extensions start with Memnox once it reloads")
        }
        return Typed(.clipboard, "no \(app) window answered for the terminal the session runs in, even after its extensions restarted")
    }

    /// The request written again under an id of its own, unanswered and marked seen, so only the extension acts on
    /// it and the daemon never shows it to the Mac a second time. Nil when the request cannot be read or written.
    private static func copyOfRequest(_ request: String, seenIn editor: String, attempt: Int = 0) -> String? {
        let parts = request.split(separator: Retry.separator)
        guard parts.count == Retry.idParts else { return nil }
        // Each window tried gets an id of its own, so a late answer from one is never read as another's.
        let mark = Retry.marker + (attempt == 0 ? "" : String(attempt))
        let again = [parts[0], parts[1] + mark, parts[2]].joined(separator: String(Retry.separator))
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(Folder.displays)
        let from = folder.appendingPathComponent("\(request).\(Folder.recordExtension)")
        guard let data = try? Data(contentsOf: from),
              var record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        for answered in Retry.answeredFields { record.removeValue(forKey: answered) }
        record[Retry.idField] = again
        record[Retry.seenField] = [Retry.seenApp: editor]
        guard let written = try? JSONSerialization.data(withJSONObject: record) else { return nil }
        let to = folder.appendingPathComponent("\(again).\(Folder.recordExtension)")
        return (try? written.write(to: to, options: .atomic)) == nil ? nil : again
    }

    /// How a request is sent again: its id with a mark the extension's id pattern still takes, and the fields
    /// that say it was answered or claimed taken off.
    private enum Retry {
        static let separator: Character = "_"
        static let idParts = 3
        static let marker = "r"
        static let idField = "id"
        static let seenField = "seen"
        static let seenApp = "app"
        static let answeredFields = ["delivered", "noTerminal", "claimedBy", "seen"]
    }

    /// Every process on the terminal with its state, where `+` marks the one in front; empty when it cannot be read.
    private static func foreground(_ tty: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "stat=,comm=", "-t", tty.replacingOccurrences(of: "/dev/", with: "")]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        process.waitUntilExit()
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    /// Why a tab could not be found, in words the voice can pass on: the agent runs on a terminal
    /// the app does not hold, so sending again would fail the same way.
    private static func noTab(_ app: String) -> String {
        "none of \(app)'s tabs holds that session's terminal, so it may run inside tmux or another app, and sending again would fail the same way"
    }

    /// What a hint calls an editor whose name was never noted.
    private static let anEditor = "your editor"

    /// Said when the extension never wrote back, which an editor window still on an older one does.
    nonisolated fileprivate static let extensionSilent = "the Memnox extension did not answer, so its editor window may need its extensions restarted"

    /// What the Memnox extension says when no integrated terminal in the editor holds the device.
    private static let noEditorTerminal = "no integrated terminal holds its device"

    /// What the extension wrote on the request once it typed it, read from the runtime's own folder.
    private static func extensionDelivery(of request: String, resending link: URL? = nil,
                                          attempts: Int = Timing.deliveryAttempts) async -> Typed {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("\(Folder.displays)/\(request).\(Folder.recordExtension)")
        for attempt in 0..<attempts {
            // The extension ignores a request it already answered, so sending the link again is safe.
            if let link, attempt > 0, attempt % Timing.linkResendEvery == 0 { NSWorkspace.shared.open(link) }
            let record = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(DeliveryRecord.self, from: $0) }
            if let delivered = record?.delivered {
                // An extension from before the hand over answers this as final, and the runtime has already read it.
                let older = delivered.reason == noEditorTerminal
                return delivered.outcome == Delivery.typed.rawValue
                    ? .landed
                    : Typed(.failed, delivered.reason ?? "the extension could not type it", toldFailedFirst: older)
            }
            // A window holding the terminal claimed it, so it is typing there whatever the window the link reached said.
            if record?.noTerminal == true, record?.claimedBy == nil { return Typed(.failed, noEditorTerminal) }
            try? await Task.sleep(nanoseconds: nanoseconds(Timing.deliveryPoll))
        }
        return Typed(.failed, Self.extensionSilent)
    }

    /// Brings the conversation forward and types the words into its message box a key at a time.
    /// The link alone cannot carry them, since the extension refuses a prompt for a conversation already open.
    /// Told what was typed and what the person sent after fixing it, so the words they fixed are learned.
    var corrected: ((String, String) -> Void)?

    func prefill(_ text: String, session: String, host: DisplayHost?) async -> Typed {
        // A chat panel only takes keys with its window in front, so the screen is borrowed for the send and handed back.
        await borrowingScreen { await self.prefillInFront(text, session: session, host: host) }
    }

    private func prefillInFront(_ text: String, session: String, host: DisplayHost?) async -> Typed {
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
        let corrected = corrected
        let typed = await PromptTyping.typeIntoEditor(text, inAppAt: host?.appPath) { corrected?(text, $0) }
        if !typed.wentIn { PromptTyping.leaveOnClipboard(text) }
        return typed
    }

    /// The comet leaves the orb, and the words land as it arrives rather than before it.
    private func launch(toward app: String) async {
        let start = orbFrame?().map { NSPoint(x: $0.midX, y: $0.midY) }
            ?? NSScreen.main.map { NSPoint(x: $0.frame.midX, y: $0.frame.minY + Self.fallbackLaunchHeight) }
        guard let start else { return }
        // The comet flies while the action runs: waiting for it to land cost most of a second every time.
        flight.fly(from: start, toApp: app)
    }

    /// Typed without a newline and then sent on its own, since an agent reads text and Return arriving together as a paste.
    /// A key at a time through iTerm's own scripting, which needs no leave to press keys, so the person
    /// watches it go in either way. One short script per key with the wait in Swift, since a script runs
    /// on the main thread and one holding every key would stop the orb for seconds.
    private func typeThroughITerm(_ text: String, tty: String) async -> Typed {
        let pause = PromptTyping.basePause(for: text.count)
        // Its tab comes forward first, so the person sees the words go in.
        if Self.run(Self.iTermScript(tty)) { try? await Task.sleep(nanoseconds: Self.nanoseconds(Timing.tabSettle)) }
        for character in text {
            guard Self.run(Self.iTermTypeScript(tty, AppleScriptText.quoted(String(character)), newline: false)) else {
                return Typed(.failed, "its iTerm tab closed while it was typing")
            }
            try? await Task.sleep(nanoseconds: Self.nanoseconds(pause))
        }
        try? await Task.sleep(nanoseconds: Self.nanoseconds(Timing.beforeReturn))
        return Self.run(Self.iTermTypeScript(tty, "", newline: true)) ? .landed : Typed(.failed, "its iTerm tab closed before it was sent")
    }

    /// Writes into the iTerm session on this terminal, with Return only when asked, since Return
    /// arriving with the text reads to an agent as a paste.
    private static func iTermTypeScript(_ tty: String, _ words: String, newline: Bool) -> String {
        """
        tell application "iTerm"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                            tell s to write text "\(words)" newline \(newline ? "yes" : "no")
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

    /// A new tab with the line written into it, and iTerm left where it is on screen.
    private static func iTermLaunchBehind(_ line: String) -> String {
        """
        tell application "iTerm"
            if (count of windows) is 0 then
                set w to (create window with default profile)
            else
                set w to current window
                tell w to create tab with default profile
            end if
            tell current session of w to write text "\(line)"
            return true
        end tell
        """
    }

    /// A new Terminal window running the line, which Terminal opens without coming forward.
    private static func terminalLaunchBehind(_ line: String) -> String {
        """
        tell application "Terminal"
            do script "\(line)"
            return true
        end tell
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

    private static func terminalInFront(_ tty: String, marks: [String] = []) -> String {
        let shows = markTest(marks, in: ["history of t"]).map { " or \($0)" } ?? ""
        return """
        tell application "Terminal"
            set t to selected tab of front window
            return ((tty of t) is "\(tty)")\(shows)
        end tell
        """
    }

    /// Editors that bring forward the window on a folder when asked to open it.
    private static let editors = [AppName.code, AppName.cursor, AppName.windsurf, AppName.zed]

    /// Editors whose Claude Code extension opens one conversation by its link.
    private static let conversationEditors = [AppName.code, AppName.cursor, AppName.windsurf]

    private static func iTermScript(_ tty: String, marks: [String] = []) -> String {
        inITerm(tty, marks: marks, first: "activate", "select w\nselect t\nselect s")
    }

    /// Closing the session closes its tab when it is the only one there, which is how iTerm closes a tab.
    /// The Escape key as the character a terminal reads for it.
    private static let escapeCharacter = 27
    /// How an app bundle's folder ends.
    private static let appBundleSuffix = ".app"

    /// The app a session runs in, by the name noted or else its bundle's.
    private static func appName(of host: DisplayHost) -> String? {
        host.app ?? host.appPath.map { URL(fileURLWithPath: $0).lastPathComponent.replacingOccurrences(of: appBundleSuffix, with: "") }
    }

    /// Escape written into the iTerm session on this terminal as a key, so its tab never has to come forward.
    /// The keys as one AppleScript expression of character ids, so no text but the keys can reach the script.
    private static func iTermWriteScript(_ tty: String, _ keys: [TerminalPress], marks: [String] = []) -> String {
        let text = keys.map(\.sequence).joined().unicodeScalars.map { "(character id \($0.value))" }.joined(separator: " & ")
        return inITerm(tty, marks: marks, "tell s to write text (\(text)) newline no")
    }

    private static func iTermEscapeScript(_ tty: String, marks: [String] = []) -> String {
        inITerm(tty, marks: marks, "tell s to write text (character id \(escapeCharacter)) newline no")
    }

    /// Acts on the iTerm session on this terminal as `s`, in tab `t` of window `w`; when none is on it, on
    /// the one session alone that shows a mark, such as the id `memnox run` printed, and on no session when
    /// several do, since keys in the wrong tab would answer for someone else.
    private static func inITerm(_ tty: String, marks: [String], first: String = "", _ action: String) -> String {
        let shows = markTest(marks, in: ["text of s", "name of s"])
        let byMark = shows.map { test in
            """
            set found to 0
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if \(test) then
                            set found to found + 1
                            set fw to w
                            set ft to t
                            set fs to s
                        end if
                    end repeat
                end repeat
            end repeat
            if found is 1 then
                set w to fw
                set t to ft
                set s to fs
                \(action)
                return true
            end if
            """
        } ?? ""
        return """
        tell application "iTerm"
            \(first)
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                            \(action)
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
            \(byMark)
        end tell
        return false
        """
    }

    /// An AppleScript test that any of the places holds any of the marks, or nil with no mark worth looking for.
    private static func markTest(_ marks: [String], in places: [String]) -> String? {
        let worth = marks.filter { $0.count >= Mark.fewestCharacters }.map(AppleScriptText.quoted)
        guard !worth.isEmpty else { return nil }
        return places.flatMap { place in worth.map { "((\(place)) contains \"\($0)\")" } }.joined(separator: " or ")
    }

    /// How long a mark must be before a tab showing it is taken to be the session's, as the runtime counts it.
    private enum Mark {
        static let fewestCharacters = 10
    }

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

    private static func terminalScript(_ tty: String, marks: [String] = []) -> String {
        let shows = markTest(marks, in: ["history of t"])
        let byMark = shows.map { test in
            """
            set found to 0
            repeat with w in windows
                repeat with t in tabs of w
                    if \(test) then
                        set found to found + 1
                        set fw to w
                        set ft to t
                    end if
                end repeat
            end repeat
            if found is 1 then
                set selected of ft to true
                set index of fw to 1
                return true
            end if
            """
        } ?? ""
        return """
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
            \(byMark)
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

    /// The window the brain asked to see, captured with its controls.
    func look(app name: String?) async -> Sight? {
        guard let app = ScreenSight.app(named: name, otherwise: frontApp()) else { return nil }
        return await ScreenSight.look(at: app)
    }

    /// The words in the session's iTerm or Terminal tab, read by the terminal itself, so a question an agent
    /// asks there is read without Screen Recording and never from another app's window.
    func readTab(of host: DisplayHost) async -> Sight? {
        let app = (host.app ?? host.appPath ?? "").lowercased()
        guard let tty = AppleScriptText.device(host.tty) else { return nil }
        let marks = host.marks ?? []
        let (name, source) = app.contains(AppName.iTerm)
            ? (AppName.iTermTitle, Self.inITerm(tty, marks: marks, "return text of s"))
            : app.contains(AppName.terminal) ? (AppName.terminalTitle, Self.terminalText(tty, marks: marks)) : ("", "")
        guard !source.isEmpty, let text = Self.runText(source)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        diary.note("read the \(name) tab on \(tty)")
        return Sight(app: name, window: nil, text: String(text.suffix(Self.mostTabCharacters)))
    }

    /// The end of a tab is where its question is, and this much holds every choice of one.
    private static let mostTabCharacters = 3_000

    /// Terminal's whole history for the tab on this terminal, or the one tab alone showing a mark.
    private static func terminalText(_ tty: String, marks: [String]) -> String {
        let shows = markTest(marks, in: ["history of t"])
        let byMark = shows.map { test in
            """
            set found to 0
            repeat with w in windows
                repeat with t in tabs of w
                    if \(test) then
                        set found to found + 1
                        set ft to t
                    end if
                end repeat
            end repeat
            if found is 1 then return history of ft
            """
        } ?? ""
        return """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then return history of t
                end repeat
            end repeat
            \(byMark)
        end tell
        return ""
        """
    }

    /// The text a script returned, or nil when it failed.
    private static func runText(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { diary.note("could not read the terminal: \(error)") }
        // No tab found answers false, which is not the words of a tab.
        guard let result, ![DescType(typeTrue), DescType(typeFalse), DescType(typeBoolean)].contains(result.descriptorType) else { return nil }
        return result.stringValue
    }

    /// The window an action is aimed at, captured either side of acting without bringing anything forward,
    /// since many actions happen behind the person; nothing at all when its app is not known, rather than
    /// whatever the person happens to be looking at.
    func evidence(of host: DisplayHost?, request: String, at moment: WitnessMoment) async -> Witness? {
        guard let app = host.flatMap({ Self.running($0) }) else { return nil }
        return await ScreenSight.evidence(of: app, request: request, at: moment)
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

private extension Typed {
    /// The editor's own step for an extension that is older than this memnox or never wrote back.
    func withEditorHint(_ app: String, older: Bool = false) -> Typed {
        older || toldFailedFirst || reason == SessionPresenter.extensionSilent ? with(hint: .restartExtensions(app: app)) : self
    }
}
