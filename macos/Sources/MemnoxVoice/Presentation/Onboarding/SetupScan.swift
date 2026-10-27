import MemnoxVoiceCore
import SwiftUI

/// The first run's last word: once setup closes, the full screen scan the agents can ask for goes up with this Mac's
/// agents, the voice says what Memnox found across the agents, skills, servers, memory and apps, the scan stays until
/// that is said, and closing it opens the Memnox window on Home where the next steps wait. It asks the runtime's own live scan,
/// and falls back to the cards the app already reads from a daemon too old for it.
@MainActor
final class SetupScan {
    static let shared = SetupScan()

    private let panel = ScanPanel()

    /// The full screen scan's own title, the same words it heads every scan with.
    private static let title = "Your agents"

    private init() {}

    func run(_ setup: SetupModel) async {
        let shell = AppWindow.shared.shell
        let tools = SettingsWindow.shared.menu?.tools
        await tools?.refreshed()
        await shell.agents?.agents.refresh()
        await shell.hub?.hub.refresh()
        await shell.skills?.skills.refresh()
        await shell.memory?.memory.refreshSources()
        // The runtime's own live scan first, which counts tools, sessions and capabilities; the cards only for a daemon too old for it.
        let scanned = await shell.agents?.agents.scan()
        let agents = shell.agents?.agents.agents ?? []
        let tally = ScanLines.tally(agents: agents, scanned: scanned, skills: shell.skills?.skills.hub, servers: shell.hub?.hub.hub,
                                    sources: shell.memory?.memory.sources ?? [], apps: tools?.yourApps ?? [])
        // Home opens whichever way the scan goes, and straight away when there is no agent to draw.
        panel.closed = { Self.openHome() }
        let nodes = scanned?.agents ?? ScanLines.nodes(agents)
        guard !nodes.isEmpty else {
            panel.closed = nil
            Self.openHome()
            return
        }
        // Up until the voice has finished explaining it, and quiet the moment the person closes it.
        panel.voiceStarted = { [weak setup] in setup?.voiceSounding ?? false }
        panel.interrupted = { [weak setup] in setup?.stopGuide() }
        panel.present(nodes, title: Self.title, sessionsKnown: scanned != nil)
        if let scanned, scanned.capabilities.total == nil { landCount(shell.agents?.agents) }
        await setup.narrate(FirstRunGuide.scanned(tally))
        panel.narrationFinished()
    }

    /// While the runtime counts the servers it had never asked, asks again a few times so the figures land in place.
    private func landCount(_ agents: Agents?) {
        guard let agents else { return }
        Task { [panel] in
            for _ in 0..<Self.recounts {
                try? await Task.sleep(nanoseconds: UInt64(Self.recountEvery * Self.nanosecondsPerSecond))
                guard let again = await agents.scan(), panel.recount(again.agents) else { return }
                if again.capabilities.total != nil { return }
            }
        }
    }

    /// Starting every server to ask it takes some seconds, so a few asks a little apart cover it without polling forever.
    private static let recounts = 6
    private static let recountEvery: TimeInterval = 3
    private static let nanosecondsPerSecond: TimeInterval = 1_000_000_000

    private static func openHome() {
        SettingsWindow.shared.show()
        AppWindow.shared.shell.go(WindowRoute(.home))
    }
}
