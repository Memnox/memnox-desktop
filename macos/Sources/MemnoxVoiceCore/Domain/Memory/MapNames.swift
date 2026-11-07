import Foundation

// Which names the map writes under its marks. A busy workspace graph with every name written is a smear of overlapping
// words, so only the heaviest few are named until the pointer or a pick asks for another, and every name is cut short.

public enum MapNames {
    /// How many of the heaviest nodes are named before anything is hovered: enough to read the landmarks.
    public static let mostNamed = 14
    /// The longest name written under a mark, in characters, before it is cut with an ellipsis.
    public static let longest = 28
    private static let ellipsis = "…"

    /// The nodes named at rest: the heaviest by how many lines touch them, as the record weighs them or as the map
    /// draws them, whichever is more, with ties broken by id so the same record names the same nodes.
    public static func named(_ map: MemoryMap, most: Int = mostNamed) -> Set<String> {
        var degree: [String: Int] = [:]
        for edge in map.edges {
            degree[edge.from, default: 0] += 1
            degree[edge.to, default: 0] += 1
        }
        let weighed = map.nodes.map { (id: $0.id, weight: max($0.weight, degree[$0.id] ?? 0)) }
        let heaviest = weighed.sorted { $0.weight == $1.weight ? $0.id < $1.id : $0.weight > $1.weight }
        return Set(heaviest.prefix(most).map(\.id))
    }

    /// Whether a node's name is written: always once hovered or picked, else only for the heavy ones once zoomed in.
    public static func shows(_ id: String, named: Set<String>, hovered: String?, selected: String?, zoomedIn: Bool) -> Bool {
        id == hovered || id == selected || (zoomedIn && named.contains(id))
    }

    /// A name cut to `longest`, on a word where one ends close enough, with an ellipsis so it reads as cut.
    public static func short(_ name: String, longest: Int = longest) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > longest else { return trimmed }
        let head = String(trimmed.prefix(longest))
        let cut = head.lastIndex(of: " ").map { String(head[..<$0]) } ?? head
        // A word end more than half way back would throw away most of the name, so the cut is mid word instead.
        let kept = cut.count * 2 >= longest ? cut : head
        return kept.trimmingCharacters(in: .whitespaces) + ellipsis
    }
}
