import CryptoKit
import Foundation

/// The SHA-256 of a downloaded disk image, read a piece at a time, since the image carries the runtime and the voice.
public enum ImageChecksum {
    private static let chunk = 1 << 20

    /// The lowercase hex digest of the file, as `shasum -a 256` prints it.
    public static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: chunk), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Whether the file is the one the published checksum names.
    public static func matches(_ file: URL, published: String) -> Bool {
        guard let expected = publishedDigest(published), let actual = try? sha256(of: file) else { return false }
        return expected == actual
    }
}
