import MemnoxVoiceCore
import SwiftUI

/// The local network for the window, redrawn whenever the runtime's answer changes it.
@MainActor
final class NetworkScreen: ObservableObject {
    let network: LocalNetwork
    /// Bumped when the status changes, so every view reading it is drawn again.
    @Published private(set) var tick = 0

    init(network: LocalNetwork) {
        self.network = network
        network.changed = { [weak self] in
            Task { @MainActor [weak self] in self?.tick += 1 }
        }
    }
}

/// Whether paired phones reach this Mac over the network it shares with them. The runtime decides: turning it off is
/// done at once, and turning it on is only proposed, holding once signed with Touch ID on the island.
struct NetworkPage: View {
    @ObservedObject var screen: NetworkScreen
    @State private var note: (text: String, alert: Bool)?

    var body: some View {
        content.task { await screen.network.refresh() }
    }

    @ViewBuilder private var content: some View {
        let network = screen.network
        if let lan = network.status {
            SettingsCard(title: "Local network") {
                NetworkLine(LocalNetworkLines.what)
                NetworkLine(LocalNetworkLines.bounds)
                SwitchRow(symbol: "wifi", title: "Reach this Mac on the local network",
                          detail: LocalNetworkLines.switchCaption(on: lan.on),
                          isOn: Binding(get: { lan.on }, set: { flip($0) }))
                    .disabled(network.busy)
                if let note {
                    Text(note.text)
                        .font(Memnox.sans(Memnox.TextSize.footnote))
                        .foregroundStyle(note.alert ? Memnox.Palette.destructive : Memnox.Palette.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                SettingsDivider(full: true)
                SettingsRow(symbol: "wifi", title: "Status", caption: LocalNetworkLines.statusLine(lan))
                SettingsRow(symbol: "iphone", title: "Phones on it", caption: LocalNetworkLines.phonesLine(lan))
            }
        } else if network.unreadable {
            ReadFailed(what: "the local network") { Task { await network.refresh() } }
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private func flip(_ on: Bool) {
        let network = screen.network
        Task {
            switch await network.set(on: on) {
            case .failed(let why): note = (why, true)
            case .proposed: note = (LocalNetworkLines.waitsLine, false)
            case .done: note = nil
            }
        }
    }
}

/// Said under Phones while the local network is on: pairing then needs no account.
struct PairsWithoutAccountLine: View {
    @ObservedObject var screen: NetworkScreen

    var body: some View {
        Group {
            if screen.network.status?.on == true { NetworkLine(LocalNetworkLines.pairsWithoutAccount) }
        }
        // Only to say this; a runtime without the local network leaves it unsaid.
        .task { await screen.network.refresh() }
    }
}

/// A quiet line of the network page.
private struct NetworkLine: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Memnox.sans(Memnox.TextSize.footnote))
            .foregroundStyle(Memnox.Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
