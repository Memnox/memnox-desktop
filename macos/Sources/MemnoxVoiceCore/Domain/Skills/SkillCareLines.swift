import Foundation

/// The Skills page's words for a skill's use, its fix backlog and a suggested fix, built here so the page only draws.
public enum SkillCareLines {
    /// Uses, failures and refusals in one line, or that the chats lately never used it.
    public static func counts(_ stats: SkillStatsView?) -> String {
        guard let stats, stats.uses > 0 || stats.failures > 0 || stats.refusals > 0 else {
            return "Not used in the last 30 days"
        }
        let uses = stats.uses == 1 ? "Used once" : "Used \(stats.uses) times"
        let failures = stats.failures == 1 ? "1 failure" : "\(stats.failures) failures"
        let refusals = stats.refusals == 1 ? "1 refusal" : "\(stats.refusals) refusals"
        return "\(uses), \(failures), \(refusals) in the last 30 days"
    }

    /// What Calibrate builds the suggestion from, so the button says it before it is pressed.
    public static func calibrateHint(_ stats: SkillStatsView?) -> String? {
        guard let stats else { return nil }
        let notes = stats.notes.count
        let failures = stats.recentFailures.count
        if notes == 0 && failures == 0 { return "Nothing noted and nothing failed, so there is no fix to suggest." }
        let noted = notes == 1 ? "1 note" : "\(notes) notes"
        let failed = failures == 1 ? "1 failure" : "\(failures) failures"
        return "Builds a Known issues section from \(noted) and \(failed)."
    }

    /// The suggestion's header: the version it moves to and that Accept goes through the hub like any new version.
    public static func suggestionTitle(_ calibration: SkillCalibration, current: String) -> String {
        "Suggested fix: \(current) to \(calibration.draft.version)"
    }

    public static func diff(_ calibration: SkillCalibration) -> [PlanDiffLine] {
        MemoryLayersLines.diff(before: calibration.before, after: calibration.after)
    }

    /// A note as the runtime keeps it, one line, or nil when nothing was typed.
    public static func note(_ typed: String) -> String? {
        let line = typed.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return line.isEmpty ? nil : line
    }
}

/// The order chip on a connector, official first, then CLI, API and community MCP, as the runtime sorts them.
public enum ConnectorOrderLines {
    public static func chip(_ source: ConnectorSource) -> String {
        switch source {
        case .official: return "Official"
        case .cli: return "CLI"
        case .api: return "API"
        case .mcp: return "Community MCP"
        }
    }

    /// The chip for a toolkit, or nil from a runtime that does not say where it comes from.
    public static func chip(for toolkit: ToolkitSummary) -> String? {
        guard let source = toolkit.connectorSource else { return nil }
        guard let weight = toolkit.weight else { return chip(source) }
        return "\(chip(source)) \(weight)"
    }

    /// The legend above the list, so the order is said once rather than guessed from the chips.
    public static let legend = "Searched in order: Official, then CLI, then API, then community MCP"
}
