import Foundation

/// The tabs of Protection settings, in the console's order for the pages its sidebar row lights.
public enum ProtectionTab: String, CaseIterable, Sendable {
    case readyMade
    case allRules
    case autonomy

    public var title: String {
        switch self {
        case .readyMade: "Ready-made rules"
        case .allRules: "All rules"
        case .autonomy: "Autonomy"
        }
    }

    /// The tabs drawn. Autonomy is left off for now, since Ready to hand over on Home already offers the same.
    public static let shown: [ProtectionTab] = [.readyMade, .allRules]
}

/// The words of Protection settings, the console's own except where this computer signs in place of an admin
/// approving, and the same as Windows and Linux say them. Team and fleet sentences are left out, since one machine has
/// neither.
public enum ProtectionLines {
    // Ready-made rules, as the console's library and its choices say them.
    public static func readyIntro(keyTitle: String) -> String {
        "Rules written for you. Choose Allow, Ask or Deny on one; it holds once you confirm it with \(keyTitle)."
    }
    public static let search = "Search by tool, command or what it protects: kubectl, refund, secrets"
    public static let searchLabel = "Search ready-made rules"
    public static let allRules = "All rules"
    public static let starter = "Add the starter set"
    /// Under one category, the console's own words for taking every suggestion there.
    public static let everySuggestion = "Use every suggestion"
    public static let noneMatchTitle = "No ready-made rule matches that."
    public static let noneMatchDetail = "Propose your own under All rules."
    /// The console's one sentence, which an empty state splits into its title and the line under it.
    public static var noneMatch: String { "\(noneMatchTitle) \(noneMatchDetail)" }
    public static let notAdded = "Not added"
    public static let suggested = "Suggested"
    public static let changed = "Changed"

    /// "In force as ask", the badge of a ready-made rule that holds.
    public static func inForceAs(_ effect: RuleEffect) -> String {
        "In force as \(StudioLines.words(effect).title.lowercased())"
    }

    // The bar and the review, as the console's choices save.
    public static let notSaved = "Not saved yet"
    public static let undo = "Undo"
    public static let review = "Review and save"
    public static let previewed = "Not saved yet. Nothing has changed."
    public static let save = "Save"
    public static let saving = "Saving"
    public static func reviewDescription(keyTitle: String) -> String {
        "Saving proposes each change, and it takes effect once you confirm it with \(keyTitle) on the island."
    }

    // All rules, as the console's full list.
    public static let allIntro = "Every rule your AI follows, in full. Each one either lets it go ahead, makes it ask you first, or stops it."
    public static let simplerTitle = "Want the simple version?"
    public static let simplerNote = "Choose Allow, Ask or Deny in plain words, one thing at a time."
    public static let startTitle = "Start from a ready-made rule"
    public static let startNote = "Rules written for you, for force pushes, deploys, payments and secrets. Add one in a click."
    public static let handOver = "See what to hand over"
    public static let propose = "Propose a rule"
    public static let rulesInForce = "Rules in force"
    public static let allTab = "All"
    public static let noRuleHere = "No rule here yet"
    /// The console says nothing more under a filtered empty list; a card here needs a line, so it says when one shows.
    public static let noRuleHereBody = "A rule with this effect shows here once one holds."
    public static let noRules = "No rules yet"
    public static let noRulesBody = "A rule comes from an Allow from now on answer, a ready-made rule, or one proposed here."

    // Autonomy, as the console's hand over page.
    public static let autonomyIntro = "What your agents could start doing on their own, based on what you keep saying yes to."
    public static let readyToHandOver = "Ready to hand over"
    public static let stopAsking = "Stop asking"
    public static let proposing = "Proposing"
    public static let nothingReady = "Nothing ready yet"
    public static let nothingReadyBody = "When you say yes to the same action several times and never no, it shows here as something you can hand over."
    public static let almostCaption = "It needs the same yes a few more times, with no refusal."
    public static let takeBack = "Take it back"
}
