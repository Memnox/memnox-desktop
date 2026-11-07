import Foundation

// Which names the brain writes this frame. Every candidate is measured where it would be drawn on the screen, then the
// heaviest are placed first and a name that would lie over one already placed is left off, so a dense cluster reads as
// a few clear names rather than a smear. The hovered and the picked are placed before anything else, so they always show.

/// One name that could be written: what it names, the box it would take on the screen, and how much it matters.
public struct LabelCandidate: Equatable, Sendable {
    public let id: Int
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let weight: Double

    public init(id: Int, x: Double, y: Double, width: Double, height: Double, weight: Double) {
        self.id = id
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.weight = weight
    }

    func meets(_ other: LabelCandidate, air: Double) -> Bool {
        x < other.x + other.width + air && other.x < x + width + air && y < other.y + other.height + air && other.y < y + height + air
    }
}

public enum BrainLabels {
    /// The air kept between two names on the screen, in points.
    public static let air = 2.0

    /// The names placed, in the order they were: the ones that must show first whatever they cover, then the rest by
    /// weight, heaviest first with ties by id, each only where it covers none placed before it.
    public static func place(_ candidates: [LabelCandidate], always: Set<Int>) -> [Int] {
        let first = candidates.filter { always.contains($0.id) }.sorted { $0.id < $1.id }
        let rest = candidates.filter { !always.contains($0.id) }
            .sorted { $0.weight == $1.weight ? $0.id < $1.id : $0.weight > $1.weight }
        var placed: [LabelCandidate] = first
        for candidate in rest where !placed.contains(where: { $0.meets(candidate, air: air) }) {
            placed.append(candidate)
        }
        return placed.map(\.id)
    }
}
