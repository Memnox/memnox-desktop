import MemnoxVoiceCore
import SwiftUI

/// What stays under Settings: the Settings window's own pages, less the overview, the agents and the apps, which moved to
/// Home, Agents and the MCP Hub.
struct SettingsDestination: View {
    @ObservedObject var models: SettingsModels
    @ObservedObject var menu: MenuModel
    @ObservedObject var setup: SetupModel
    let tab: String?

    var body: some View {
        let page = tab.flatMap(SettingsPage.init(rawValue:)) ?? .account
        SettingsPageColumn(title: page.title, subtitle: page.subtitle) {
            switch page {
            case .account:
                if let account = models.account { AccountPage(account: account, setup: setup) }
            case .permissions: SetupPermissionsCard(model: setup)
            case .connection: SetupMacCard(model: setup)
            case .phones: PhonesPage(menu: menu, setup: setup)
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
