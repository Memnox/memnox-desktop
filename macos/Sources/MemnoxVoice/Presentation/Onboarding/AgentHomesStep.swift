import AppKit
import SwiftUI

/// Where the person runs their agents and what each of those apps still needs, so starting a session, following up
/// and typing work there from the first try rather than failing later with a reason nobody saw coming.
@MainActor
final class AgentHomesModel: ObservableObject {
    static let shared = AgentHomesModel()

    /// The apps the person said they use, kept so Settings shows the same ones.
    static let chosenKey = "agentHomes"
    /// The editors whose chat link the person saw open, which no file on disk records.
    static let chatKey = "agentHomesChatOpened"

    @Published private(set) var chosen: Set<AgentHome>
    @Published private(set) var chatOpened: Set<AgentHome>
    @Published private(set) var automation: [AgentHome: Automation] = [:]
    /// The editors whose chat link was just opened, waiting on the person to say whether it came up.
    @Published private(set) var tried: Set<AgentHome> = []
    @Published private(set) var asking: AgentHome?
    /// Bumped on each look, so checks read off disk and the running apps draw again.
    @Published private(set) var looked = 0

    /// Long enough for a terminal just opened to take an Apple Event.
    private static let launchSettle: TimeInterval = 1.5

    var installed: [AgentHome] { AgentHome.allCases.filter(\.installed) }

    private init() {
        let defaults = UserDefaults.standard
        let saved = defaults.stringArray(forKey: Self.chosenKey).map { Set($0.compactMap(AgentHome.init(rawValue:))) }
        // Until they answer, every one on this Mac is offered ticked, since most people use what they installed.
        chosen = saved ?? Set(AgentHome.allCases.filter(\.installed))
        chatOpened = Set((defaults.stringArray(forKey: Self.chatKey) ?? []).compactMap(AgentHome.init(rawValue:)))
    }

    func toggle(_ home: AgentHome) {
        if chosen.contains(home) { chosen.remove(home) } else { chosen.insert(home) }
        UserDefaults.standard.set(chosen.map(\.rawValue), forKey: Self.chosenKey)
    }

    /// Reads every check again without asking anything, which the step does every couple of seconds while it shows.
    func look() async {
        for home in chosen where !home.isEditor {
            automation[home] = await Automation.of(home.bundleID, ask: false)
        }
        looked += 1
    }

    /// Puts up macOS's own question for a terminal, opening it first since only a running app can be asked about.
    func allowAutomation(_ home: AgentHome) async {
        asking = home
        defer { asking = nil }
        if home.running == nil, let app = home.app {
            _ = try? await NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
            try? await Task.sleep(nanoseconds: UInt64(Self.launchSettle * 1_000_000_000))
        }
        automation[home] = await Automation.of(home.bundleID, ask: true)
    }

    /// Opens Claude Code's chat through the same link a follow up uses, so the editor asks its one question now.
    func tryChat(_ home: AgentHome) {
        guard let link = home.claudeChatLink else { return }
        NSWorkspace.shared.open(link)
        tried.insert(home)
    }

    func chatCameUp(_ home: AgentHome, _ yes: Bool) {
        tried.remove(home)
        guard yes else { return }
        chatOpened.insert(home)
        UserDefaults.standard.set(chatOpened.map(\.rawValue), forKey: Self.chatKey)
    }

    func open(_ url: URL?) {
        if let url { NSWorkspace.shared.open(url) }
    }

