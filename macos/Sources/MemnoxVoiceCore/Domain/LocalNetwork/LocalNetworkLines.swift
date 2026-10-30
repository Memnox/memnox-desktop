import Foundation

/// How a press on the switch ended: done at once, proposed and waiting for a signature, or refused.
public enum LanOutcome: Equatable, Sendable {
    case done
    case proposed(id: String)
    case failed(String)
}

/// The words of the Local network page, mirrored from shared/tauri-core's local-network-lines.ts with this Mac and
/// Touch ID named.
public enum LocalNetworkLines {
    /// What the local network does, said before the switch so nobody turns on what they cannot name.
    public static let what =
        "Lets your paired phones reach this Mac straight over the network you share, rather than through the relay. The conversation is encrypted end to end the same way either way."

    /// Where it listens and that it starts off, which the card says whether it is on or not.
    public static let bounds =
        "It stays off until you turn it on, and it only ever listens on a private address, such as your home or office network, never a public one."

    /// Said on the Phones page while it is on, since pairing then needs nothing beyond the network.
    public static let pairsWithoutAccount =
        "The local network is on, so a phone on the same network can pair with this Mac with no Memnox account."

    /// The switch's caption: turning off narrows who reaches this Mac, so only turning on asks for Touch ID.
    public static func switchCaption(on: Bool) -> String {
        on ? "Turn off to stop it at once" : "Touch ID to turn on"
    }

    /// Where it stands, in a sentence: off, on with nothing listening, or listening and where.
    public static func statusLine(_ lan: LanStatus) -> String {
        if !lan.on { return "Off. Your phones reach this Mac through the relay." }
        if !lan.listening || lan.addresses.isEmpty {
            return "On, but this Mac has no private network address right now, so nothing is listening."
        }
        let places = lan.port.map { port in lan.addresses.map { "\($0):\(port)" } } ?? lan.addresses
        let announced = lan.advertised ? ", announced to phones nearby under a name that says nothing about this Mac" : ""
        return "Listening on \(places.joined(separator: ", "))\(announced)."
    }

    /// Which paired phones are connected over it now, by name.
    public static func phonesLine(_ lan: LanStatus) -> String {
        let names = lan.reachable.map(\.name)
        guard let last = names.last else { return lan.on ? "No phone is connected over it now." : "No phone is connected over it." }
        let said = names.count == 1 ? last : "\(names.dropLast().joined(separator: ", ")) and \(last)"
        return "\(said) \(names.count == 1 ? "is" : "are") connected over it now."
    }

    /// Said once turning it on was proposed: nothing listens until the person signs it.
    public static let waitsLine = "Nothing is listening yet. Turning it on waits for your signature with Touch ID on the island."
}
