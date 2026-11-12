import Foundation

/// The newest Memnox service published to npm, the same package the first run installs as `memnox@latest`.
public enum RuntimeRelease {
    /// The version in the registry's answer for `memnox/latest`, or nil for an answer that names none.
    public static func newest(in json: Data) -> String? {
        guard let answer = try? JSONDecoder().decode(Listed.self, from: json) else { return nil }
        let numbers = answer.version.split(separator: ".").prefix(Self.parts)
        guard numbers.count == Self.parts, numbers.dropLast().allSatisfy({ Int($0) != nil }),
              numbers.last?.first?.isNumber == true else { return nil }
        return answer.version
    }

    /// Major, minor and patch, which every published version carries.
    private static let parts = 3

    /// Whether the version on offer is one the service at `running` should move to.
    public static func isNewer(_ version: String, than running: String) -> Bool {
        !isAtLeast(running, version)
    }

    private struct Listed: Decodable {
        let version: String
    }
}

/// The words the notch says about a newer Memnox service.
public enum RuntimeUpdateLines {
    public static func ready(_ version: String) -> String { "Memnox service \(version) is ready" }
    public static func updating(_ version: String) -> String { "Updating the Memnox service to \(version)" }
    public static func help(_ version: String) -> String { "Update the Memnox service to \(version) in place" }
    public static let later = "Not this version"
}
