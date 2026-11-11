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

/// A quiet line under Phones.
private struct NetworkLine: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Memnox.Console.sans(Memnox.TextSize.footnote))
            .foregroundStyle(Memnox.Console.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
