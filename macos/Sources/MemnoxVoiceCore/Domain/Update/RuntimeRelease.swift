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

    /// The reason `npm deprecate` left on one version's entry; npm writes it as a string, and an empty one lifts it.
    public static func deprecation(in json: Data) -> String? {
        guard let entry = try? JSONDecoder().decode(Entry.self, from: json),
              let reason = entry.deprecated?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty else { return nil }
        return reason
    }

    /// Digits and dots only, so a version read from the daemon can never steer the registry address elsewhere.
    public static func isPlainVersion(_ version: String) -> Bool {
        let numbers = version.split(separator: ".", omittingEmptySubsequences: false)
        return numbers.count == Self.parts && numbers.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
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

    /// A version's own entry, where npm keeps `deprecated` only while the version is withdrawn.
    private struct Entry: Decodable {
        let deprecated: String?
    }
}

/// The words the notch says about a newer Memnox service.
public enum RuntimeUpdateLines {
    public static func ready(_ version: String) -> String { "Memnox service \(version) is ready" }
    public static func updating(_ version: String) -> String { "Updating the Memnox service to \(version)" }
    public static func help(_ version: String) -> String { "Update the Memnox service to \(version) in place" }
    public static let later = "Not this version"
    /// Said as the update starts unasked, since the person never pressed anything.
    public static func withdrawn(_ running: String, _ version: String) -> String {
        "Memnox service \(running) was withdrawn for a fault, so it is updating to \(version)"
    }
}
