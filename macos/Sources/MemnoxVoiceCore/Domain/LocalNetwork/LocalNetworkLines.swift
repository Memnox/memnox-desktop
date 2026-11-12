import Foundation

/// The local network's one line on this Mac, mirrored from shared/tauri-core's local-network-lines.ts.
public enum LocalNetworkLines {
    /// Said on the Phones page while it is on, since pairing then needs nothing beyond the network.
    public static let pairsWithoutAccount =
        "The local network is on, so a phone on the same network can pair with this Mac with no Memnox account."
}
