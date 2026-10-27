import Foundation

// The brain laid along time: every piece at the moment it was learned, written or last used, from the oldest at the
// left to the newest at the right, in a lane to each layer. What says no time stands in a row of its own at the foot of
// its layer's lane, spread evenly from one side to the other rather than stacked in one column, as the console lays it,
// and a layer with nothing dated gives its whole lane to that row. Every spot is a hash of its id or a step of the row,
// so the same record lays out the same way.

/// A mark on the time axis: where it is across the world and the moment it stands for.
public struct BrainTick: Equatable, Sendable {
    public let x: Double
    public let at: Date
}

public struct BrainTimelineLayout: Equatable, Sendable {
    /// Each node's spot, by the index it was given in.
    public let spots: [(x: Double, y: Double)]
    public let ticks: [BrainTick]
    /// Each layer's lane, by its middle across the world, for the lane's name.
    public let lanes: [(layer: BrainLayer, y: Double)]
    /// Each layer's row of what says no time, by its first row's middle, for the row's name.
    public let undated: [(layer: BrainLayer, y: Double)]

    public static func == (left: BrainTimelineLayout, right: BrainTimelineLayout) -> Bool {
        left.spots.elementsEqual(right.spots) { $0.x == $1.x && $0.y == $1.y } && left.ticks == right.ticks
            && left.lanes.elementsEqual(right.lanes) { $0.layer == $1.layer && $0.y == $1.y }
            && left.undated.elementsEqual(right.undated) { $0.layer == $1.layer && $0.y == $1.y }
    }
}

public enum BrainTimeline {
    /// How tall each layer's lane is, in world points, and the air between two.
    public static let laneHeight = 120.0
    public static let laneGap = 36.0
    /// The share of a lane its undated row takes when the lane holds dated marks too, the console's.
    public static let undatedShare = 0.32
    /// The least distance between two undated marks along a row, in world points.
    public static let undatedSpacing = 18.0
    /// How far a dated mark may stray across its band, as a share of it, so a day's marks do not stack.
    public static let datedSpread = 0.8
    /// How many moments the axis is marked at.
    public static let tickCount = 5
    /// A hash's fraction less this is centred on its band, and a row's step is centred on its cell.
    private static let centred = 0.5
    private static let jitterSalt: UInt64 = 81
    private static let spreadSalt: UInt64 = 82

    /// Reads a time as the runtime writes it, with or without fractions of a second.
    public static func moment(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    /// Each node across the brain's length by its moment, in its layer's lane, the lanes stacked from the core's down,
    /// and what says no time in its lane's own row, ordered by name so a row reads as a list.
    public static func layout(ids: [String], layers: [BrainLayer], moments: [Date?], labels: [String]? = nil) -> BrainTimelineLayout {
        let width = 2 * BrainOutline.halfLength
        let left = -BrainOutline.halfLength
        let dated = moments.compactMap { $0 }
        let oldest = dated.min()
        let newest = dated.max()
        var length = 0.0
        if let oldest, let newest { length = newest.timeIntervalSince(oldest) }
        let present = BrainLayer.allCases.filter(layers.contains)
        let stack = Double(present.count) * laneHeight + Double(max(present.count - 1, 0)) * laneGap
        let top = BrainOutline.middle.y - stack / 2
        var spots: [(x: Double, y: Double)] = Array(repeating: (left, BrainOutline.middle.y), count: ids.count)
        var lanes: [(layer: BrainLayer, y: Double)] = []
        var rows: [(layer: BrainLayer, y: Double)] = []
        for (order, layer) in present.enumerated() {
            let laneTop = top + Double(order) * (laneHeight + laneGap)
            lanes.append((layer, laneTop + laneHeight / 2))
            let mine = ids.indices.filter { layers[$0] == layer }
            let timed = mine.filter { moments[$0] != nil }
            let loose = mine.filter { moments[$0] == nil }
            let split = timed.isEmpty ? laneTop : loose.isEmpty ? laneTop + laneHeight : laneTop + laneHeight * (1 - undatedShare)
            let band = split - laneTop
            for index in timed {
                guard let moment = moments[index], let oldest else { continue }
                let share = length > 0 ? moment.timeIntervalSince(oldest) / length : SurfaceOrbit.unit(ids[index], salt: spreadSalt)
                let jitter = (SurfaceOrbit.unit(ids[index], salt: jitterSalt) - centred) * band * datedSpread
                spots[index] = (left + share * width, laneTop + band / 2 + jitter)
            }
            guard !loose.isEmpty else { continue }
            let named = { (index: Int) in labels?[index] ?? ids[index] }
            let ordered = loose.sorted { named($0) == named($1) ? ids[$0] < ids[$1] : named($0) < named($1) }
            let cells = undatedCells(ordered.count, width: width, height: laneTop + laneHeight - split)
            for (at, index) in ordered.enumerated() { spots[index] = (left + cells[at].x, split + cells[at].y) }
            rows.append((layer, split + (cells.first?.y ?? 0)))
        }
        var ticks: [BrainTick] = []
        if let oldest, length > 0 {
            ticks = (0..<tickCount).map { step in
                let share = Double(step) / Double(tickCount - 1)
                return BrainTick(x: left + share * width, at: oldest.addingTimeInterval(share * length))
            }
        } else if let oldest {
            ticks = [BrainTick(x: 0, at: oldest)]
        }
        return BrainTimelineLayout(spots: spots, ticks: ticks, lanes: lanes, undated: rows)
    }

    /// Where each of this many undated marks sits in a band this wide and tall from its top left: rows as long as
    /// the spacing allows, each spread evenly across the whole width, so no two share a spot.
    public static func undatedCells(_ count: Int, width: Double, height: Double) -> [(x: Double, y: Double)] {
        guard count > 0 else { return [] }
        let perRow = max(1, Int(width / undatedSpacing))
        let rows = Int((Double(count) / Double(perRow)).rounded(.up))
        let rowHeight = height / Double(rows)
        return (0..<count).map { at in
            let row = at / perRow
            let inRow = min(perRow, count - row * perRow)
            let column = at - row * perRow
            return ((Double(column) + centred) / Double(inRow) * width, rowHeight * (Double(row) + centred))
        }
    }
}
