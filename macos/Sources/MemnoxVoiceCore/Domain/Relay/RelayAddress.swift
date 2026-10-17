import Foundation

/// The relay's HTTP routes beside its WebSocket, read from the one relay URL the QR carries.
public enum RelayAddress {
    /// The phone's push route, authenticated with its rly_ token.
    static let pushPath = "/v1/relay/push"
    private static let secureSocket = "wss"
    private static let plainSocket = "ws"
    private static let secureWeb = "https"
    private static let plainWeb = "http"

    /// wss://host/v1/relay becomes https://host/v1/relay/push, and ws becomes http for a local relay in tests.
    public static func pushURL(from relay: URL) -> URL? {
        guard var parts = URLComponents(url: relay, resolvingAgainstBaseURL: false) else { return nil }
        switch parts.scheme {
        case secureSocket: parts.scheme = secureWeb
        case plainSocket: parts.scheme = plainWeb
        default: return nil
        }
        parts.path = pushPath
        parts.query = nil
        return parts.url
    }
}
