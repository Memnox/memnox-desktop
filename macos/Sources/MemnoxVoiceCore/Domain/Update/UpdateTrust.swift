import Foundation

/// How an app on disk is signed, as the updater reads it: whether its seal still holds, and the Apple team behind it.
public struct AppSignature: Equatable, Sendable {
    /// False when any file was changed after signing, or when there is no signature at all.
    public let isIntact: Bool
    /// The Apple Developer team that signed it; nil for an ad hoc or a local signature, which no team stands behind.
    public let team: String?

    public init(isIntact: Bool, team: String?) {
        self.isIntact = isIntact
        self.team = team?.nilIfBlank
    }
}

/// Whether a downloaded Memnox may replace the running one. The checksum sits in the same release as the image,
/// so whoever could swap one could swap both; the Apple team's signature is the part a stolen token cannot forge.
public enum UpdateTrust {
    public enum Verdict: Equatable, Sendable {
        case trusted
        /// A file in the new app changed after it was signed, or it carries no signature.
        case broken
        /// Signed, but not by the team that signs Memnox.
        case strangerTeam(expected: String, found: String?)
    }

    /// The team the new app must carry: the one this app is signed by, or, for a preview signed before Memnox had a
    /// Developer ID, the one its build named. A build with neither has nothing to hold the new one to but its seal.
    public static func expectedTeam(running: AppSignature, pinned: String?) -> String? {
        running.team ?? pinned?.nilIfBlank
    }

    public static func verdict(for candidate: AppSignature, running: AppSignature, pinned: String?) -> Verdict {
        guard candidate.isIntact else { return .broken }
        guard let expected = expectedTeam(running: running, pinned: pinned) else { return .trusted }
        return candidate.team == expected ? .trusted : .strangerTeam(expected: expected, found: candidate.team)
    }
}

private extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}
