import MemnoxVoiceCore
import SwiftUI

/// What stays under Settings: the Settings window's own pages, less the overview, the agents and the apps, which moved to
/// Home, Agents and the MCP Hub.
struct SettingsDestination: View {
    @ObservedObject var models: SettingsModels
    @ObservedObject var menu: MenuModel
    @ObservedObject var setup: SetupModel
    let tab: String?
    /// The setup sealed under a passphrase and put back once signed, nil until the app wires it.
    let backup: Backup?
    /// Whether paired phones reach this Mac over the local network, nil until the app wires it.
    let network: NetworkScreen?

    /// The Backup page is the window's own, so it has no page in the Settings window to borrow.
    static let backupTab = "backup"
    /// So is Local network.
    static let networkTab = "network"

    var body: some View {
        if tab == Self.backupTab {
            SettingsPageColumn(title: "Backup",
                               subtitle: "Your rules, hubs, skills, projects and memory, sealed under a passphrase and put back once you sign.") {
                if let backup { BackupPage(backup: backup) }
            }
        } else if tab == Self.networkTab {
            SettingsPageColumn(title: "Local network",
                               subtitle: "Reach this Mac over the network you share, rather than through the relay.") {
                if let network { NetworkPage(screen: network) }
            }
        } else {
            page
        }
    }

    @ViewBuilder private var page: some View {
        let page = tab.flatMap(SettingsPage.init(rawValue:)) ?? .account
        SettingsPageColumn(title: page.title, subtitle: page.subtitle) {
            switch page {
            case .account:
                if let account = models.account { AccountPage(account: account, setup: setup) }
            case .permissions: SetupPermissionsCard(model: setup)
            case .connection: SetupMacCard(model: setup)
            case .phones:
                PhonesPage(menu: menu, setup: setup)
                if let network { PairsWithoutAccountLine(screen: network) }
            case .appearance: AppearancePage()
            case .voice: VoicePage(menu: menu, setup: setup)
            case .listening: ListeningPage(menu: menu, setup: setup)
            case .dictation:
                if let dictations = models.dictations { DictationPage(store: dictations) }
            case .help: HelpPage(menu: menu)
            // These moved to destinations of their own, so a stale tab naming one lands on Account instead.
            case .overview, .tools, .apps:
                if let account = models.account { AccountPage(account: account, setup: setup) }
            }
        }
    }
}
