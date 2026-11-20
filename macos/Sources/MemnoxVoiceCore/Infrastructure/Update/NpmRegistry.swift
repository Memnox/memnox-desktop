import Foundation

/// The `memnox` package on npm, read without signing in, as the first run's `npm install` reads it.
public struct NpmRegistry: RuntimeFeed {
    public static let defaultLatest = URL(string: "https://registry.npmjs.org/memnox/latest")!  // a fixed address that always parses
    private let transport: HttpTransport
    private let latest: URL

    /// The system's own transport unless a test hands over a scripted one; this folder is the one place a feed is read.
    public init(transport: HttpTransport = URLSessionTransport(), latest: URL = NpmRegistry.defaultLatest) {
        self.transport = transport
        self.latest = latest
    }

    public func newest() async -> String? {
        guard let data = await read(latest) else { return nil }
        return RuntimeRelease.newest(in: data)
    }

    /// Read from the version's own entry beside `latest`; only a plain version is ever put in the address.
    public func deprecation(of version: String) async -> String? {
        guard RuntimeRelease.isPlainVersion(version),
              let data = await read(latest.deletingLastPathComponent().appendingPathComponent(version)) else { return nil }
        return RuntimeRelease.deprecation(in: data)
    }

    private func read(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, status) = try? await transport.send(request), status == 200 else { return nil }
        return data
    }
}
