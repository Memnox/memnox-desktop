import MemnoxVoiceCore
import SwiftUI

/// What stays under Settings: the Settings window's own pages, less the overview, the agents, the apps and the
/// connection, which moved to Home, Agents, Connectors and Machines.
struct SettingsDestination: View {
    @ObservedObject var models: SettingsModels
    @ObservedObject var menu: MenuModel
    @ObservedObject var setup: SetupModel
    let tab: String?
    /// Whether paired phones reach this Mac over the local network, which Phones says, nil until the app wires it.
    let network: NetworkScreen?

    var body: some View { page }

    @ViewBuilder private var page: some View {
        let page = tab.flatMap(SettingsPage.init(rawValue:)) ?? .account
        SettingsPageColumn(title: page.title, subtitle: page.subtitle) {
            switch page {
            case .account:
                if let account = models.account { AccountPage(account: account, setup: setup) }
            case .permissions: SetupPermissionsCard(model: setup)
            case .phones:
                PhonesPage(menu: menu, setup: setup)
                if let network { PairsWithoutAccountLine(screen: network) }
            case .appearance: AppearancePage()
            case .voice: VoicePage(menu: menu, setup: setup)
            case .listening: ListeningPage(menu: menu, setup: setup)
            case .dictation:
                if let dictations = models.dictations { DictationPage(store: dictations) }
            case .help: HelpPage(menu: menu, setup: setup)
            // These moved to pages of their own, so a stale tab naming one lands on Account instead.
            case .overview, .tools, .apps, .connection:
                if let account = models.account { AccountPage(account: account, setup: setup) }
            }
        }
    }
}
