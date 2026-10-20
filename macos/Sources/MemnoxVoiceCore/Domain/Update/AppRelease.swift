import Foundation

/// A release of the Mac app on GitHub: its version, the disk image and the checksum published beside it.
public struct AppRelease: Equatable, Sendable {
    public let version: String
    public let image: URL
    public let checksum: URL

    public init(version: String, image: URL, checksum: URL) {
        self.version = version
        self.image = image
        self.checksum = checksum
    }

    /// The names `scripts/dmg.sh` gives the image and its checksum, the same in every release.
    public enum Asset {
        public static let image = "Memnox.dmg"
        public static let checksum = "Memnox.dmg.sha256"
    }

    /// The tag `release-app.yml` releases from, `app-v<version>`, which the Mac app is added to.
    private static let tagPrefix = "app-v"

    /// Whether this release is one the app at `running` should move to.
    public func isNewer(than running: String) -> Bool {
        !isAtLeast(running, version)
    }

    /// The newest release carrying the Mac app, from GitHub's list of releases, previews included as install.sh
    /// takes them. A release the Mac image was never added to, a draft, or one without its checksum is passed over.
    public static func newest(in json: Data) -> AppRelease? {
        guard let releases = try? JSONDecoder().decode([Listed].self, from: json) else { return nil }
        let found = releases.compactMap { listed -> AppRelease? in
            guard listed.draft != true, listed.tag_name.hasPrefix(tagPrefix) else { return nil }
            let version = String(listed.tag_name.dropFirst(tagPrefix.count))
            func asset(_ name: String) -> URL? {
                listed.assets.first { $0.name == name }.flatMap { URL(string: $0.browser_download_url) }
            }
            guard !version.isEmpty, let image = asset(Asset.image), let checksum = asset(Asset.checksum) else { return nil }
            return AppRelease(version: version, image: image, checksum: checksum)
        }
        return found.max { !isAtLeast($0.version, $1.version) }
    }

    /// The fields read from one release in GitHub's answer, named as GitHub names them.
    private struct Listed: Decodable {
        let tag_name: String
        let draft: Bool?
        let assets: [Listed.Asset]

        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
    }
}

/// The hex digest a published `.sha256` file holds, as `shasum -a 256` writes it, lowercased; nil when it holds none.
public func publishedDigest(_ text: String) -> String? {
    let digest = text.split(whereSeparator: \.isWhitespace).first.map { $0.lowercased() } ?? ""
    let hex = CharacterSet(charactersIn: "0123456789abcdef")
    guard digest.count == 64, digest.unicodeScalars.allSatisfy(hex.contains) else { return nil }
    return digest
}