    func bringForward(_ home: AgentHome) {
        if let running = home.running {
            running.activate()
        } else if let app = home.app {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: What each app still needs

    func hasMemnoxExtension(_ home: AgentHome) -> Bool { home.extensionAdded(AgentHomeIDs.memnoxTerminals) != nil }

    func hasClaudeCode(_ home: AgentHome) -> Bool { home.extensionAdded(AgentHomeIDs.claudeCodeFolder) != nil }

    /// Open since before the Memnox extension went in, so the extension is not running in it until it reloads.
    func needsReload(_ home: AgentHome) -> Bool {
        guard let added = home.extensionAdded(AgentHomeIDs.memnoxTerminals),
              let launched = home.running?.launchDate else { return false }
        return launched < added
    }

    var mayType: Bool { AXIsProcessTrusted() }

    /// Whether everything the app needs is in, for its tick beside the name.
    func ready(_ home: AgentHome) -> Bool {
        if home.isEditor {
            let chat = !hasClaudeCode(home) || chatOpened.contains(home)
            return hasMemnoxExtension(home) && !needsReload(home) && chat && mayType
        }
        return automation[home] == .allowed && mayType
    }
}

/// The step that asks where the agents run, then walks each chosen app through what it needs, one row at a time.
struct AgentHomesStep: View {
    @ObservedObject var flow: OnboardingFlow

    var body: some View {
        StepTitle(title: "Where you run your agents",
                  detail: "Pick every app you use. Each needs a step or two so Memnox can start sessions, follow up and type there for you.")
        Next(title: "Continue", flow: flow)
        AgentHomesSetup()
    }
}

/// The picker and each chosen app's checklist, shared by the first run and Settings.
struct AgentHomesSetup: View {
    @ObservedObject private var model = AgentHomesModel.shared

    private enum Timing {
        /// Often enough that a reload or a switch flipped in System Settings ticks without pressing anything.
        static let lookEvery: TimeInterval = 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xLarge) {
            KitCard(symbol: "macwindow.on.rectangle", title: "Your apps", detail: picked) {
                if model.installed.isEmpty {
                    KitRow(symbol: "questionmark.app", title: "No editor or terminal found",
                           detail: "Memnox works with VS Code, Cursor, Windsurf, iTerm and Terminal.") { EmptyView() }
                } else {
                    AgentHomePicker(model: model)
                }
            }
            ForEach(model.installed.filter(model.chosen.contains)) { home in
                AgentHomeCard(model: model, home: home)
            }
        }
        .task {
            while !Task.isCancelled {
                await model.look()
                try? await Task.sleep(nanoseconds: UInt64(Timing.lookEvery * 1_000_000_000))
            }
        }
    }

    private var picked: String {
        let ready = model.installed.filter { model.chosen.contains($0) && model.ready($0) }.count
        let chosen = model.installed.filter(model.chosen.contains).count
        if chosen == 0 { return "Tap the ones you run Claude Code, Codex or Cursor in." }
        return ready == chosen ? "All set in every app you picked." : "\(ready) of \(chosen) ready."
    }
}

/// Every editor and terminal on this Mac as a tile with its own icon, ticked when the person uses it.
private struct AgentHomePicker: View {
    @ObservedObject var model: AgentHomesModel

