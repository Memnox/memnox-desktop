import Foundation

/// One of the three layer cards on the Memory page, numbered as the long term memory stack reads.
public struct LayerCard: Equatable, Sendable, Identifiable {
    public let number: Int
    /// The file, MEMORY.md, the router's own name, or SKILL.md.
    public let file: String
    /// What the layer is for, in two or three words.
    public let role: String
    /// How it stands now, in a line.
    public let state: String
    /// The layer is there and does its job, so the card draws as settled.
    public let settled: Bool

    public var id: Int { number }
}

/// One line of the value strip, drawn only where the runtime measured the number in it.
public struct ValueLine: Equatable, Sendable, Identifiable {
    public let title: String
    public let figure: String
    public let detail: String

    public var id: String { title }
}

/// How one line of a planned file changes.
public enum PlanDiffMark: String, Sendable {
    case added
    case removed
    case same
}

public struct PlanDiffLine: Equatable, Sendable, Identifiable {
    public let mark: PlanDiffMark
    public let text: String
    /// Its place in the diff, so two equal lines stay two rows.
    public let index: Int

    public var id: Int { index }
}

/// The Layers view's words, every one built here from what the runtime answered, so the page only draws.
public enum MemoryLayersLines {
    /// The router file a project's first agent reads, or CLAUDE.md where it has none yet.
    public static let defaultRouter = "CLAUDE.md"

    public static func cards(_ project: ProjectLayersView) -> [LayerCard] {
        [indexCard(project.index), routerCard(project.routers), skillsCard(project.skills)]
    }

    private static func indexCard(_ index: MemoryIndexLayerView) -> LayerCard {
        guard index.present else {
            return LayerCard(number: 1, file: index.path, role: "every chat", state: "Not written yet", settled: false)
        }
        let lines = count(index.lines, "line")
        let state = index.unlinked == 0
            ? "\(lines), each linked to its file"
            : "\(lines), \(count(index.unlinked, "line")) linked to no file"
        return LayerCard(number: 1, file: index.path, role: "every chat", state: state, settled: index.unlinked == 0)
    }

    private static func routerCard(_ routers: [MemoryRouterLayerView]) -> LayerCard {
        guard let router = routers.first(where: \.present) ?? routers.first else {
            return LayerCard(number: 2, file: defaultRouter, role: "the router", state: "No agent reads one here yet", settled: false)
        }
        guard router.present else {
            return LayerCard(number: 2, file: router.path, role: "the router", state: "Not written yet", settled: false)
        }
        let total = router.departments.count
        let state = total == 0
            ? "\(count(router.lines, "line")), no departments to route"
            : "Routes \(router.routed) of \(count(total, "department"))"
        return LayerCard(number: 2, file: router.path, role: "the router", state: state, settled: router.routed == total)
    }

    private static func skillsCard(_ skills: [MemorySkillLayerView]) -> LayerCard {
        guard !skills.isEmpty else {
            return LayerCard(number: 3, file: "SKILL.md", role: "live data", state: "No SKILL.md in this project", settled: false)
        }
        let live = skills.filter(\.liveData).count
        let state = "\(count(skills.count, "skill")), \(live) say where live data is"
        return LayerCard(number: 3, file: "SKILL.md", role: "live data", state: state, settled: live > 0)
    }

    /// Faster to find and cheaper to find, each only where its number was measured, so nothing is invented.
    public static func value(_ value: MemoryValueView?) -> [ValueLine] {
        guard let value else { return [] }
        var lines: [ValueLine] = []
        if let median = value.searchMedianMs, let searches = value.searches, searches > 0 {
            lines.append(ValueLine(title: "Faster to find", figure: "\(Int(median.rounded())) ms",
                                   detail: "median over the last \(count(searches, "search"))"))
        }
        if let saved = value.contextTokensSaved, saved > 0 {
            lines.append(ValueLine(title: "Cheaper to find", figure: "\(grouped(saved)) tokens",
                                   detail: "not read because memory answered in lines rather than whole"))
        }
        return lines
    }

