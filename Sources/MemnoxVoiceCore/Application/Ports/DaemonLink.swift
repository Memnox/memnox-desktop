import Foundation

/// How the app reaches the daemon. A protocol, so everything above it is tested without a socket.
public protocol DaemonLink: AnyObject {
    /// Every line the daemon writes back for one request, until it closes or the caller stops.
    func stream(_ request: DaemonRequest) -> AsyncThrowingStream<DaemonResponse, Error>
}

extension DaemonLink {
    /// The first answer, for the methods that answer once.
    public func request(_ request: DaemonRequest) async throws -> DaemonResponse {
        for try await response in stream(request) { return response }
        throw ProtocolError.disconnected
    }
}