    private enum Layout {
        static let iconSide: CGFloat = 36
        static let tileWidth: CGFloat = 96
        static let radius: CGFloat = 14
        static let chosenEdge: CGFloat = 2
        static let restingInk = 0.06
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Layout.tileWidth), spacing: Memnox.Spacing.medium)],
                  alignment: .leading, spacing: Memnox.Spacing.medium) {
            ForEach(model.installed) { home in tile(home) }
        }
        .padding(.vertical, Memnox.Spacing.regular)
    }

    private func tile(_ home: AgentHome) -> some View {
        let chosen = model.chosen.contains(home)
        let shape = RoundedRectangle(cornerRadius: Layout.radius, style: .continuous)
        return Button { withAnimation(.snappy) { model.toggle(home) } } label: {
            VStack(spacing: Memnox.Spacing.small) {
                if let app = home.app {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                        .resizable()
                        .frame(width: Layout.iconSide, height: Layout.iconSide)
                }
                Text(home.name)
                    .font(Memnox.sans(Memnox.TextSize.footnote, .semibold))
                    .foregroundStyle(Memnox.Palette.ink)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Memnox.Spacing.medium)
            .background(shape.fill(Memnox.ink(Layout.restingInk)))
            .overlay(shape.strokeBorder(chosen ? Memnox.Palette.primary : Color.clear, lineWidth: Layout.chosenEdge))
            .overlay(alignment: .topTrailing) {
                if chosen {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Memnox.Palette.primary)
                        .padding(Memnox.Spacing.small)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(PressableStyle())
        .pointingHand()
        .accessibilityLabel(home.name)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityHint(chosen ? "Memnox sets this app up" : "Memnox leaves this app alone")
    }
}

/// One app's checklist: for an editor the extension, a reload, the chat link and typing; for a terminal its tabs.
private struct AgentHomeCard: View {
    @ObservedObject var model: AgentHomesModel
    let home: AgentHome

    var body: some View {
        let _ = model.looked
        KitCard(symbol: home.isEditor ? "chevron.left.forwardslash.chevron.right" : "terminal",
                title: home.name, detail: model.ready(home) ? "Ready." : summary) {
            if home.isEditor { editorRows } else { terminalRows }
        }
    }

    private var summary: String {
        home.isEditor
            ? "So Memnox can start a session, follow up in its chat and reach the terminal a session runs in."
            : "So Memnox can find the tab a session runs in, type your follow up there and read it back."
    }

    @ViewBuilder private var editorRows: some View {
        KitRow(symbol: "puzzlepiece.extension", title: "Memnox extension",
               detail: model.hasMemnoxExtension(home)
                   ? "In, so your voice reaches the terminal a session runs in."
                   : "The Memnox service puts it in on its own once it is running.") {
            if model.hasMemnoxExtension(home) { CheckBox(state: .done) } else { ProgressView().controlSize(.small) }
        }
        if model.needsReload(home) {
            KitDivider()
            KitRow(symbol: "arrow.clockwise", title: "Reload \(home.name)",
                   detail: "It was open before the extension went in. In \(home.name), press \u{2318}\u{21E7}P, type Reload Window and press Return.") {
                Button("Show \(home.name)") { model.bringForward(home) }.buttonStyle(KitButton(kind: .primary))
            }
        }
        KitDivider()
        chatRow
        KitDivider()
        KitRow(symbol: "keyboard", title: "Type follow ups",
               detail: model.mayType
                   ? "Memnox types into its chat and checks the words landed before it presses Return."
                   : "Allow Accessibility on the step before, so Memnox can type into \(home.name).") {
            CheckBox(state: model.mayType ? .done : .needs("Accessibility"))
        }
    }

    /// Claude Code's chat, opened by the link every follow up uses, which the editor asks about the first time.
    @ViewBuilder private var chatRow: some View {
        if !model.hasClaudeCode(home) {
            KitRow(symbol: "bubble.left.and.text.bubble.right", title: "Claude Code in \(home.name)",
                   detail: "Add the Claude Code extension, so Memnox can start sessions in its chat and follow up there.") {
                Button("Get it") { model.open(home.claudeExtensionPage) }.buttonStyle(KitButton(kind: .secondary))
            }
        } else if model.tried.contains(home) {
            KitRow(symbol: "bubble.left.and.text.bubble.right", title: "Did Claude Code's chat open?",
                   detail: "If \(home.name) asked whether Claude Code may open the link, tick Don't ask again, then press Open.") {
                HStack(spacing: Memnox.Spacing.small) {
                    Button("Not yet") { model.chatCameUp(home, false) }.buttonStyle(KitButton(kind: .secondary))
                    Button("It opened") { model.chatCameUp(home, true) }.buttonStyle(KitButton(kind: .primary))
                }
            }
        } else {
            KitRow(symbol: "bubble.left.and.text.bubble.right", title: "Open chats from Memnox",
                   detail: model.chatOpened.contains(home)
                       ? "Memnox opens the Claude Code chat a session runs in, and starts new ones there."
                       : "\(home.name) asks once before it lets a link open Claude Code. Try it now so it never asks mid task.") {
                if model.chatOpened.contains(home) {
                    CheckBox(state: .done)
                } else {
                    Button("Try it") { model.tryChat(home) }.buttonStyle(KitButton(kind: .primary))
                }
            }
        }
    }

    @ViewBuilder private var terminalRows: some View {
        let state = model.automation[home] ?? .notAsked
        KitRow(symbol: "rectangle.stack", title: "Find its tabs",
               detail: terminalDetail(state)) {
            switch state {
            case .allowed:
                CheckBox(state: .done)
            case .denied:
                Button("Open Settings") { model.open(Self.automationPane) }.buttonStyle(KitButton(kind: .secondary))
            case .notAsked, .notRunning:
                Button("Allow") { Task { await model.allowAutomation(home) } }
                    .buttonStyle(KitButton(kind: .primary))
                    .disabled(model.asking != nil)
            }
        }
        KitDivider()
        KitRow(symbol: "keyboard", title: "Type follow ups",
               detail: model.mayType ? "Memnox types into the agent's prompt and reads the tab back." : "Allow Accessibility on the step before.") {
            CheckBox(state: model.mayType ? .done : .needs("Accessibility"))
        }
    }

    private func terminalDetail(_ state: Automation) -> String {
        switch state {
        case .allowed: return "Memnox brings the session's own tab forward and types into it."
        case .denied: return "Turned off. Switch Memnox on for \(home.name) under Privacy and Security, Automation."
        case .notAsked: return "macOS asks once whether Memnox may control \(home.name). Press Allow, then OK."
        case .notRunning: return "\(home.name) opens for a moment, since macOS can only ask about an app that is running."
        }
    }

    private static let automationPane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
}