    /// The short term memory card: the count first, then money only where every model was priced.
    public static func sessionCost(_ cost: SessionCostView) -> [String] {
        var lines = ["\(count(cost.coldReloads, "cold reload")) in \(cost.days) days, over \(count(cost.sessions, "chat"))"]
        if cost.coldReloads > 0 { lines.append("\(grouped(cost.reloadedTokens)) tokens written into the cache again") }
        if let reload = cost.reloadCostUsd { lines.append("Reloading cost \(dollars(reload)) at API prices") }
        if let saving = cost.warmSavingUsd {
            let hours = Int(cost.warmHours.rounded())
            lines.append(saving > 0
                ? "Keeping chats warm \(hours)h would have saved \(dollars(saving))"
                : "Keeping chats warm \(hours)h would have cost more than it saved")
        }
        if !cost.unpricedModels.isEmpty {
            lines.append("No price is known for \(cost.unpricedModels.joined(separator: ", ")), so no total is given")
        }
        return lines
    }

    /// What confirming would write, in a line.
    public static func planSummary(_ plan: MemoryLayersPlan) -> String {
        let changed = plan.files.filter(\.changed).count
        let same = plan.files.count - changed
        if changed == 0 { return "Everything is already as the map would write it." }
        let tail = same == 0 ? "" : ", \(same) already as planned"
        return "Writes \(count(changed, "file"))\(tail). Only what sits inside Memnox's fenced blocks changes."
    }

    /// A line diff from before to after, kept in order, so the sheet shows exactly what moves.
    public static func diff(before: [String], after: [String]) -> [PlanDiffLine] {
        let common = longestCommon(before, after)
        var lines: [(PlanDiffMark, String)] = []
        var b = 0, a = 0
        for line in common {
            while b < before.count, before[b] != line { lines.append((.removed, before[b])); b += 1 }
            while a < after.count, after[a] != line { lines.append((.added, after[a])); a += 1 }
            lines.append((.same, line))
            b += 1
            a += 1
        }
        lines += before[b...].map { (.removed, $0) } + after[a...].map { (.added, $0) }
        return lines.enumerated().map { PlanDiffLine(mark: $1.0, text: $1.1, index: $0) }
    }

    private static func longestCommon(_ x: [String], _ y: [String]) -> [String] {
        guard !x.isEmpty, !y.isEmpty else { return [] }
        var table = Array(repeating: Array(repeating: 0, count: y.count + 1), count: x.count + 1)
        for i in stride(from: x.count - 1, through: 0, by: -1) {
            for j in stride(from: y.count - 1, through: 0, by: -1) {
                table[i][j] = x[i] == y[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var common: [String] = []
        var i = 0, j = 0
        while i < x.count, j < y.count {
            if x[i] == y[j] { common.append(x[i]); i += 1; j += 1 } else if table[i + 1][j] >= table[i][j + 1] { i += 1 } else { j += 1 }
        }
        return common
    }

    /// A keep list typed one line each, blank lines dropped.
    public static func keepList(_ typed: String) -> [String] {
        typed.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func count(_ n: Int, _ noun: String) -> String {
        n == 1 ? "1 \(noun)" : "\(grouped(n)) \(plural(noun))"
    }

    /// Thousands set apart by commas whatever the Mac's locale, so a count reads the same everywhere.
    static func grouped(_ n: Int) -> String {
        let digits = String(abs(n))
        let parts = stride(from: digits.count, to: 0, by: -3).map { end -> String in
            let start = max(0, end - 3)
            return String(digits[digits.index(digits.startIndex, offsetBy: start)..<digits.index(digits.startIndex, offsetBy: end)])
        }
        return (n < 0 ? "-" : "") + parts.reversed().joined(separator: ",")
    }

    private static func plural(_ noun: String) -> String {
        noun.hasSuffix("ch") ? "\(noun)es" : "\(noun)s"
    }

    private static func dollars(_ usd: Double) -> String {
        String(format: "$%.2f", usd)
    }
}
