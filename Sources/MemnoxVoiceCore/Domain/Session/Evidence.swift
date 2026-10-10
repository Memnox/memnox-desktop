import Foundation

/// What may be claimed about an action, from what was read back after it: nothing is called done
/// that was not seen, and a send nobody could check is said to be unchecked.
public enum Evidence {
    /// Whether words typed into a target show there once more than they did before, ignoring how the
    /// target wrapped or spaced them, so an identical instruction sent earlier never counts as this one.
    public static func landed(_ text: String, before: String, after: String) -> Bool {
        let needle = squeezed(text)
        guard !needle.isEmpty else { return false }
        return occurrences(of: needle, in: squeezed(after)) > occurrences(of: needle, in: squeezed(before))
    }

    /// The last of the target's text, enough to show on a card as what was seen.
    public static func excerpt(_ text: String, around words: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let probe = squeezed(String(words.prefix(probeLength)))
        let hit = lines.lastIndex { squeezed($0).contains(probe) } ?? max(0, lines.count - 1)
        let start = max(0, hit - excerptContext)
        return lines.isEmpty ? "" : lines[start...hit].joined(separator: "\n")
    }

    /// The line a confirmed proposal earns: done only for what the daemon finished before it answered,
    /// let through for a held call that is still the agent's to run, under way for one still running.
    public static func afterConfirm(_ answer: ProposalAnswer, outcome: String?) -> String {
        guard answer == .confirmed else { return "Very well. I have left it as it was." }
        switch outcome {
        case confirmStarted:
            return "Very well. It is under way, and I will tell you if anything goes wrong."
        case confirmLetThrough:
            return "Very well. I have let it through, and it carries on from here."
        default:
            return "Very well. It is done."
        }
    }

    /// Said by the app itself only when the daemon never heard the result, since the brain says it otherwise.
    public static func unheard(_ outcome: Delivery, otherwise: String) -> String? {
        switch outcome {
        case .verified, .typed:
            return nil
        case .waiting:
            return "I kept it for its next prompt rather than take your window."
        case .clipboard, .notAllowed, .failed:
            return otherwise
        }
    }

    /// The proof as a card shows it: what was checked, then what was seen.
    public static func card(_ proof: Proof) -> String {
        guard let seen = proof.seen, !seen.isEmpty else { return "Checked \(proof.checked)." }
        return "Checked \(proof.checked):\n\(seen)"
    }

    /// The runtime's outcome for a confirmed command still running on its own.
    static let confirmStarted = "started"
    /// The runtime's outcome for a held call a confirmed proposal let through.
    static let confirmLetThrough = "let-through"
    /// Enough of the words to find the line they landed on, short enough that a wrap never splits it.
    private static let probeLength = 24
    /// Lines shown above the one the words landed on, so the card shows where they went.
    private static let excerptContext = 2

    private static func squeezed(_ text: String) -> String {
        String(text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.map(Character.init))
    }

    private static func occurrences(of needle: String, in haystack: String) -> Int {
        var count = 0
        var range = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: needle, range: range) {
            count += 1
            range = found.upperBound..<haystack.endIndex
        }
        return count
    }
}
