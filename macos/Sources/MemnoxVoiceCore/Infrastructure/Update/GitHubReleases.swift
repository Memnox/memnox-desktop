import Foundation

/// The releases of `Memnox/memnox-desktop` on GitHub, read without signing in, as install.sh reads them.
public struct GitHubReleases: ReleaseFeed {
    public static let defaultList = URL(string: "https://api.github.com/repos/Memnox/memnox-desktop/releases?per_page=30")!  // a fixed address that always parses
    private let transport: HttpTransport
    private let list: URL

    public init(transport: HttpTransport, list: URL = GitHubReleases.defaultList) {
        self.transport = transport
        self.list = list
    }

    public func newest() async -> AppRelease? {
        var request = URLRequest(url: list)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, status) = try? await transport.send(request), status == 200 else { return nil }
        return AppRelease.newest(in: data)
    }
}
